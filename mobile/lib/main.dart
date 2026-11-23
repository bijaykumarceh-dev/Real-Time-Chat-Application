import 'dart:async';

import 'package:flutter/material.dart';

import 'chat_client.dart';

const _ink = Color(0xFF202C28);
const _muted = Color(0xFF7C8984);
const _green = Color(0xFF187C62);
const _canvas = Color(0xFFF5F7F5);

void main() {
  runApp(const GatherApp());
}

class GatherApp extends StatefulWidget {
  const GatherApp({super.key});

  @override
  State<GatherApp> createState() => _GatherAppState();
}

class _GatherAppState extends State<GatherApp> {
  final ChatClient _client = ChatClient();
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await _client.restoreSession();
    if (mounted) setState(() => _restoring = false);
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _client,
    builder: (context, _) => MaterialApp(
      title: 'Gather',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _green,
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: _canvas,
          foregroundColor: _ink,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: _muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE7ECE9)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE7ECE9)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _green, width: 1.5),
          ),
        ),
      ),
      home: _restoring
          ? const _RestoreScreen()
          : _client.user == null
          ? _LoginScreen(client: _client)
          : _ChatScreen(client: _client),
    ),
  );
}

class _RestoreScreen extends StatelessWidget {
  const _RestoreScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: _green)),
  );
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.client});

  final ChatClient client;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    await widget.client.authenticate(
      username: _usernameController.text,
      password: _passwordController.text,
      register: _register,
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: widget.client.serverUrl);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Chat server'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use your deployed server URL. Keep the final address private '
                'if it contains credentials.',
                style: TextStyle(color: _muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://your-chat-server.example.com',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.client.setServerUrl(controller.text);
                  if (context.mounted) Navigator.pop(context);
                } on FormatException catch (exception) {
                  setDialogState(() => error = exception.message);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: _editServer,
                      tooltip: 'Configure server',
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _BrandMark(size: 58),
                  const SizedBox(height: 20),
                  const Text(
                    'gather',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _register
                        ? 'Create an account and join the conversation.'
                        : 'A little closer, wherever you are.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted, fontSize: 15),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE8ECE9)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0B18231F),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _register ? 'Create account' : 'Welcome back',
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _usernameController,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) {
                              final username = value?.trim() ?? '';
                              if (username.isEmpty || username.length > 32) {
                                return 'Enter a username (1-32 characters).';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              final length = value?.length ?? 0;
                              if (_register && (length < 8 || length > 72)) {
                                return 'Use a password of 8-72 characters.';
                              }
                              if (!_register && length == 0) {
                                return 'Enter your password.';
                              }
                              return null;
                            },
                          ),
                          if (client.error case final error?) ...[
                            const SizedBox(height: 14),
                            _InlineNotice(text: error),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: _green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 21,
                                      height: 21,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _register ? 'Create account' : 'Sign in',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _register = !_register;
                            widget.client.clearError();
                          }),
                    child: Text(
                      _register
                          ? 'Already have an account? Sign in'
                          : 'New to Gather? Create an account',
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Server: ${client.serverUrl}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatScreen extends StatefulWidget {
  const _ChatScreen({required this.client});

  final ChatClient client;

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final _messageController = TextEditingController();
  final _messageFocus = FocusNode();
  final _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _typingActive = false;

  ChatClient get client => widget.client;

  @override
  void initState() {
    super.initState();
    client.addListener(_scrollToLatest);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    client.removeListener(_scrollToLatest);
    _messageController.dispose();
    _messageFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    if (!mounted || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onDraftChanged(String value) {
    if (value.trim().isEmpty) {
      _stopTyping();
      setState(() {});
      return;
    }
    client.typingStarted();
    if (!_typingActive) {
      _typingActive = true;
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _stopTyping);
    setState(() {});
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    _typingTimer = null;
    if (_typingActive) client.typingStopped();
    _typingActive = false;
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || !client.isJoined || !client.isConnected) return;
    _stopTyping();
    client.sendMessage(text);
    _messageController.clear();
    setState(() {});
    _messageFocus.requestFocus();
  }

  Future<void> _logout() async {
    _stopTyping();
    await client.logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = client.user!;
    final canSend =
        client.isConnected &&
        client.isJoined &&
        _messageController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            const _BrandMark(size: 35),
            const SizedBox(width: 11),
            const Text(
              'gather',
              style: TextStyle(
                color: _ink,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account menu',
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 10),
                    Text('Sign out'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 17),
              child: _Avatar(name: user.username, size: 38),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _RoomHeader(client: client),
            if (client.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _InlineNotice(text: client.error!),
              ),
            Expanded(
              child: client.isLoadingHistory && client.messages.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: _green),
                    )
                  : client.messages.isEmpty
                  ? const _EmptyConversation()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                      itemCount:
                          client.messages.length +
                          (client.typingUsers.isEmpty ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index == client.messages.length) {
                          return _TypingNote(users: client.typingUsers);
                        }
                        final message = client.messages[index];
                        return _MessageBubble(
                          message: message,
                          own: message.sender == user.username,
                        );
                      },
                    ),
            ),
            if (!client.isJoined && !client.isLoadingHistory)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Waiting to join the chat…',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            _Composer(
              controller: _messageController,
              focusNode: _messageFocus,
              enabled: client.isConnected && client.isJoined,
              canSend: canSend,
              onChanged: _onDraftChanged,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.client});

  final ChatClient client;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 13, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFFE8ECE9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4EE),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Center(
                    child: Text(
                      '#',
                      style: TextStyle(
                        color: _green,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'general',
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'A shared space for everyone',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                _ConnectionBadge(connected: client.isConnected),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: _green),
                const SizedBox(width: 6),
                Text(
                  '${client.onlineUsers.length} online',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: SizedBox(
                    height: 26,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: client.onlineUsers.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 5),
                      itemBuilder: (context, index) => Tooltip(
                        message: client.onlineUsers[index],
                        child: _Avatar(
                          name: client.onlineUsers[index],
                          size: 25,
                          compact: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: connected ? const Color(0xFFE8F4EE) : const Color(0xFFFFF2DF),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(
          connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          size: 13,
          color: connected ? _green : const Color(0xFFAF7420),
        ),
        const SizedBox(width: 5),
        Text(
          connected ? 'Live' : 'Connecting',
          style: TextStyle(
            color: connected ? _green : const Color(0xFFAF7420),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFE7F2EC),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.forum_outlined, color: _green, size: 29),
          ),
          const SizedBox(height: 15),
          const Text(
            'Your conversation starts here',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Send a message to say hello to everyone in general.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.own});

  final ChatMessage message;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(message.timestamp.toLocal())
        .format(context);
    final readNames = message.readBy.map((receipt) => receipt.username).toSet();
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.79,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Column(
            crossAxisAlignment: own
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!own)
                Padding(
                  padding: const EdgeInsets.only(left: 5, bottom: 4),
                  child: Text(
                    message.sender,
                    style: const TextStyle(
                      color: _green,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: own ? _green : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(17),
                    topRight: const Radius.circular(17),
                    bottomLeft: Radius.circular(own ? 17 : 5),
                    bottomRight: Radius.circular(own ? 5 : 17),
                  ),
                  border: own
                      ? null
                      : Border.all(color: const Color(0xFFE8ECE9)),
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: own ? Colors.white : _ink,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                    if (own && readNames.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.done_all_rounded,
                        size: 14,
                        color: _green,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Seen by ${readNames.join(', ')}',
                        style: const TextStyle(color: _green, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingNote extends StatelessWidget {
  const _TypingNote({required this.users});

  final List<String> users;

  @override
  Widget build(BuildContext context) {
    final text = users.length == 1
        ? '${users.first} is typing…'
        : '${users.take(2).join(' and ')} are typing…';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 5),
      child: Row(
        children: [
          const Icon(Icons.more_horiz_rounded, color: _green, size: 21),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.canSend,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool canSend;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      14,
      10,
      14,
      MediaQuery.paddingOf(context).bottom + 10,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFE8ECE9))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onChanged: onChanged,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: enabled ? 'Write a message…' : 'Connecting to chat…',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: _green, width: 1),
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 47,
          height: 47,
          child: FilledButton(
            onPressed: canSend ? onSend : null,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: _green,
              disabledBackgroundColor: const Color(0xFFDCE4DF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
            child: const Icon(Icons.arrow_upward_rounded, size: 22),
          ),
        ),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size, this.compact = false});

  final String name;
  final double size;
  final bool compact;

  static const _colors = [
    Color(0xFFD9E8FF),
    Color(0xFFFCE1D7),
    Color(0xFFE7DEFB),
    Color(0xFFD9EEE4),
    Color(0xFFFAE9BD),
  ];

  @override
  Widget build(BuildContext context) {
    final color = name.isEmpty
        ? _colors.first
        : _colors[name.codeUnitAt(0) % _colors.length];
    final initials = name.trim().isEmpty
        ? '?'
        : name
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map(
                (part) =>
                    part.isEmpty ? '' : part.substring(0, 1).toUpperCase(),
              )
              .join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: compact ? 1 : 2),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: _ink,
          fontSize: size * (compact ? 0.38 : 0.32),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.2),
        child: const _MarkDots(),
      ),
    ),
  );
}

class _MarkDots extends StatelessWidget {
  const _MarkDots();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Expanded(
        child: Row(
          children: [
            Expanded(child: _MarkDot()),
            SizedBox(width: 3),
            Expanded(child: _MarkDot()),
          ],
        ),
      ),
      SizedBox(height: 3),
      Expanded(
        child: Row(
          children: [
            Expanded(child: _MarkDot()),
            SizedBox(width: 3),
            Expanded(child: _MarkDot()),
          ],
        ),
      ),
    ],
  );
}

class _MarkDot extends StatelessWidget {
  const _MarkDot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0EC),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: Color(0xFFAD4938),
          size: 17,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF8F3C2E),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}
