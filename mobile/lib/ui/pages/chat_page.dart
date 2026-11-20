import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/provider.dart';
import '../../state/chat_controller.dart';
import '../widgets/message_bubble.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/thinking_button.dart';
import '../widgets/web_search_button.dart';
import 'chat_sheets.dart';
import 'settings_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  ChatController? _chat;
  bool _inputExpanded = false;
  bool _showJumpBottom = false;
  int _lastPathLength = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ChatController chat = context.read<ChatController>();
    if (!identical(_chat, chat)) {
      _chat?.removeListener(_onChatChanged);
      _chat = chat;
      _chat!.addListener(_onChatChanged);
      _scroll.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _chat?.removeListener(_onChatChanged);
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final bool away = _scroll.offset <
        _scroll.position.maxScrollExtent - 80;
    if (away != _showJumpBottom) {
      setState(() => _showJumpBottom = away);
    }
  }

  void _onChatChanged() {
    final ChatController? chat = _chat;
    if (chat == null) {
      return;
    }
    final int length = chat.activePath.length;
    final bool grew = length > _lastPathLength;
    _lastPathLength = length;
    if (!_scroll.hasClients) {
      return;
    }
    final bool nearBottom =
        _scroll.offset >= _scroll.position.maxScrollExtent - 200;
    if (grew || (chat.isGenerating && nearBottom)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) {
      return;
    }
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty) {
      return;
    }
    final ChatController chat = context.read<ChatController>();
    _input.clear();
    setState(() => _inputExpanded = false);
    await chat.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final ChatController chat = context.watch<ChatController>();
    final List<ChatMessage> path = chat.activePath;
    _lastPathLength = path.length;
    final ChatSession? session = chat.currentSession;
    final String identityName = session == null
        ? ''
        : (chat.identityById(session.userIdentityId)?.name ?? '');

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.surface,
      drawer: _SessionDrawer(
        onNewSession: _startNewSession,
        onOpenSettings: () => _openSettings(context),
        onOpenCharacters: () => showCharacterSheet(context, manage: true),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _buildHeader(context, chat),
            if (chat.noticeText.isNotEmpty) _buildNotice(c, chat),
            Divider(color: c.borderSoft, height: 1),
            Expanded(
              child: Stack(
                children: <Widget>[
                  path.isEmpty
                      ? _buildEmptyState(c)
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                          itemCount: path.length,
                          itemBuilder: (BuildContext context, int index) {
                            final ChatMessage message = path[index];
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              child: MessageBubble(
                                key: ValueKey<String>(message.id),
                                message: message,
                                controller: chat,
                                identityName:
                                    message.isUser ? identityName : '',
                                speakerName: message.isAssistant
                                    ? (chat.characterById(message.speakerId)
                                            ?.name ??
                                        '')
                                    : '',
                                onLongPress: () =>
                                    showMessageActions(context, message),
                                onBranchChange: (int delta) => chat
                                    .switchBranch(message.id, delta),
                              ),
                            );
                          },
                        ),
                  if (_showJumpBottom)
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: _JumpBottomButton(
                        onTap: () {
                          _scrollToBottom();
                          setState(() => _showJumpBottom = false);
                        },
                      ),
                    ),
                ],
              ),
            ),
            _buildInputArea(context, chat),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ChatController chat) {
    final AppColors c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _bar(c.textPrimary),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: _bar(c.textPrimary),
                  ),
                  _bar(c.textPrimary),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: <Widget>[
                  Text(
                    chat.sessionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textTitle,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chat.providerName,
                    style: TextStyle(fontSize: 10, color: c.textMuted),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => showModelPicker(context),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.accentOutline),
              ),
              constraints: const BoxConstraints(maxWidth: 150),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      chat.currentModelId.isEmpty
                          ? '选择模型'
                          : chat.currentModelId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '选模型',
                    style: TextStyle(fontSize: 10, color: c.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(Color color) => Container(
        width: 16,
        height: 2,
        color: color,
      );

  Widget _buildNotice(AppColors c, ChatController chat) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: chat.clearNotice,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: c.dangerFill,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            chat.noticeText,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: c.dangerText),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppColors c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: 24, height: 1, color: c.accent),
              Text(
                '  BALANCE  /  AI',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                  color: c.accent,
                ),
              ),
              Container(width: 24, height: 1, color: c.accent),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '让想法慢慢展开',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w500,
              color: c.textTitle,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            '从一个问题开始，开启一段清晰的对话。',
            style: TextStyle(
              fontSize: 14,
              height: 1.64,
              color: c.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// 选择并上传附件：文件 / 相册 / 拍照，统一走 FileUploadService。
  Future<void> _pickAttachment(
    BuildContext context,
    ChatController chat,
  ) async {
    final String? kind = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('选择文件'),
              onTap: () => Navigator.of(ctx).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
          ],
        ),
      ),
    );
    if (kind == null) {
      return;
    }
    String? fileName;
    Uint8List? bytes;
    try {
      if (kind == 'file') {
        final PlatformFile? file = await FilePicker.pickFile();
        if (file == null) {
          return;
        }
        fileName = file.name;
        bytes = await file.readAsBytes();
      } else {
        final XFile? picked = await ImagePicker().pickImage(
          source: kind == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 90,
        );
        if (picked == null) {
          return;
        }
        fileName = picked.name;
        bytes = await picked.readAsBytes();
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择附件失败：$error')),
      );
      return;
    }
    await chat.uploadPendingAttachment(fileName: fileName, bytes: bytes);
  }
  Widget _buildInputArea(BuildContext context, ChatController chat) {
    final AppColors c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (chat.pendingAttachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final MessageAttachment att in chat.pendingAttachments)
                    InputChip(
                      label:
                          Text(att.fileName, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => chat.removePendingAttachment(att.fileId),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: _inputExpanded
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.center,
            children: <Widget>[
              if (chat.attachmentBusy)
                const Padding(
                  padding: EdgeInsets.only(right: 8, bottom: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 6),
                  child: IconButton(
                    tooltip: '添加文件或图片',
                    onPressed: () => _pickAttachment(context, chat),
                    icon: Icon(Icons.add_circle_outline_rounded, color: c.accent),
                  ),
                ),
              Expanded(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: <Widget>[
                    TextField(
                      controller: _input,
                      minLines: _inputExpanded ? 4 : 2,
                      maxLines: _inputExpanded ? 10 : 2,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: c.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入您的问题...',
                        contentPadding: const EdgeInsets.fromLTRB(
                          16,
                          12,
                          46,
                          12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(_inputExpanded ? 20 : 24),
                          borderSide: BorderSide(color: c.borderCard),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(_inputExpanded ? 20 : 24),
                          borderSide: BorderSide(color: c.borderCard),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(_inputExpanded ? 20 : 24),
                          borderSide: BorderSide(color: c.accentOutline),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10, bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(13),
                        onTap: () =>
                            setState(() => _inputExpanded = !_inputExpanded),
                        child: Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.iconTile,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: c.accentOutline),
                          ),
                          child: Icon(
                            _inputExpanded
                                ? Icons.close_fullscreen_rounded
                                : Icons.open_in_full_rounded,
                            size: 14,
                            color: c.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (chat.isGenerating)
                SizedBox(
                  width: 60,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.dangerText,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: chat.stopGenerating,
                    child: const Text(
                      '停止',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: _send,
                    child: const Icon(Icons.arrow_upward_rounded, size: 21),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              ThinkingButton(
                enabled: chat.enableThinking,
                providerId: chat.currentProviderId,
                modelId: chat.currentModelId,
                onToggle: chat.setEnableThinking,
              ),
              const SizedBox(width: 8),
              WebSearchButton(
                enabled: chat.enableWebSearch,
                providerId: chat.currentProviderId,
                onToggle: chat.setEnableWebSearch,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  /// Creates the draft, closes the drawer, then offers character binding on
  /// the page's own context (the drawer context is unmounted by then).
  void _startNewSession() {
    _scaffoldKey.currentState?.closeDrawer();
    context.read<ChatController>().createNewSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showBindSheet(context);
      }
    });
  }
}

class _JumpBottomButton extends StatelessWidget {
  const _JumpBottomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.accentOutline),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x1F231E14),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '↓',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.accent,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '回到底部',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: c.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionDrawer extends StatelessWidget {
  const _SessionDrawer({
    required this.onNewSession,
    required this.onOpenSettings,
    required this.onOpenCharacters,
  });

  final VoidCallback onNewSession;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenCharacters;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final ChatController chat = context.watch<ChatController>();
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.82,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: <Widget>[
                  Text(
                    '历史会话',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: c.textTitle,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: onNewSession,
                      child: const Text(
                        '+ 新会话',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: c.borderSoft, height: 1),
            Expanded(
              child: chat.sessions.isEmpty
                  ? Center(
                      child: Text(
                        '还没有历史会话',
                        style: TextStyle(fontSize: 13, color: c.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      itemCount: chat.sessions.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ChatSession session = chat.sessions[index];
                        final bool selected =
                            session.id == chat.currentSessionId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              Navigator.of(context).pop();
                              await chat.openSessionWithPrivacy(session);
                            },
                            onLongPress: () =>
                                showSessionActions(context, session),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                13,
                                14,
                                13,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? c.accentSoftSelected
                                    : c.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? c.accentOutline
                                      : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            if (session.isPrivate)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                  right: 4,
                                                ),
                                                child: Icon(
                                                  Icons.lock_outline_rounded,
                                                  size: 13,
                                                  color: c.accent,
                                                ),
                                              ),
                                            Expanded(
                                              child: Text(
                                                session.title,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: selected
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                                  color: selected
                                                      ? c.accent
                                                      : c.textPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_providerName(session.providerId)} · '
                                          '${session.messages.length} 条消息',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: c.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: c.iconMuted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Divider(color: c.borderSoft, height: 1),
            _DrawerRow(
              icon: Icons.people_outline_rounded,
              label: '角色管理',
              onTap: () {
                Navigator.of(context).pop();
                onOpenCharacters();
              },
            ),
            _DrawerRow(
              icon: Icons.settings_outlined,
              label: '设置',
              onTap: () {
                Navigator.of(context).pop();
                onOpenSettings();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _providerName(String id) {
    for (final ProviderDefinition p in providers) {
      if (p.id == id) {
        return p.name;
      }
    }
    return id;
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.iconTile,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icon, size: 18, color: c.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: c.iconMuted,
            ),
          ],
        ),
      ),
    );
  }
}
