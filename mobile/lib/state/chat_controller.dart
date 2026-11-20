import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/chat_models.dart';
import '../data/models/provider.dart';
import '../data/services/auth_service.dart';
import '../data/services/baizhi_web_search_service.dart';
import '../data/services/chat_service.dart';
import '../data/services/chat_storage_service.dart';
import '../data/services/key_store.dart';
import '../data/services/model_service.dart';
import 'settings_controller.dart';

CharacterCard emptyCharacter() => CharacterCard(
      id: '',
      name: '助手',
      systemPrompt: '',
      firstMessage: '',
      temperature: 0.7,
      createdAt: 0,
    );

/// Owns session tree state, streaming and model selection.
///
/// Concurrency notes:
/// 1. Each reply gets a monotonically increasing generation token; late
///    callbacks from a stopped or replaced stream are ignored.
/// 2. UI updates during streaming are coalesced on a 120ms ticker so token
///    bursts cannot starve the frame pipeline.
class ChatController extends ChangeNotifier {
  ChatController({
    required ChatStorageService storage,
    required SettingsController settings,
    required KeyStore keyStore,
    required AuthService auth,
  })  : _storage = storage,
        _settings = settings,
        _keyStore = keyStore,
        _auth = auth;

  final ChatStorageService _storage;
  final SettingsController _settings;
  final KeyStore _keyStore;
  final AuthService _auth;

  final List<ChatSession> _sessions = <ChatSession>[];
  final List<CharacterCard> _characters = <CharacterCard>[];
  final List<UserIdentityCard> _identities = <UserIdentityCard>[];
  final List<ModelInfo> _availableModels = <ModelInfo>[];
  final List<ProviderDefinition> _configuredProviders = <ProviderDefinition>[];
  final Set<String> _collapsedReasons = <String>{};

  ChatSession? _draft;
  String _currentSessionId = '';
  String _currentCharacterId = '';
  String _currentProviderId = 'deepseek';
  String _currentModelId = '';
  String _currentApiKey = '';
  bool _enableThinking = true;
  bool _enableWebSearch = true;
  bool _isGenerating = false;
  bool _fetchingModels = false;
  bool _initialized = false;
  String _noticeText = '';
  StreamSubscription<ChatStreamEvent>? _subscription;
  Timer? _ticker;
  int _seq = 0;
  int _generation = 0;

  bool get initialized => _initialized;
  List<ChatSession> get sessions => List<ChatSession>.unmodifiable(_sessions);
  List<CharacterCard> get characters =>
      List<CharacterCard>.unmodifiable(_characters);
  List<UserIdentityCard> get identities =>
      List<UserIdentityCard>.unmodifiable(_identities);
  List<ModelInfo> get availableModels =>
      List<ModelInfo>.unmodifiable(_availableModels);
  List<ProviderDefinition> get configuredProviders =>
      List<ProviderDefinition>.unmodifiable(_configuredProviders);
  String get currentSessionId => _currentSessionId;
  String get currentCharacterId => _currentCharacterId;
  String get currentProviderId => _currentProviderId;
  String get currentModelId => _currentModelId;
  bool get enableThinking => _enableThinking;
  bool get enableWebSearch => _enableWebSearch;
  bool get isGenerating => _isGenerating;
  bool get fetchingModels => _fetchingModels;
  String get noticeText => _noticeText;

  ChatSession? get currentSession {
    final ChatSession? draft = _draft;
    if (draft != null && draft.id == _currentSessionId) {
      return draft;
    }
    for (final ChatSession session in _sessions) {
      if (session.id == _currentSessionId) {
        return session;
      }
    }
    return null;
  }

  List<ChatMessage> get activePath {
    final ChatSession? session = currentSession;
    if (session == null) {
      return const <ChatMessage>[];
    }
    final List<ChatMessage> path = <ChatMessage>[];
    String cursor = session.activeRootId;
    int guard = 0;
    while (cursor.isNotEmpty && guard < 2000) {
      guard++;
      final ChatMessage? node = findMessage(session, cursor);
      if (node == null) {
        break;
      }
      path.add(node);
      cursor = node.activeChildId;
    }
    return path;
  }

