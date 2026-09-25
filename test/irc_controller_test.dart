import 'package:flutter_test/flutter_test.dart';

import 'package:jersirc/controllers/irc_controller.dart';
import 'package:jersirc/models/irc_message.dart';

void main() {
  test('creates a room and tracks users from IRC events', () {
    final controller = IrcController();
    addTearDown(controller.dispose);

    controller.handleMessage(IrcMessage(':alice!u@h', 'alice', 'JOIN', ['#panama']));
    controller.handleMessage(IrcMessage(':server', null, '353', ['JersIRC_User', '=', '#panama', '@alice +bob carol']));

    final room = controller.rooms['#panama'];
    expect(room, isNotNull);
    expect(room!.users.keys, containsAll(<String>['alice', 'bob', 'carol']));
    expect(room.users['alice']!.isOp, isTrue);
    expect(room.users['bob']!.hasVoice, isTrue);
  });

  test('routes channel and private messages to separate rooms', () {
    final controller = IrcController();
    addTearDown(controller.dispose);

    controller.handleMessage(IrcMessage(':alice!u@h', 'alice', 'PRIVMSG', ['#panama', 'hola']));
    controller.handleMessage(IrcMessage(':bob!u@h', 'bob', 'PRIVMSG', ['JersIRC_User', 'privado']));

    expect(controller.rooms['#panama']!.messages.single.trailing, 'hola');
    expect(controller.rooms['bob']!.privateChat, isTrue);
    expect(controller.rooms['bob']!.messages.single.trailing, 'privado');
  });

  test('ignores messages from ignored users', () {
    final controller = IrcController();
    addTearDown(controller.dispose);

    controller.ignoredUsers.add('alice');
    controller.handleMessage(IrcMessage(':alice!u@h', 'alice', 'PRIVMSG', ['#panama', 'ignored']));

    expect(controller.rooms, isEmpty);
  });
}
