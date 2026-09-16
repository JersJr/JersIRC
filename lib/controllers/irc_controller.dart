import 'dart:async';

import 'package:flutter/foundation.dart';

import '../irc_client.dart';
import '../models/chat_room.dart';
import '../models/irc_message.dart';

/// UI-independent coordinator for IRC connection state, rooms and incoming events.
///
/// The current screen can migrate to this controller incrementally without changing
/// the IRC transport itself.
class IrcController extends ChangeNotifier {
  IrcController({IrcClient? client}) : client = client ?? IrcClient() {
    _subscription = this.client.messages.listen(handleMessage);
  }

  final IrcClient client;
  final Map<String, ChatRoomModel> rooms = {};
  final Set<String> ignoredUsers = <String>{};

  StreamSubscription<IrcMessage>? _subscription;
  Timer? _reconnectTimer;

  String? activeRoom;
  String status = 'Desconectado';
  bool connected = false;
  bool connecting = false;
  bool manualDisconnect = false;

  ChatRoomModel? get currentRoom => activeRoom == null ? null : rooms[activeRoom];

  Future<void> connect({
    required String host,
    required int port,
    required String nickname,
    bool secure = false,
    bool automatic = false,
  }) async {
    if (connecting || connected) return;

    _reconnectTimer?.cancel();
    manualDisconnect = false;
    connecting = true;
    connected = false;
    status = automatic ? 'Reconectando...' : 'Conectando...';
    notifyListeners();

    try {
      await client.connect(
        host: host.trim(),
        port: port,
        nickname: nickname.trim(),
        secure: secure,
      );
      connected = true;
      connecting = false;
      status = 'Conectado';
      notifyListeners();
    } catch (error) {
      connected = false;
      connecting = false;
      status = error.toString().replaceFirst('StateError: ', '').replaceFirst('Exception: ', '');
      notifyListeners();
      if (!manualDisconnect && !status.toLowerCase().contains('nickname en uso')) {
        scheduleReconnect(host: host, port: port, nickname: nickname, secure: secure);
      }
    }
  }

