import 'package:flutter_test/flutter_test.dart';
import 'package:jersirc/services/irc_parser.dart';

void main() {
  const parser = IrcParser();

  test('parses PRIVMSG with trailing text containing spaces', () {
    final message = parser.parse(
      ':Nick!user@example.com PRIVMSG #panama :Hola desde JersIRC',
    );

    expect(message.command, 'PRIVMSG');
    expect(message.prefix, 'Nick!user@example.com');
    expect(message.nick, 'Nick');
    expect(message.params, ['#panama', 'Hola desde JersIRC']);
    expect(message.trailing, 'Hola desde JersIRC');
  });

  test('parses numeric IRC replies', () {
    final message = parser.parse(':server 001 JersIRC_User :Welcome to the network');

    expect(message.command, '001');
    expect(message.params, ['JersIRC_User', 'Welcome to the network']);
  });

  test('parses PING token', () {
    final message = parser.parse('PING :12345');

    expect(message.command, 'PING');
    expect(message.trailing, '12345');
  });
}
