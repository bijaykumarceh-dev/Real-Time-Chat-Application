import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

const defaultServerUrl = 'https://real-time-chat-application-r34x.onrender.com';

class ChatUser {
  const ChatUser({required this.id, required this.username});

  final String id;
  final String username;

  factory ChatUser.fromJson(Map<String, dynamic> json) => ChatUser(
    id: json['id']?.toString() ?? '',
    username: json['username']?.toString() ?? 'Guest',
  );
}

class ReadReceipt {
  const ReadReceipt({
    required this.userId,
    required this.username,
    required this.readAt,
  });

  final String userId;
  final String username;
  final DateTime readAt;

  factory ReadReceipt.fromJson(Map<String, dynamic> json) => ReadReceipt(
    userId: json['userId']?.toString() ?? json['id']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    readAt:
        DateTime.tryParse(json['readAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    required this.readBy,
  });

  final String id;
  final String sender;
  final String text;
  final DateTime timestamp;
  final List<ReadReceipt> readBy;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id']?.toString() ?? '',
    sender: json['sender']?.toString() ?? '',
    text: json['text']?.toString() ?? '',
    timestamp:
        DateTime.tryParse(
          (json['timestamp'] ?? json['createdAt'])?.toString() ?? '',
        ) ??
        DateTime.now(),
    readBy: (json['readBy'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReadReceipt.fromJson)
        .toList(),
  );

  ChatMessage withReceipt(ReadReceipt receipt) {
    if (readBy.any((existing) => existing.userId == receipt.userId)) {
      return this;
    }
    return ChatMessage(
      id: id,
      sender: sender,
      text: text,
      timestamp: timestamp,
      readBy: [...readBy, receipt],
    );
  }
}

class ChatClient extends ChangeNotifier {
  ChatClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final List<ChatMessage> _messages = [];
  final List<String> _onlineUsers = [];
  final List<String> _typingUsers = [];

  String _serverUrl = defaultServerUrl;
  String _token = '';
  ChatUser? _user;
  io.Socket? _socket;
  bool _isConnected = false;
  bool _isJoined = false;
  bool _isLoadingHistory = false;
  String? _error;

  String get serverUrl => _serverUrl;
  ChatUser? get user => _user;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<String> get onlineUsers => List.unmodifiable(_onlineUsers);
  List<String> get typingUsers => List.unmodifiable(_typingUsers);
  bool get isConnected => _isConnected;
  bool get isJoined => _isJoined;
  bool get isLoadingHistory => _isLoadingHistory;
  String? get error => _error;

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> restoreSession() async {
    if (_token.isEmpty) {
      notifyListeners();
      return;
    }

    try {
      final response = await _http.get(
        _uri('/api/auth/me'),
        headers: _authHeaders(),
      );
      if (response.statusCode == 401) {
        await _clearSession();
        return;
      }
      final payload = _decodeResponse(response);
      _setSession(payload);
      _connectSocket();
    } catch (error) {
      _error = 'Could not reach the chat server: $error';
    }
    notifyListeners();
  }

  Future<void> authenticate({
    required String username,
    required String password,
    required bool register,
  }) async {
    _error = null;
    notifyListeners();
    try {
      final response = await _http.post(
        _uri('/api/auth/${register ? 'register' : 'login'}'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username.trim(), 'password': password}),
      );
      final payload = _decodeResponse(response);
      _setSession(payload);
      _connectSocket();
    } catch (error) {
      _error = _messageFromError(error);
    }
    notifyListeners();
  }