  void scheduleReconnect({
    required String host,
    required int port,
    required String nickname,
    required bool secure,
  }) {
    if (manualDisconnect || connected || connecting) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      connect(
        host: host,
        port: port,
        nickname: nickname,
        secure: secure,
        automatic: true,
      );
    });
  }

  Future<void> disconnect() async {
    manualDisconnect = true;
    _reconnectTimer?.cancel();
    await client.disconnect();
    connected = false;
    connecting = false;
    status = 'Desconectado';
    notifyListeners();
  }

  void join(String channel) {
    final name = channel.trim();
    if (!connected || name.isEmpty) return;
    rooms.putIfAbsent(name, () => ChatRoomModel(name));
    activeRoom = name;
    rooms[name]!.unread = 0;
    client.join(name);
    notifyListeners();
  }

  void openPrivate(String nickname) {
    final name = nickname.trim();
    if (!connected || name.isEmpty) return;
    rooms.putIfAbsent(name, () => ChatRoomModel(name, privateChat: true));
    activeRoom = name;
    rooms[name]!.unread = 0;
    notifyListeners();
  }

  void closeRoom(String name) {
    final room = rooms[name];
    if (room == null) return;
    if (!room.privateChat && connected) client.part(name);
    rooms.remove(name);
    if (activeRoom == name) {
      activeRoom = rooms.isEmpty ? null : rooms.keys.first;
    }
    notifyListeners();
  }

  void sendMessage(String text) {
    final target = activeRoom;
    final value = text.trim();
    if (!connected || target == null || value.isEmpty) return;

    client.message(target, value);
    rooms[target]?.messages.add(
      IrcMessage(':local!local@local', 'local', 'PRIVMSG', <String>[target, value]),
    );
    notifyListeners();
  }

  void handleMessage(IrcMessage message) {
    if (message.command == 'DISCONNECTED') {
      connected = false;
      connecting = false;
      if (!manualDisconnect) status = 'Conexión perdida';
      notifyListeners();
      return;
    }

    if (message.command == 'ERROR') {
      connected = false;
      connecting = false;
      status = message.trailing.isEmpty ? 'Error de conexión' : 'Error: ${message.trailing}';
      notifyListeners();
      return;
    }

    if (message.command == '001') {
      connected = true;
      connecting = false;
      status = 'Conectado';
    }

    final numeric = int.tryParse(message.command);
    if (numeric != null && numeric >= 400 && numeric != 422) {
      status = friendlyError(message);
      if ({431, 432, 433, 436, 437, 451, 464, 465}.contains(numeric)) {
        connected = false;
        connecting = false;
        _reconnectTimer?.cancel();
      }
    }

    if (message.command == 'JOIN' && message.params.isNotEmpty) {
      final roomName = message.params.last;
      final room = rooms.putIfAbsent(roomName, () => ChatRoomModel(roomName));
      if (message.nick != null) room.addUser(message.nick!);
      activeRoom ??= roomName;
    }

    if (message.command == 'PART' && message.params.isNotEmpty && message.nick != null) {
      rooms[message.params.first]?.removeUser(message.nick!);
    }

    if (message.command == 'QUIT' && message.nick != null) {
      for (final room in rooms.values) {
        room.removeUser(message.nick!);
      }
    }

    if (message.command == 'NICK' && message.nick != null && message.params.isNotEmpty) {
      final newNick = message.params.last;
      for (final room in rooms.values) {
        room.renameUser(message.nick!, newNick);
      }
    }

    if (message.command == 'KICK' && message.params.length >= 2) {
      rooms[message.params.first]?.removeUser(message.params[1]);
    }

    if ((message.command == 'PRIVMSG' || message.command == 'NOTICE') && message.params.isNotEmpty) {
      final sender = message.nick;
      if (sender != null && ignoredUsers.contains(sender.toLowerCase())) return;

      final target = message.params.first;
      final isChannel = target.startsWith('#') || target.startsWith('&') || target.startsWith('+') || target.startsWith('!');
      final roomName = isChannel ? target : (sender ?? target);
      final room = rooms.putIfAbsent(roomName, () => ChatRoomModel(roomName, privateChat: !isChannel));
      room.messages.add(message);
      if (activeRoom != roomName) {
        room.unread++;
      } else {
        room.unread = 0;
      }
      activeRoom ??= roomName;
    }

    if (message.command == '353' && message.params.length >= 3) {
      final room = rooms.putIfAbsent(message.params[2], () => ChatRoomModel(message.params[2]));
      for (final raw in message.trailing.split(RegExp(r'\s+'))) {
        if (raw.isEmpty) continue;
        final match = RegExp(r'^([~&@%+]+)(.+)$').firstMatch(raw);
        final prefixes = match?.group(1) ?? '';
        final user = match?.group(2) ?? raw;
        if (user.isNotEmpty) room.addUser(user, prefixes: prefixes);
      }
    }

    if (message.command == 'MODE' && message.params.length >= 2) {
      _applyUserModes(message);
    }

    notifyListeners();
  }

  void _applyUserModes(IrcMessage message) {
    final target = message.params.first;
    if (!target.startsWith('#')) return;
    final room = rooms[target];
    if (room == null) return;

    var adding = true;
    var arg = 2;
    const modeMap = {'q': '~', 'a': '&', 'o': '@', 'h': '%', 'v': '+'};

    for (final mode in message.params[1].split('')) {
      if (mode == '+') {
        adding = true;
        continue;
      }
      if (mode == '-') {
        adding = false;
        continue;
      }
      if (!'ovhqa'.contains(mode) || arg >= message.params.length) continue;

      final user = message.params[arg++];
      final prefix = modeMap[mode];
      if (prefix == null) continue;
      var prefixes = room.users[user]?.prefixes ?? '';
      if (adding && !prefixes.contains(prefix)) prefixes += prefix;
      if (!adding) prefixes = prefixes.replaceAll(prefix, '');
      room.setUserPrefixes(user, prefixes);
    }
  }

  String friendlyError(IrcMessage message) {
    switch (message.command) {
      case '431': return 'Falta nickname';
      case '432': return 'Nickname no válido: ${message.trailing}';
      case '433': return 'Nickname en uso: ${message.trailing}';
      case '436': return 'Nickname en conflicto: ${message.trailing}';
      case '437': return 'Nickname/recurso no disponible: ${message.trailing}';
      case '451': return 'El servidor aún no considera registrada la conexión';
      case '464': return 'Contraseña incorrecta o requerida';
      case '465': return 'Conexión rechazada/bloqueada: ${message.trailing}';
      case '422': return 'Sin MOTD';
      default: return 'IRC ${message.command}: ${message.trailing}';
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    client.dispose();
    super.dispose();
  }
}
