enum MessageRole { user, assistant, system }

enum MessageStatus { sending, streaming, success, error }

enum SceneMode { single, group }

/// Write-time context mask produced by the topic gate.
///
/// Business Rule: `keep` is positional and must match the segment count;
/// mismatches are treated as "no mask" (fail-open) when replaying.
class TopicGateMask {
  const TopicGateMask({required this.topic, required this.keep});

  final String topic;
  final List<bool> keep;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'topic': topic,
        'keep': keep,
      };

  static TopicGateMask? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? topic = raw['topic'];
    final Object? keepRaw = raw['keep'];
    if (topic is! String || keepRaw is! List) {
      return null;
    }
    return TopicGateMask(
      topic: topic,
      keep: keepRaw.map((Object? v) => v == true).toList(growable: false),
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.status,
    this.reasoningContent,
    this.thinkingDuration,
    this.errorMessage,
    this.parentId = '',
    List<String>? childIds,
    this.activeChildId = '',
    this.speakerId = '',
    List<String>? mentionedIds,
    this.topicMask,
  })  : childIds = childIds ?? <String>[],
        mentionedIds = mentionedIds ?? <String>[];

  final String id;
  final MessageRole role;
  String content;
  String? reasoningContent;
  int? thinkingDuration;
  final int createdAt;
  MessageStatus status;
  String? errorMessage;
  String parentId;
  List<String> childIds;
  String activeChildId;
  String speakerId;
  List<String> mentionedIds;
  TopicGateMask? topicMask;

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  static String roleToWire(MessageRole role) {
    switch (role) {
      case MessageRole.user:
        return 'user';
      case MessageRole.assistant:
        return 'assistant';
      case MessageRole.system:
        return 'system';
    }
  }

  static MessageRole roleFromWire(Object? value) {
    if (value == 'assistant') {
      return MessageRole.assistant;
    }
    if (value == 'system') {
      return MessageRole.system;
    }
    return MessageRole.user;
  }

  static MessageStatus statusFromWire(Object? value) {
    if (value == 'sending') {
      return MessageStatus.sending;
    }
    if (value == 'streaming') {
      return MessageStatus.streaming;
    }
    if (value == 'error') {
      return MessageStatus.error;
    }
    return MessageStatus.success;
  }

  static String statusToWire(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return 'sending';
      case MessageStatus.streaming:
        return 'streaming';
      case MessageStatus.success:
        return 'success';
      case MessageStatus.error:
        return 'error';
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'role': roleToWire(role),
        'content': content,
        if (reasoningContent != null) 'reasoningContent': reasoningContent,
        if (thinkingDuration != null) 'thinkingDuration': thinkingDuration,
        'createdAt': createdAt,
        'status': statusToWire(status),
        if (errorMessage != null) 'errorMessage': errorMessage,
        'parentId': parentId,
        'childIds': childIds,
        'activeChildId': activeChildId,
        'speakerId': speakerId,
        'mentionedIds': mentionedIds,
        if (topicMask != null) 'topicMask': topicMask!.toJson(),
      };

  /// Boundary parser: persisted data is untrusted, so every field is
  /// type-checked and invalid records are dropped by the caller.
  static ChatMessage? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? id = raw['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final Object? childIdsRaw = raw['childIds'];
    final List<String> childIds = <String>[];
    if (childIdsRaw is List) {
      for (final Object? c in childIdsRaw) {
        if (c is String) {
          childIds.add(c);
        }
      }
    }
    final Object? mentionedRaw = raw['mentionedIds'];
    final List<String> mentioned = <String>[];
    if (mentionedRaw is List) {
      for (final Object? m in mentionedRaw) {
        if (m is String && m.isNotEmpty) {
          mentioned.add(m);
        }
      }
    }
    return ChatMessage(
      id: id,
      role: roleFromWire(raw['role']),
      content: raw['content'] is String ? raw['content'] as String : '',
      reasoningContent:
          raw['reasoningContent'] is String ? raw['reasoningContent'] as String : null,
      thinkingDuration:
          raw['thinkingDuration'] is num ? (raw['thinkingDuration'] as num).round() : null,
      createdAt: raw['createdAt'] is num
          ? (raw['createdAt'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
      status: statusFromWire(raw['status']),
      errorMessage: raw['errorMessage'] is String ? raw['errorMessage'] as String : null,
      parentId: raw['parentId'] is String ? raw['parentId'] as String : '',
      childIds: childIds,
      activeChildId: raw['activeChildId'] is String ? raw['activeChildId'] as String : '',
      speakerId: raw['speakerId'] is String ? raw['speakerId'] as String : '',
      mentionedIds: mentioned,
      topicMask: TopicGateMask.tryParse(raw['topicMask']),
    );
  }
}

class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.characterId,
    required this.providerId,
    required this.modelId,
    required this.updatedAt,
    List<ChatMessage>? messages,
    List<String>? rootIds,
    this.activeRootId = '',
    List<String>? participantIds,
    this.sceneMode = SceneMode.single,
    Map<String, String>? joinMap,
    this.userIdentityId = '',
    this.isPrivate = false,
  })  : messages = messages ?? <ChatMessage>[],
        rootIds = rootIds ?? <String>[],
        participantIds = participantIds ?? <String>[],
        joinMap = joinMap ?? <String, String>{};

  final String id;
  String title;
  String characterId;
  String providerId;
  String modelId;
  int updatedAt;
  final List<ChatMessage> messages;
  List<String> rootIds;
  String activeRootId;
  List<String> participantIds;
  SceneMode sceneMode;
  Map<String, String> joinMap;
  String userIdentityId;
  bool isPrivate;

  bool get isGroup => sceneMode == SceneMode.group && participantIds.length >= 2;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'characterId': characterId,
        'providerId': providerId,
        'modelId': modelId,
        'updatedAt': updatedAt,
        'messages': messages.map((ChatMessage m) => m.toJson()).toList(growable: false),
        'rootIds': rootIds,
        'activeRootId': activeRootId,
        'participantIds': participantIds,
        'sceneMode': sceneMode == SceneMode.group ? 'group' : 'single',
        'joinMap': joinMap,
        'userIdentityId': userIdentityId,
        'isPrivate': isPrivate,
      };
}

