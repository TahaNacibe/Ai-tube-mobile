import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'app_constants.dart';
import 'models.dart';
import 'profile_avatar.dart';
import 'theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.preferences,
    required this.onOpenSettings,
    super.key,
  });

  final Map<String, dynamic> preferences;
  final VoidCallback onOpenSettings;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late ApiClient _api;
  List<ChatSession> _chats = [];
  String? _activeId;
  String _model = '';
  String _connectionError = '';
  String _error = '';
  String _streamText = '';
  List<Map<String, dynamic>> _streamSources = [];
  List<Map<String, dynamic>> _streamImages = [];
  http.Client? _streamClient;
  bool _busy = false;
  bool _stopping = false;

  ChatSession? get _active {
    for (final chat in _chats) {
      if (chat.id == _activeId) return chat;
    }
    return null;
  }

  String get _assistantName =>
      (widget.preferences['assistantName'] as String?)?.trim().isNotEmpty ==
          true
      ? (widget.preferences['assistantName'] as String).trim()
      : 'Assistant';

  String get _profileName =>
      (widget.preferences['profileName'] as String? ?? '').trim();

  String get _profileAvatar =>
      (widget.preferences['profileAvatar'] as String? ?? '').trim();

  String get _profileDisplayName =>
      _profileName.isNotEmpty ? _profileName : _assistantName;

  Widget _profileAvatarWidget({double radius = 15}) {
    final image = profileImageProvider(_profileAvatar);
    return CircleAvatar(
      radius: radius,
      backgroundImage: image,
      child: image == null
          ? Text(
              _profileName.isEmpty
                  ? 'A'
                  : _profileName.substring(0, 1).toUpperCase(),
              style: TextStyle(fontSize: radius * 0.75),
            )
          : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _api = ApiClient(widget.preferences['apiBaseUrl'] as String? ?? '');
    _loadChats();
    _refreshStatus();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl = oldWidget.preferences['apiBaseUrl'];
    final nextUrl = widget.preferences['apiBaseUrl'];
    if (oldUrl != nextUrl) {
      _api = ApiClient(nextUrl as String? ?? '');
      _refreshStatus();
    }
  }

  @override
  void dispose() {
    _streamClient?.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    final store = await SharedPreferences.getInstance();
    try {
      final saved = jsonDecode(store.getString(chatsKey) ?? '[]');
      if (saved is List) {
        _chats = saved
            .whereType<Map<String, dynamic>>()
            .map(ChatSession.fromJson)
            .where((chat) => chat.id.isNotEmpty)
            .toList();
        _chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (_chats.isNotEmpty) _activeId = _chats.first.id;
      }
    } on FormatException {
      await store.remove(chatsKey);
    }
    if (mounted) setState(() {});
  }

  Future<void> _persistChats() async {
    final store = await SharedPreferences.getInstance();
    await store.setString(
      chatsKey,
      jsonEncode(_chats.map((chat) => chat.toJson()).toList()),
    );
  }

  Future<void> _refreshStatus() async {
    try {
      final result = await _api.getJson('/api/models');
      if (!mounted) return;
      final running = result['running'] as List<dynamic>? ?? [];
      setState(() {
        final selected = result['selected'] as String? ?? '';
        _model = running.contains(selected)
            ? selected
            : running.isNotEmpty
            ? running.first as String
            : selected;
        _connectionError = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectionError = error.toString().replaceFirst('Exception: ', '');
        _model = '';
      });
    }
  }

  void _newChat() {
    setState(() {
      _activeId = null;
      _error = '';
    });
    Navigator.pop(context);
  }

  void _selectChat(ChatSession chat) {
    setState(() {
      _activeId = chat.id;
      _error = '';
    });
    Navigator.pop(context);
    _scrollToBottom();
  }

  Future<void> _deleteChat(ChatSession chat) async {
    setState(() {
      _chats.removeWhere((item) => item.id == chat.id);
      if (_activeId == chat.id) {
        _activeId = _chats.isEmpty ? null : _chats.first.id;
      }
    });
    await _persistChats();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    _error = '';
    final chat =
        _active ??
        ChatSession(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: text.length > 52 ? text.substring(0, 52) : text,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          messages: [],
        );
    if (!_chats.any((item) => item.id == chat.id)) _chats.insert(0, chat);
    _activeId = chat.id;
    chat.messages.add(ChatMessage(role: 'user', content: text));
    chat.updatedAt = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _busy = true;
      _streamText = '';
      _streamSources = [];
      _streamImages = [];
    });
    await _persistChats();
    _scrollToBottom();

    final client = http.Client();
    _streamClient = client;
    var responseText = '';
    var sources = <Map<String, dynamic>>[];
    var images = <Map<String, dynamic>>[];
    try {
      final events = _api.streamChat(
        messages: chat.messages
            .map(
              (message) => {'role': message.role, 'content': message.content},
            )
            .toList(),
        webSearch: widget.preferences['webSearchEnabled'] == true,
        imageSearch: widget.preferences['imageSearchEnabled'] == true,
        memoryContext: [
          if (_profileName.isNotEmpty) 'AI display name: $_profileName.',
          if ((widget.preferences['profilePersona'] as String? ?? '')
              .trim()
              .isNotEmpty)
            'Assistant persona: ${(widget.preferences['profilePersona'] as String).trim()}',
          if ((widget.preferences['profileContext'] as String? ?? '')
              .trim()
              .isNotEmpty)
            'Initial context for the assistant: ${(widget.preferences['profileContext'] as String).trim()}',
        ],
        knowledgePoolData: const [],
        client: client,
      );
      await for (final event in events) {
        if (event['error'] is String) throw Exception(event['error']);
        if (event['sources'] is List) {
          sources = (event['sources'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
          _streamSources = sources;
        }
        if (event['images'] is List) {
          images = (event['images'] as List)
              .whereType<Map<String, dynamic>>()
              .toList();
          _streamImages = images;
        }
        if (event['token'] is String) {
          responseText += event['token'] as String;
          if (mounted) setState(() => _streamText = responseText);
          _scrollToBottom();
        }
        if (event['done'] == true) break;
      }
      if (_stopping) {
        responseText = responseText.isEmpty
            ? 'Response stopped.'
            : '$responseText\n\n(Response stopped)';
      }
      if (responseText.isNotEmpty) {
        chat.messages.add(
          ChatMessage(
            role: 'assistant',
            content: responseText,
            sources: sources,
            images: images,
          ),
        );
      }
    } catch (error) {
      if (!_stopping && mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
      if (_stopping && responseText.isNotEmpty) {
        chat.messages.add(
          ChatMessage(
            role: 'assistant',
            content: '$responseText\n\n(Response stopped)',
            sources: sources,
            images: images,
          ),
        );
      }
    } finally {
      client.close();
      _streamClient = null;
      _stopping = false;
      chat.updatedAt = DateTime.now().millisecondsSinceEpoch;
      if (mounted) {
        setState(() {
          _busy = false;
          _streamText = '';
          _streamSources = [];
          _streamImages = [];
        });
      }
      await _persistChats();
      _scrollToBottom();
    }
  }

  void _stop() {
    if (!_busy) return;
    _stopping = true;
    _streamClient?.close();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = _active?.messages ?? const <ChatMessage>[];
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Chat history',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            _profileAvatarWidget(),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_profileDisplayName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Tooltip(
                message: _connectionError.isEmpty
                    ? 'Server connected'
                    : _connectionError,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _connectionError.isEmpty
                        ? const Color(0xff4a9a68)
                        : const Color(0xffc85843),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          if (_connectionError.isNotEmpty)
            _ConnectionBanner(
              message: _connectionError,
              onSettings: widget.onOpenSettings,
            ),
          Expanded(
            child: messages.isEmpty && _streamText.isEmpty
                ? _welcome()
                : _buildMessages(messages),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: _ErrorBanner(message: _error),
            ),
          _composer(),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final sorted = [..._chats]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  _profileAvatarWidget(radius: 17),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$_profileDisplayName / local',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FilledButton.icon(
                onPressed: _newChat,
                icon: const Icon(Icons.add),
                label: const Text('New chat'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 24, 16, 8),
              child: Text(
                'RECENT',
                style: TextStyle(
                  color: appMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Expanded(
              child: sorted.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 22),
                      child: Text(
                        'Conversations on this device will appear here.',
                        style: TextStyle(color: appMuted, height: 1.5),
                      ),
                    )
                  : ListView.builder(
                      itemCount: sorted.length,
                      itemBuilder: (context, index) {
                        final chat = sorted[index];
                        return ListTile(
                          selected: chat.id == _activeId,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.08),
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectChat(chat),
                          trailing: IconButton(
                            tooltip: 'Delete chat',
                            icon: const Icon(Icons.delete_outline, size: 19),
                            onPressed: () => _deleteChat(chat),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                _connectionError.isEmpty ? Icons.circle : Icons.error_outline,
                size: 14,
                color: _connectionError.isEmpty
                    ? const Color(0xff4a9a68)
                    : const Color(0xffc85843),
              ),
              title: Text(
                _connectionError.isEmpty
                    ? 'Server connected'
                    : 'Server unavailable',
              ),
              subtitle: Text(
                _model.isEmpty ? 'Tap to configure connection' : _model,
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onOpenSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _welcome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 52, 22, 24),
      children: [
        const _Eyebrow(label: 'YOUR LOCAL AI'),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 39,
              height: 1.07,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.8,
            ),
            children: [
              const TextSpan(text: 'A good place\nto '),
              TextSpan(
                text: 'think out loud.',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          'Ask a question, untangle an idea, or make something new. Your conversation stays on this device.',
          style: TextStyle(color: appMuted, height: 1.65),
        ),
        const SizedBox(height: 8),
        const Text(
          'Public web and image search can be enabled in settings.',
          style: TextStyle(color: appMuted, height: 1.5, fontSize: 12),
        ),
        const SizedBox(height: 26),
        for (final prompt in [
          'Explain a tricky idea in a simple way',
          'Help me brainstorm a fresh project idea',
          'Help me write a clear, friendly email',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _input.text = prompt;
                  _send();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          prompt,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Icon(
                        Icons.arrow_outward,
                        size: 17,
                        color: appAccent(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessages(List<ChatMessage> messages) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
      itemCount: messages.length + (_streamText.isNotEmpty || _busy ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return _MessageBubble(
            assistantName: _assistantName,
            profileName: _profileName,
            profileAvatar: _profileAvatar,
            message: ChatMessage(
              role: 'assistant',
              content: _streamText.isEmpty ? 'Thinking…' : _streamText,
              sources: _streamSources,
              images: _streamImages,
            ),
            streaming: _streamText.isEmpty,
          );
        }
        return _MessageBubble(
          assistantName: _assistantName,
          profileName: _profileName,
          profileAvatar: _profileAvatar,
          message: messages[index],
        );
      },
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(13, 7, 7, 7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: Color(0x0d1d291b), blurRadius: 16),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 12000,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message Assistant…',
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 7),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: _busy ? 'Stop response' : 'Send message',
                    onPressed: _busy ? _stop : _send,
                    style: IconButton.styleFrom(
                      backgroundColor: _busy
                          ? const Color(0xffa84e3b)
                          : Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    icon: Icon(
                      _busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Your chats are saved on this device',
              style: TextStyle(color: appMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.assistantName,
    required this.profileName,
    required this.profileAvatar,
    required this.message,
    this.streaming = false,
  });

  final String assistantName;
  final String profileName;
  final String profileAvatar;
  final ChatMessage message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!user) ...[
            CircleAvatar(
              radius: 14,
              backgroundImage: profileImageProvider(profileAvatar),
              child: profileImageProvider(profileAvatar) == null
                  ? Text(
                      profileName.trim().isEmpty
                          ? assistantName.trim().substring(0, 1).toUpperCase()
                          : profileName.trim().substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontSize: 10),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth:
                    MediaQuery.sizeOf(context).width * (user ? 0.84 : 0.86),
              ),
              padding: user ? const EdgeInsets.all(13) : EdgeInsets.zero,
              decoration: user
                  ? BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(13),
                        topRight: Radius.circular(13),
                        bottomLeft: Radius.circular(13),
                        bottomRight: Radius.circular(4),
                      ),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!user)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        streaming
                            ? '${profileName.trim().isEmpty ? assistantName : profileName} · TYPING'
                            : (profileName.trim().isEmpty
                                      ? assistantName
                                      : profileName)
                                  .toUpperCase(),
                        style: const TextStyle(
                          color: appMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                  if (user)
                    Text(message.content, style: const TextStyle(height: 1.55))
                  else if (message.content == 'Thinking…')
                    const Text(
                      'Thinking…',
                      style: TextStyle(
                        color: appMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
                        code: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.dividerColor),
                        ),
                      ),
                      onTapLink: (text, href, title) {
                        if (href != null) launchUrl(Uri.parse(href));
                      },
                    ),
                  if (message.images.isNotEmpty)
                    _ImageStrip(images: message.images),
                  if (message.sources.isNotEmpty)
                    _SourceList(sources: message.sources),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.images});
  final List<Map<String, dynamic>> images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 145,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = images[index];
          final src =
              image['thumbnail'] as String? ?? image['image'] as String? ?? '';
          return SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      src,
                      width: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 150,
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  image['title'] as String? ?? 'Image',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SourceList extends StatelessWidget {
  const _SourceList({required this.sources});
  final List<Map<String, dynamic>> sources;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 18),
          const Text(
            'Sources',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          for (final source in sources)
            InkWell(
              onTap: () {
                final value = source['url'] as String?;
                if (value != null) launchUrl(Uri.parse(value));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  source['title'] as String? ??
                      source['url'] as String? ??
                      'Source',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 20, height: 1, color: appAccent(context)),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: appAccent(context),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.message, required this.onSettings});
  final String message;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xfffff1ed),
      child: InkWell(
        onTap: onSettings,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 16,
                color: Color(0xff813c2f),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff813c2f),
                    fontSize: 11,
                  ),
                ),
              ),
              const Text(
                'SETUP',
                style: TextStyle(
                  color: Color(0xff813c2f),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xfffff1ed),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      message,
      style: const TextStyle(color: Color(0xff813c2f), fontSize: 12),
    ),
  );
}