  String get providerName =>
      findProvider(_currentProviderId)?.name ?? _currentProviderId;

  bool get thinkingSupported =>
      isThinkingSupported(_currentProviderId, _currentModelId);

  String get sessionTitle => currentSession?.title ?? '新对话';

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    _characters
      ..clear()
      ..addAll(await _storage.loadCharacters());
    _identities
      ..clear()
      ..addAll(await _storage.loadIdentities());
    final List<ChatSession> loaded = await _storage.loadSessions();
    final List<ChatSession> kept = loaded
        .where((ChatSession s) => s.messages.isNotEmpty)
        .toList(growable: false);
    _sessions
      ..clear()
      ..addAll(kept);
    if (kept.length != loaded.length) {
      await _storage.saveSessions(_sessions);
    }
    if (_characters.isNotEmpty) {
      _currentCharacterId = _characters.first.id;
    }
    _createNewSessionInternal();
    await loadConfiguredProviders();
    if (_configuredProviders.isNotEmpty) {
      _currentProviderId = _configuredProviders.first.id;
      final ChatSession? draft = _draft;
      if (draft != null) {
        draft.providerId = _currentProviderId;
      }
    }
    await _reloadApiKey();
    unawaited(refreshModelList());
    _initialized = true;
    notifyListeners();
  }

  // ── Session tree helpers ──

  ChatMessage? findMessage(ChatSession session, String id) {
    for (final ChatMessage m in session.messages) {
      if (m.id == id) {
        return m;
      }
    }
    return null;
  }

  List<ChatMessage> pathToNode(ChatSession session, String targetId) {
    final List<ChatMessage> rev = <ChatMessage>[];
    String cursor = targetId;
    int guard = 0;
    while (cursor.isNotEmpty && guard < 2000) {
      guard++;
      final ChatMessage? node = findMessage(session, cursor);
      if (node == null) {
        break;
      }
      rev.add(node);
      cursor = node.parentId;
    }
    return rev.reversed.toList(growable: false);
  }

  List<ChatMessage> historyTo(ChatSession session, String targetId) {
    final List<ChatMessage> full = pathToNode(session, targetId);
    return full
        .where((ChatMessage m) =>
            (m.isUser || m.isAssistant) && m.content.isNotEmpty)
        .toList(growable: false);
  }

  List<String> siblingsOf(ChatSession session, ChatMessage message) {
    if (message.parentId.isEmpty) {
      return List<String>.from(session.rootIds);
    }
    final ChatMessage? parent = findMessage(session, message.parentId);
    if (parent == null) {
      return <String>[message.id];
    }
    return List<String>.from(parent.childIds);
  }

  int siblingIndex(ChatSession session, ChatMessage message) {
    final List<String> siblings = siblingsOf(session, message);
    final int index = siblings.indexOf(message.id);
    return index < 0 ? 0 : index;
  }

  int branchCount(ChatMessage message) {
    final ChatSession? session = currentSession;
    return session == null ? 1 : siblingsOf(session, message).length;
  }

  int branchIndex(ChatMessage message) {
    final ChatSession? session = currentSession;
    return session == null ? 0 : siblingIndex(session, message);
  }

  String nextId(String role) {
    _seq++;
    return 'msg_${role}_${DateTime.now().millisecondsSinceEpoch}_$_seq';
  }

  ChatMessage buildMessage(MessageRole role, String content, String parentId) {
    return ChatMessage(
      id: nextId(ChatMessage.roleToWire(role)),
      role: role,
      content: content,
      reasoningContent: role == MessageRole.assistant ? '' : null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      status: MessageStatus.success,
      parentId: parentId,
    );
  }

  void attach(ChatSession session, ChatMessage node) {
    _promoteDraftIfNeeded(session);
    session.messages.add(node);
    if (node.parentId.isEmpty) {
      session.rootIds.add(node.id);
      session.activeRootId = node.id;
      return;
    }
    final ChatMessage? parent = findMessage(session, node.parentId);
    if (parent == null) {
      node.parentId = '';
      session.rootIds.add(node.id);
      session.activeRootId = node.id;
      return;
    }
    parent.childIds.add(node.id);
    parent.activeChildId = node.id;
  }

  void _promoteDraftIfNeeded(ChatSession session) {
    final ChatSession? draft = _draft;
    if (draft == null || draft.id != session.id) {
      return;
    }
    _draft = null;
    _sessions.insert(0, session);
    unawaited(_saveState());
  }

  // ── Session lifecycle ──

  void _createNewSessionInternal() {
    _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    _draft = ChatSession(
      id: _currentSessionId,
      title: '新对话',
      characterId: '',
      providerId: _currentProviderId,
      modelId: _currentModelId,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _currentCharacterId = '';
    _noticeText = '';
    _collapsedReasons.clear();
  }

  void createNewSession() {
    _createNewSessionInternal();
    notifyListeners();
  }

  Future<void> switchSession(String sessionId) async {
    if (_draft != null && _draft!.id != sessionId) {
      _draft = null;
    }
    _currentSessionId = sessionId;
    final ChatSession? session = currentSession;
    if (session != null) {
      _currentProviderId = session.providerId;
      _currentModelId = session.modelId;
      _currentCharacterId = session.characterId;
      await _reloadApiKey();
      await refreshModelList();
    }
    _initCollapsedReasons();
    await _storage.saveActiveSessionId(sessionId);
    notifyListeners();
  }

  Future<void> openSessionWithPrivacy(ChatSession session) async {
    if (session.isPrivate) {
      final bool ok = await _auth.authenticate('解锁保密对话');
      if (!ok) {
        return;
      }
    }
    await switchSession(session.id);
  }

  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((ChatSession s) => s.id == sessionId);
    if (_currentSessionId == sessionId) {
      final String nextId = _firstNonPrivateSessionId();
      if (nextId.isNotEmpty) {
        await switchSession(nextId);
      } else {
        _createNewSessionInternal();
      }
    }
    await _saveState();
    notifyListeners();
  }

  String _firstNonPrivateSessionId() {
    for (final ChatSession s in _sessions) {
      if (!s.isPrivate) {
        return s.id;
      }
    }
    return '';
  }

  Future<void> renameSession(String sessionId, String title) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      return;
    }
    for (final ChatSession s in _sessions) {
      if (s.id == sessionId) {
        s.title = trimmed;
        break;
      }
    }
    await _saveState();
    notifyListeners();
  }

  Future<void> toggleSessionPrivacy(String sessionId) async {
    ChatSession? session;
    for (final ChatSession s in _sessions) {
      if (s.id == sessionId) {
        session = s;
        break;
      }
    }
    if (session == null) {
      return;
    }
    if (session.isPrivate) {
      final bool ok = await _auth.authenticate('取消保密需要验证身份');
      if (!ok) {
        return;
      }
      session.isPrivate = false;
    } else {
      session.isPrivate = true;
    }
    await _saveState();
    notifyListeners();
  }

  bool sessionIsPrivate(String sessionId) {
    for (final ChatSession s in _sessions) {
      if (s.id == sessionId) {
        return s.isPrivate;
      }
    }
    return false;
  }

  // ── Characters and identities ──

  CharacterCard? characterById(String id) {
    for (final CharacterCard c in _characters) {
      if (c.id == id) {
        return c;
      }
    }
    return null;
  }

  UserIdentityCard? identityById(String id) {
    for (final UserIdentityCard c in _identities) {
      if (c.id == id) {
        return c;
      }
    }
    return null;
  }

  CharacterCard get currentCharacter =>
      characterById(_currentCharacterId) ?? emptyCharacter();

  Future<CharacterCard> saveCharacter({
    String? id,
    required String name,
    required String systemPrompt,
    required String firstMessage,
    required double temperature,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('角色名称不能为空');
    }
    CharacterCard? updated;
    for (int i = 0; i < _characters.length; i++) {
      final CharacterCard c = _characters[i];
      if (c.id == id) {
        updated = CharacterCard(
          id: c.id,
          name: trimmed,
          avatarIcon: c.avatarIcon,
          description: c.description,
          systemPrompt: systemPrompt.trim(),
          firstMessage: firstMessage.trim(),
          temperature: temperature,
          knowledge: c.knowledge,
          createdAt: c.createdAt,
        );
        _characters[i] = updated;
        break;
      }
    }
    updated ??= CharacterCard(
      id: 'char_${DateTime.now().millisecondsSinceEpoch}',
      name: trimmed,
      systemPrompt: systemPrompt.trim(),
      firstMessage: firstMessage.trim(),
      temperature: temperature,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (!_characters.contains(updated)) {
      _characters.insert(0, updated);
    }
    _currentCharacterId = updated.id;
    await _storage.saveCharacters(_characters);
    notifyListeners();
    return updated;
  }

  Future<void> deleteCharacter(String id) async {
    _characters.removeWhere((CharacterCard c) => c.id == id);
    if (_currentCharacterId == id) {
      _currentCharacterId = '';
      final ChatSession? session = currentSession;
      if (session != null) {
        session.characterId = '';
      }
    }
    await _storage.saveCharacters(_characters);
    await _saveState();
    notifyListeners();
  }

  void selectCharacterForDraft(String characterId) {
    _currentCharacterId = characterId;
    final ChatSession? session = currentSession;
    if (session != null && session.messages.isEmpty) {
      session.characterId = characterId;
      session.participantIds = characterId.isEmpty ? <String>[] : <String>[characterId];
      _currentCharacterId = characterId;
    }
    notifyListeners();
  }

  void selectIdentityForDraft(String identityId) {
    final ChatSession? session = currentSession;
    if (session != null && session.messages.isEmpty) {
      session.userIdentityId = identityId;
      notifyListeners();
    }
  }

  Future<void> saveIdentity({
    String? id,
    required String name,
    required String persona,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('身份名称不能为空');
    }
    UserIdentityCard? updated;
    for (int i = 0; i < _identities.length; i++) {
      final UserIdentityCard c = _identities[i];
      if (c.id == id) {
        updated = UserIdentityCard(
          id: c.id,
          name: trimmed,
          persona: persona.trim(),
          createdAt: c.createdAt,
        );
        _identities[i] = updated;
        break;
      }
    }
    updated ??= UserIdentityCard(
      id: 'identity_${DateTime.now().millisecondsSinceEpoch}',
      name: trimmed,
      persona: persona.trim(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (!_identities.contains(updated)) {
      _identities.insert(0, updated);
    }
    await _storage.saveIdentities(_identities);
    notifyListeners();
  }

  Future<void> deleteIdentity(String id) async {
    _identities.removeWhere((UserIdentityCard c) => c.id == id);
    await _storage.saveIdentities(_identities);
    await _saveState();
    notifyListeners();
  }

  /// Binds the selected character/identity to the current draft on confirm.
  Future<void> bindDraftParticipants({
    required String characterId,
    required String identityId,
  }) async {
    final ChatSession? session = currentSession;
    if (session == null) {
      return;
    }
    if (session.characterId.isNotEmpty ||
        session.participantIds.isNotEmpty ||
        session.userIdentityId.isNotEmpty) {
      return;
    }
    session.characterId = characterId;
    session.participantIds = characterId.isEmpty ? <String>[] : <String>[characterId];
    session.userIdentityId = identityId;
    _currentCharacterId = characterId;
    final CharacterCard? c = characterById(characterId);
    if (c != null &&
        c.firstMessage.trim().isNotEmpty &&
        session.messages.isEmpty) {
      final ChatMessage welcome = buildMessage(
        MessageRole.assistant,
        c.firstMessage.trim(),
        '',
      );
      attach(session, welcome);
    }
    await _saveState();
    notifyListeners();
  }

  // ── Providers and models ──

  Future<void> loadConfiguredProviders() async {
    final List<ProviderDefinition> out = <ProviderDefinition>[];
    for (final ProviderDefinition p in providers) {
      final String key = await _keyStore.read(KeyStore.providerKey(p.id));
      if (key.trim().isNotEmpty) {
        out.add(p);
      }
    }
    _configuredProviders
      ..clear()
      ..addAll(out);
    notifyListeners();
  }

  Future<void> _reloadApiKey() async {
    _currentApiKey = await _keyStore.read(KeyStore.providerKey(_currentProviderId));
  }

  Future<void> refreshModelList() async {
    _fetchingModels = true;
    notifyListeners();
    try {
      final List<ModelInfo> models =
          await ModelService.fetchModels(_currentProviderId, _currentApiKey);
      _availableModels
        ..clear()
        ..addAll(models);
      if (models.isNotEmpty &&
          !models.any((ModelInfo m) => m.id == _currentModelId)) {
        _currentModelId = models.first.id;
        final ChatSession? session = currentSession;
        if (session != null) {
          session.modelId = _currentModelId;
        }
        unawaited(_saveState());
      }
    } finally {
      _fetchingModels = false;
      notifyListeners();
    }
  }

  Future<void> selectProvider(String providerId) async {
    _currentProviderId = providerId;
    final ChatSession? session = currentSession;
    if (session != null) {
      session.providerId = providerId;
    }
    await _reloadApiKey();
    await refreshModelList();
    if (thinkingSupported) {
      _enableThinking = true;
    }
    await _saveState();
    notifyListeners();
  }

  Future<void> selectModel(String modelId) async {
    _currentModelId = modelId;
    final ChatSession? session = currentSession;
    if (session != null) {
      session.modelId = modelId;
    }
    if (isThinkingSupported(_currentProviderId, modelId)) {
      _enableThinking = true;
    }
    await _saveState();
    notifyListeners();
  }

  void setEnableThinking(bool value) {
    _enableThinking = value;
    notifyListeners();
  }

  void setEnableWebSearch(bool value) {
    _enableWebSearch = value;
    notifyListeners();
  }

  void clearNotice() {
    if (_noticeText.isEmpty) {
      return;
    }
    _noticeText = '';
    notifyListeners();
  }

  bool _canSend() {
    if (_currentApiKey.trim().isEmpty) {
      _noticeText = '未配置 [$providerName] 的 API Key，请先在设置中添加';
      notifyListeners();
      return false;
    }
    if (_currentModelId.trim().isEmpty || _currentModelId == '选择模型') {
      _noticeText = '请先点击右上角选择一个有效模型';
      notifyListeners();
      return false;
    }
    _noticeText = '';
    return true;
  }

  // ── Sending and streaming ──

  Future<void> sendMessage(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || _isGenerating) {
      return;
    }
    final ChatSession? session = currentSession;
    if (session == null || !_canSend()) {
      return;
    }
    if (session.title == '新对话') {
      session.title =
          trimmed.length > 14 ? '${trimmed.substring(0, 14)}...' : trimmed;
    }
    final List<ChatMessage> path = activePath;
    final String parentId = path.isEmpty ? '' : path.last.id;
    final ChatMessage userMsg =
        buildMessage(MessageRole.user, trimmed, parentId);
    attach(session, userMsg);
    session.updatedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    generateReply(session, userMsg, currentCharacter);
  }

  Future<void> generateReply(
    ChatSession session,
    ChatMessage parentMessage,
    CharacterCard speaker,
  ) async {
    final ChatMessage assistant = buildMessage(
      MessageRole.assistant,
      '',
      parentMessage.id,
    )
      ..status = MessageStatus.streaming
      ..speakerId = speaker.id;
    attach(session, assistant);
    session.updatedAt = DateTime.now().millisecondsSinceEpoch;

    _isGenerating = true;
    _generation++;
    final int token = _generation;
    _startTicker();
    notifyListeners();

    final List<ChatMessage> rawHistory = historyTo(session, parentMessage.id);
    final String identityName = _currentIdentityName(session);
    final List<ChatMessage> history = rawHistory.map((ChatMessage m) {
      if (m.isUser && identityName.isNotEmpty && m.content.isNotEmpty) {
        return ChatMessage(
          id: m.id,
          role: m.role,
          content: '$identityName：${m.content}',
          createdAt: m.createdAt,
          status: m.status,
          parentId: m.parentId,
          reasoningContent: m.reasoningContent,
        );
      }
      return ChatMessage(
        id: m.id,
        role: m.role,
        content: m.content,
        createdAt: m.createdAt,
        status: m.status,
        parentId: m.parentId,
        reasoningContent: m.reasoningContent,
      );
    }).toList(growable: false);

    // 百智云联网搜索：发送前先检索，把摘要注入系统提示、来源挂到本条消息。
    // Business Rule: 检索失败降级为普通回答，绝不阻塞对话。
    String webContext = '';
    if (_enableWebSearch &&
        _settings.webSearchProvider == webSearchProviderBaizhi) {
      assistant
        ..searching = true
        ..searchHint = '正在联网搜索…';
      notifyListeners();
      try {
        final String key = await _settings.readBaizhiWebKey();
        final List<SearchSource> results =
            await BaizhiWebSearchService.search(parentMessage.content, key);
        if (results.isNotEmpty) {
          assistant.sources = results;
          webContext = BaizhiWebSearchService.buildContext(results);
        }
      } catch (error) {
        assistant.searchHint = '联网搜索失败，改为普通回答';
      }
      assistant.searching = false;
      notifyListeners();
    }
    final List<CitationRange> citations = <CitationRange>[];
    final int thinkingStart = DateTime.now().millisecondsSinceEpoch;
    int thinkingEnd = 0;
    bool finished = false;

    void complete({required bool stopped}) {
      if (finished) {
        return;
      }
      finished = true;
      if (token != _generation) {
        return;
      }
      _stopTicker();
      _subscription = null;
      if (assistant.content.isEmpty && assistant.status == MessageStatus.streaming) {
        assistant.status = MessageStatus.success;
      } else if (assistant.status == MessageStatus.streaming) {
        assistant.status = MessageStatus.success;
      }
      if ((assistant.reasoningContent ?? '').isNotEmpty) {
        if (assistant.thinkingDuration == null) {
          final int end = thinkingEnd > 0 ? thinkingEnd : DateTime.now().millisecondsSinceEpoch;
          assistant.thinkingDuration =
              ((end - thinkingStart) / 1000).round().clamp(1, 1 << 30).toInt();
        }
        if (_settings.autoCollapseThinking) {
          _collapsedReasons.add(assistant.id);
        }
      }
      assistant.searching = false;
      assistant.searchHint = null;
      if (citations.isNotEmpty && assistant.content.isNotEmpty) {
        assistant.content = injectCitationMarkers(
          assistant.content,
          citations,
          assistant.sources,
        );
      }      _isGenerating = false;
      unawaited(_saveState());
      notifyListeners();
      if (!stopped) {
      }
    }

    void fail(Object error) {
      if (finished) {
        return;
      }
      finished = true;
      if (token != _generation) {
        return;
      }
      _stopTicker();
      _subscription = null;
      assistant
        ..status = MessageStatus.error
        ..errorMessage = error is ChatException ? error.message : '$error';
      _isGenerating = false;
      unawaited(_saveState());
      notifyListeners();
    }

    final Stream<ChatStreamEvent> stream = ChatService.streamChat(
      ChatRequestOptions(
        providerId: _currentProviderId,
        apiKey: _currentApiKey,
        model: _currentModelId,
        temperature: speaker.temperature,
        messages: history,
        systemPrompt: _systemPromptFor(session, speaker) +
            (webContext.isEmpty ? '' : '\n\n$webContext'),
        enableThinking: _enableThinking,
        reasoningEffort: 'high',

        enableWebSearch: _enableWebSearch &&
            _settings.webSearchProvider != webSearchProviderBaizhi,
      ),
    );

    _subscription = stream.listen(
      (ChatStreamEvent event) {
        if (token != _generation) {
          return;
        }
        if (event.done) {
          complete(stopped: false);
          return;
        }
        if (event.searchHint.isNotEmpty) {
          assistant.searchHint = event.searchHint;
          assistant.searching = event.searchHint.contains('正在');
        }
        if (event.sources.isNotEmpty) {
          for (final SearchSource source in event.sources) {
            if (!assistant.sources.any((SearchSource s) => s.url == source.url)) {
              assistant.sources.add(source);
            }
          }
        }
        if (event.citations.isNotEmpty) {
          citations.addAll(event.citations);
        }
        if (event.title.isNotEmpty &&
            _settings.featureTitle &&
            session.title == '新对话') {
          session.title = event.title;
        }
        if (event.reasoning.isNotEmpty) {
          assistant.reasoningContent =
              (assistant.reasoningContent ?? '') + event.reasoning;
          _collapsedReasons.remove(assistant.id);
        }
        if (event.content.isNotEmpty) {
          if (thinkingEnd == 0 &&
              (assistant.reasoningContent ?? '').isNotEmpty) {
            thinkingEnd = DateTime.now().millisecondsSinceEpoch;
            assistant.thinkingDuration =
                ((thinkingEnd - thinkingStart) / 1000).round().clamp(1, 1 << 30).toInt();
            if (_settings.autoCollapseThinking) {
              _collapsedReasons.add(assistant.id);
            }
          }
          assistant.content += event.content;
        }
      },
      onError: fail,
      onDone: () => complete(stopped: false),
      cancelOnError: true,
    );
  }

  void stopGenerating() {
    if (!_isGenerating) {
      return;
    }
    _generation++;
    final StreamSubscription<ChatStreamEvent>? sub = _subscription;
    _subscription = null;
    unawaited(sub?.cancel());
    _stopTicker();
    _isGenerating = false;
    final List<ChatMessage> path = activePath;
    if (path.isNotEmpty) {
      final ChatMessage last = path.last;
      if (last.status == MessageStatus.streaming) {
        last.status = MessageStatus.success;
        if ((last.reasoningContent ?? '').isNotEmpty &&
            last.thinkingDuration == null) {
          last.thinkingDuration = 1;
        }
        final ChatSession? session = currentSession;
        if (session != null) {
          final ChatMessage? parent = findMessage(session, last.parentId);
          if (parent != null) {
          }
        }
      }
    }
    unawaited(_saveState());
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (_isGenerating) {
        notifyListeners();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  String _systemPromptFor(ChatSession session, CharacterCard speaker) {
    final String base = speaker.systemPrompt.trim();
    String persona = '';
    if (session.userIdentityId.isNotEmpty) {
      final UserIdentityCard? identity = identityById(session.userIdentityId);
      if (identity != null) {
        persona = identity.persona.trim().isEmpty
            ? '【与你对话的用户在剧中身份】：「${identity.name}」'
            : '【与你对话的用户在剧中身份】：「${identity.name}」—— ${identity.persona.trim()}';
      }
    }
    if (persona.isEmpty) {
      return base;
    }
    return base.isEmpty ? persona : '$base\n\n$persona';
  }

  String _currentIdentityName(ChatSession session) {
    if (session.userIdentityId.isEmpty) {
      return '';
    }
    return identityById(session.userIdentityId)?.name ?? '';
  }

  // ── Message actions ──

  bool isReasonCollapsed(String id) => _collapsedReasons.contains(id);

  void toggleReason(String id) {
    if (_collapsedReasons.contains(id)) {
      _collapsedReasons.remove(id);
    } else {
      _collapsedReasons.add(id);
    }
    notifyListeners();
  }

  bool isThinkingStreaming(ChatMessage message) =>
      message.status == MessageStatus.streaming && message.content.isEmpty;

  String reasonTitle(ChatMessage message) {
    if (isThinkingStreaming(message)) {
      return '正在思考...';
    }
    final int seconds = (message.thinkingDuration ?? 0) > 0
        ? message.thinkingDuration!
        : 1;
    return '已思考（用时 $seconds 秒）';
  }

  Future<void> regenerate(String assistantId) async {
    final ChatSession? session = currentSession;
    if (session == null || _isGenerating) {
      return;
    }
    final ChatMessage? assistant = findMessage(session, assistantId);
    if (assistant == null || !assistant.isAssistant) {
      return;
    }
    final ChatMessage? user = findMessage(session, assistant.parentId);
    if (user == null || !_canSend()) {
      return;
    }
    CharacterCard speaker = currentCharacter;
    final CharacterCard? bySpeaker = characterById(assistant.speakerId);
    if (bySpeaker != null) {
      speaker = bySpeaker;
    }
    generateReply(session, user, speaker);
  }

  Future<void> editAndResend(String userId, String newText) async {
    final ChatSession? session = currentSession;
    final String trimmed = newText.trim();
    if (session == null || _isGenerating || trimmed.isEmpty || !_canSend()) {
      return;
    }
    final ChatMessage? original = findMessage(session, userId);
    if (original == null || !original.isUser) {
      return;
    }
    final ChatMessage replacement =
        buildMessage(MessageRole.user, trimmed, original.parentId);
    replacement.mentionedIds = List<String>.from(original.mentionedIds);
    attach(session, replacement);
    session.updatedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    generateReply(session, replacement, currentCharacter);
  }

  Future<void> switchBranch(String messageId, int delta) async {
    if (_isGenerating) {
      return;
    }
    final ChatSession? session = currentSession;
    if (session == null) {
      return;
    }
    final ChatMessage? message = findMessage(session, messageId);
    if (message == null) {
      return;
    }
    final List<String> siblings = siblingsOf(session, message);
    if (siblings.length <= 1) {
      return;
    }
    int index = siblingIndex(session, message) + delta;
    if (index < 0 || index >= siblings.length) {
      return;
    }
    final String target = siblings[index];
    if (message.parentId.isEmpty) {
      session.activeRootId = target;
    } else {
      final ChatMessage? parent = findMessage(session, message.parentId);
      if (parent == null) {
        return;
      }
      parent.activeChildId = target;
    }
    session.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _saveState();
    notifyListeners();
  }

  void _initCollapsedReasons() {
    _collapsedReasons.clear();
    final ChatSession? session = currentSession;
    if (session == null) {
      return;
    }
    for (final ChatMessage m in session.messages) {
      if ((m.reasoningContent ?? '').isNotEmpty) {
        _collapsedReasons.add(m.id);
      }
    }
  }

  Future<void> _saveState() async {
    await _storage.saveSessions(_sessions);
    await _storage.saveActiveSessionId(
      _draft != null ? '' : _currentSessionId,
    );
  }

  @override
  void dispose() {
    _stopTicker();
    _subscription?.cancel();
    super.dispose();
  }
}

/// 在正文引用区间的末尾插入 [N](#cite-N) 标记。
///
/// Business Rule: 偏移以 Unicode 码点计（与 DeepSeek annotations 一致），
/// 越界或找不到来源的区间直接跳过，不影响正文。
String injectCitationMarkers(
  String content,
  List<CitationRange> citations,
  List<SearchSource> sources,
) {
  if (content.isEmpty || citations.isEmpty) {
    return content;
  }
  final Map<int, List<int>> atEnd = <int, List<int>>{};
  for (final CitationRange cite in citations) {
    final int number =
        sources.indexWhere((SearchSource s) => s.url == cite.url) + 1;
    if (number <= 0 || cite.end < 0) {
      continue;
    }
    final List<int> numbers = atEnd.putIfAbsent(cite.end, () => <int>[]);
    if (!numbers.contains(number)) {
      numbers.add(number);
    }
  }
  if (atEnd.isEmpty) {
    return content;
  }
  final StringBuffer out = StringBuffer();
  int index = 0;
  for (final int rune in content.runes) {
    out.writeCharCode(rune);
    index++;
    final List<int>? numbers = atEnd[index];
    if (numbers == null) {
      continue;
    }
    numbers.sort();
    for (final int number in numbers) {
      final String marker = number.toString();
      out.write('[$marker](#cite-$marker)');
    }
  }
  return out.toString();
}