  Future<void> setServerUrl(String value) async {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        !{'http', 'https'}.contains(parsed.scheme)) {
      throw const FormatException('Enter a valid http or https server URL.');
    }
    if (parsed.scheme == 'http' && !kDebugMode) {
      throw const FormatException(
        'Use HTTPS for a server outside local development.',
      );
    }
    _serverUrl = trimmed;
    notifyListeners();
  }

  void _setSession(Map<String, dynamic> payload) {
    final userData = payload['user'];
    if (userData is! Map<String, dynamic> ||
        payload['token'] is! String ||
        (payload['token'] as String).isEmpty) {
      throw const FormatException('The server returned an invalid session.');
    }
    _user = ChatUser.fromJson(userData);
    _token = payload['token'] as String;
    _error = null;
  }

  void _connectSocket() {
    _socket?.dispose();
    _isConnected = false;
    _isJoined = false;
    _isLoadingHistory = true;
    _onlineUsers.clear();
    _typingUsers.clear();
    _messages.clear();

    final socket = io.io(
      _serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': _token})
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      _isConnected = true;
      _isLoadingHistory = true;
      _error = null;
      socket.emit('join', 'general');
      notifyListeners();
    });
    socket.onDisconnect((_) {
      _isConnected = false;
      _isJoined = false;
      _isLoadingHistory = false;
      _typingUsers.clear();
      notifyListeners();
    });
    socket.onConnectError((dynamic error) {
      _isConnected = false;
      _isLoadingHistory = false;
      _error = 'Could not connect to chat. Check the server URL and session.';
      notifyListeners();
    });
    socket.on('users:update', (dynamic payload) {
      if (payload is List) {
        _onlineUsers
          ..clear()
          ..addAll(payload.whereType<String>());
        notifyListeners();
      }
    });
    socket.on('message:history', (dynamic payload) {
      if (payload is List) {
        _mergeMessages(
          payload.whereType<Map<String, dynamic>>().map(ChatMessage.fromJson),
        );
        _isJoined = true;
        final unreadIds = _messages
            .where(
              (message) =>
                  message.sender != _user?.username &&
                  message.id.isNotEmpty &&
                  !message.readBy.any((receipt) => receipt.userId == _user?.id),
            )
            .map((message) => message.id)
            .toList();
        if (unreadIds.isNotEmpty) {
          socket.emit('messages:read', {
            'messageIds': unreadIds.take(50).toList(),
          });
        }
      }
      _isLoadingHistory = false;
      notifyListeners();
    });
    socket.on('message:new', (dynamic payload) {
      if (payload is! Map<String, dynamic>) return;
      final message = ChatMessage.fromJson(payload);
      if (message.id.isEmpty) return;
      _mergeMessages([message]);
      if (message.sender != _user?.username) {
        socket.emit('messages:read', {
          'messageIds': [message.id],
        });
      }
      notifyListeners();
    });
    socket.on('typing:update', (dynamic payload) {
      if (payload is! Map<String, dynamic>) return;
      final username = payload['username'];
      final isTyping = payload['isTyping'];
      if (username is! String ||
          isTyping is! bool ||
          username == _user?.username) {
        return;
      }
      if (isTyping && !_typingUsers.contains(username)) {
        _typingUsers.add(username);
      } else if (!isTyping) {
        _typingUsers.remove(username);
      }
      notifyListeners();
    });
    socket.on('messages:read', (dynamic payload) {
      if (payload is! Map<String, dynamic> ||
          payload['messageIds'] is! List ||
          payload['reader'] is! Map<String, dynamic>) {
        return;
      }
      final reader = ReadReceipt.fromJson(
        payload['reader'] as Map<String, dynamic>,
      );
      final ids = (payload['messageIds'] as List)
          .map((id) => id.toString())
          .toSet();
      for (var index = 0; index < _messages.length; index++) {
        if (ids.contains(_messages[index].id)) {
          _messages[index] = _messages[index].withReceipt(reader);
        }
      }
      notifyListeners();
    });
    socket.on('chat:error', (dynamic payload) {
      _error = payload is Map && payload['message'] is String
          ? payload['message'] as String
          : 'Something went wrong. Please try again.';
      _isLoadingHistory = false;
      notifyListeners();
    });
    socket.connect();
  }

  void _mergeMessages(Iterable<ChatMessage> incoming) {
    final byId = {for (final message in _messages) message.id: message};
    for (final message in incoming) {
      if (message.id.isEmpty) continue;
      final existing = byId[message.id];
      if (existing == null) {
        byId[message.id] = message;
      } else {
        var merged = existing;
        for (final receipt in message.readBy) {
          merged = merged.withReceipt(receipt);
        }
        byId[message.id] = merged;
      }
    }
    _messages
      ..clear()
      ..addAll(byId.values)
      ..sort((first, second) => first.timestamp.compareTo(second.timestamp));
  }

  void sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !_isJoined || !_isConnected) return;
    _socket?.emit('typing:stop');
    _socket?.emit('message:send', {'text': trimmed});
  }

  void typingStarted() {
    if (_isJoined && _isConnected) {
      _socket?.emit('typing:start');
    }
  }

  void typingStopped() {
    if (_isJoined && _isConnected) {
      _socket?.emit('typing:stop');
    }
  }

  Future<void> logout() async {
    String? logoutError;
    try {
      final response = await _http.post(
        _uri('/api/auth/logout'),
        headers: _authHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        logoutError = 'Server sign-out failed; local session was cleared.';
      }
    } catch (_) {
      logoutError = 'Could not reach the server; local session was cleared.';
    }
    await _clearSession(error: logoutError);
  }

  Map<String, String> _authHeaders() => {
        'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path) => Uri.parse('$_serverUrl$path');

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The server returned an invalid response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatApiException(
        decoded['error']?.toString() ??
            'Request failed (${response.statusCode}).',
      );
    }
    return decoded;
  }

  String _messageFromError(Object error) {
    if (error is ChatApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Could not reach the chat server. Check your connection.';
  }

  Future<void> _clearSession({String? error}) async {
    _socket?.dispose();
    _socket = null;
    _token = '';
    _user = null;
    _isConnected = false;
    _isJoined = false;
    _isLoadingHistory = false;
    _messages.clear();
    _onlineUsers.clear();
    _typingUsers.clear();
    _error = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _socket?.dispose();
    _http.close();
    super.dispose();
  }
}

class ChatApiException implements Exception {
  const ChatApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
