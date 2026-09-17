import 'package:flutter_test/flutter_test.dart';
import 'package:jersirc/models/chat_room.dart';

void main() {
  test('adds and updates IRC user prefixes', () {
    final room = ChatRoomModel('#panama');
    room.addUser('Javier');
    expect(room.users['Javier']?.prefixes, '');
    room.setUserPrefixes('Javier', '@+');
    expect(room.users['Javier']?.isOp, isTrue);
    expect(room.users['Javier']?.hasVoice, isTrue);
  });

  test('renames and removes users', () {
    final room = ChatRoomModel('#panama');
    room.addUser('OldNick', prefixes: '@');
    room.renameUser('OldNick', 'NewNick');
    expect(room.users.containsKey('OldNick'), isFalse);
    expect(room.users['NewNick']?.isOp, isTrue);
    room.removeUser('NewNick');
    expect(room.users, isEmpty);
  });
}