class CharacterCard {
  CharacterCard({
    required this.id,
    required this.name,
    this.avatarIcon = 'custom',
    this.description = '',
    this.systemPrompt = '',
    this.firstMessage = '',
    this.temperature = 0.7,
    this.knowledge = '',
    required this.createdAt,
  });

  final String id;
  String name;
  String avatarIcon;
  String description;
  String systemPrompt;
  String firstMessage;
  double temperature;
  String knowledge;
  final int createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'avatarIcon': avatarIcon,
        'description': description,
        'systemPrompt': systemPrompt,
        'firstMessage': firstMessage,
        'temperature': temperature,
        'knowledge': knowledge,
        'createdAt': createdAt,
      };

  static CharacterCard? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? id = raw['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    return CharacterCard(
      id: id,
      name: raw['name'] is String ? raw['name'] as String : '未命名',
      avatarIcon: raw['avatarIcon'] is String ? raw['avatarIcon'] as String : 'custom',
      description: raw['description'] is String ? raw['description'] as String : '',
      systemPrompt: raw['systemPrompt'] is String ? raw['systemPrompt'] as String : '',
      firstMessage: raw['firstMessage'] is String ? raw['firstMessage'] as String : '',
      temperature: raw['temperature'] is num ? (raw['temperature'] as num).toDouble() : 0.7,
      knowledge: raw['knowledge'] is String ? raw['knowledge'] as String : '',
      createdAt: raw['createdAt'] is num
          ? (raw['createdAt'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class UserIdentityCard {
  UserIdentityCard({
    required this.id,
    required this.name,
    this.persona = '',
    required this.createdAt,
  });

  final String id;
  String name;
  String persona;
  final int createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'persona': persona,
        'createdAt': createdAt,
      };

  static UserIdentityCard? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? id = raw['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    return UserIdentityCard(
      id: id,
      name: raw['name'] is String ? raw['name'] as String : '未命名',
      persona: raw['persona'] is String ? raw['persona'] as String : '',
      createdAt: raw['createdAt'] is num
          ? (raw['createdAt'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class ModelInfo {
  const ModelInfo({required this.id, required this.name});

  final String id;
  final String name;
}
