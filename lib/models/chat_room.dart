import '../irc_client.dart';
import 'irc_user.dart';

class ChatRoomModel {
  final String name;
  final bool privateChat;
  final List<IrcMessage> messages = <IrcMessage>[];
  final Map<String, IrcUser> users = <String, IrcUser>{};
  int unread = 0;
  String? topic;

  ChatRoomModel(this.name, {this.privateChat = false});

  void addUser(String nick, {String prefixes = ''}) {
    final existing = users[nick];
    users[nick] = existing == null
        ? IrcUser(nick, prefixes: prefixes)
        : existing.copyWith(prefixes: prefixes);
  }

  void removeUser(String nick) => users.remove(nick);

  void renameUser(String oldNick, String newNick) {
    final user = users.remove(oldNick);
    if (user != null) {
      users[newNick] = user.copyWith(nick: newNick);
    }
  }
}
