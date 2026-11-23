import 'package:flutter_test/flutter_test.dart';
import 'package:gather_chat/chat_client.dart';

void main() {
  test('parses serialized messages and read receipts', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'sender': 'Avery',
      'text': 'Hello',
      'timestamp': '2026-11-23T12:00:00.000Z',
      'readBy': [
        {
          'userId': 'user-2',
          'username': 'Jordan',
          'readAt': '2026-11-23T12:01:00.000Z',
        },
      ],
    });

    expect(message.id, 'message-1');
    expect(message.sender, 'Avery');
    expect(message.text, 'Hello');
    expect(message.timestamp, DateTime.utc(2026, 11, 23, 12));
    expect(message.readBy.single.username, 'Jordan');
  });

  test('adds each reader only once', () {
    final message = ChatMessage.fromJson({
      'id': 'message-2',
      'sender': 'Avery',
      'text': 'Hello',
      'timestamp': '2026-11-23T12:00:00.000Z',
      'readBy': const [],
    });
    final receipt = ReadReceipt(
      userId: 'user-2',
      username: 'Jordan',
      readAt: DateTime.utc(2026, 11, 23, 12, 1),
    );

    final updated = message.withReceipt(receipt).withReceipt(receipt);

    expect(updated.readBy, hasLength(1));
    expect(updated.readBy.single.userId, 'user-2');
  });
}
