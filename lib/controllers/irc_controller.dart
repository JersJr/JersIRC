import 'dart:async';
import 'package:flutter/foundation.dart';
import '../irc_client.dart';
import '../models/chat_room.dart';
import '../models/irc_message.dart';

class IrcController extends ChangeNotifier {
  IrcController({IrcClient? client}) : client = client ?? IrcClient() {
    _subscription = this.client.messages.listen(handleMessage);
  }

  final IrcClient client;
  final Map<String, ChatRoomModel> rooms = {};
  final Set<String> ignoredUsers = <String>{};
  StreamSubscription<IrcMessage>? _subscription;
  Timer? _reconnectTimer;
  String? _lastHost, _lastNickname;
  int? _lastPort;
  bool _lastSecure = true;
  String? activeRoom;
  String status = 'Desconectado';
  bool connected = false, connecting = false, manualDisconnect = false, permanentConnectionFailure = false;
  ChatRoomModel? get currentRoom => activeRoom == null ? null : rooms[activeRoom];

  Future<void> connect({required String host, required int port, required String nickname, bool secure = false, bool automatic = false}) async {
    if (connecting || connected) return;
    _lastHost = host.trim(); _lastPort = port; _lastNickname = nickname.trim(); _lastSecure = secure;
    _reconnectTimer?.cancel(); manualDisconnect = false; permanentConnectionFailure = false; connecting = true; connected = false;
    status = automatic ? 'Reconectando...' : 'Conectando...'; notifyListeners();
    try {
      await client.connect(host: _lastHost!, port: port, nickname: _lastNickname!, secure: secure);
      connected = true; connecting = false; status = 'Conectado'; notifyListeners();
    } catch (error) {
      connected = false; connecting = false; status = error.toString().replaceFirst('StateError: ', '').replaceFirst('Exception: ', ''); notifyListeners(); _scheduleReconnectIfAllowed();
    }
  }

  void _scheduleReconnectIfAllowed() {
    if (manualDisconnect || connected || connecting || _lastHost == null || _lastPort == null || _lastNickname == null || _isPermanentConnectionError(status)) return;
    _reconnectTimer?.cancel(); status = 'Conexión perdida. Reintentando en 5 s...'; notifyListeners();
    _reconnectTimer = Timer(const Duration(seconds: 5), () => connect(host: _lastHost!, port: _lastPort!, nickname: _lastNickname!, secure: _lastSecure, automatic: true));
  }
  bool _isPermanentConnectionError(String value) { final x = value.toLowerCase(); return x.contains('nickname en uso') || x.contains('nickname en conflicto') || x.contains('nickname/recurso no disponible') || x.contains('nickname no válido') || x.contains('contraseña incorrecta') || x.contains('rechazada/bloqueada'); }
  void scheduleReconnect({required String host, required int port, required String nickname, required bool secure}) { _lastHost = host.trim(); _lastPort = port; _lastNickname = nickname.trim(); _lastSecure = secure; _scheduleReconnectIfAllowed(); }

  Future<void> disconnect() async { manualDisconnect = true; _reconnectTimer?.cancel(); await client.disconnect(); connected = false; connecting = false; status = 'Desconectado'; notifyListeners(); }

  void join(String channel) { final n = channel.trim(); if (!connected || n.isEmpty) return; rooms.putIfAbsent(n, () => ChatRoomModel(n)); activeRoom = n; rooms[n]!.unread = 0; client.join(n); notifyListeners(); }
  void openPrivate(String nickname) { final n = nickname.trim(); if (!connected || n.isEmpty) return; final existing = rooms.keys.firstWhere((key) => key.toLowerCase() == n.toLowerCase(), orElse: () => ''); if (existing.isNotEmpty) { activeRoom = existing; rooms[existing]!.unread = 0; } else { rooms[n] = ChatRoomModel(n, privateChat: true); activeRoom = n; } notifyListeners(); }
  void closeRoom(String name) { if (name.isEmpty) return; final key = rooms.keys.firstWhere((k) => k.toLowerCase() == name.toLowerCase(), orElse: () => ''); if (key.isEmpty) return; final r = rooms[key]!; if (!r.privateChat && connected) client.part(key); rooms.remove(key); if (activeRoom == key) activeRoom = rooms.isEmpty ? null : rooms.keys.first; notifyListeners(); }
  void changeNick(String nickname) { final n = nickname.trim(); if (connected && n.isNotEmpty) client.changeNick(n); }

  void sendMessage(String text) {
    final target = activeRoom, value = text.trim(); if (!connected || target == null || value.isEmpty) return;
    client.message(target, value);
    final localNick = (_lastNickname?.trim().isNotEmpty == true) ? _lastNickname!.trim() : 'local';
    rooms[target]?.messages.add(IrcMessage(':$localNick!local@local', localNick, 'PRIVMSG', [target, value]));
    notifyListeners();
  }

  void sendPrivate(String target, String text) {
    final t = target.trim(), v = text.trim(); if (!connected || t.isEmpty || v.isEmpty) return;
    openPrivate(t); client.message(t, v);
    final localNick = (_lastNickname?.trim().isNotEmpty == true) ? _lastNickname!.trim() : 'local';
    rooms[activeRoom]?.messages.add(IrcMessage(':$localNick!local@local', localNick, 'PRIVMSG', [t, v]));
    notifyListeners();
  }

  void sendNotice(String target, String text) { if (connected && target.trim().isNotEmpty && text.trim().isNotEmpty) client.notice(target.trim(), text.trim()); }
  void sendAction(String target, String text) { if (connected && target.trim().isNotEmpty && text.trim().isNotEmpty) client.message(target.trim(), '\u0001ACTION ${text.trim()}\u0001'); }
  void toggleIgnore(String nickname) { final n = nickname.trim().toLowerCase(); if (n.isEmpty) return; if (!ignoredUsers.add(n)) ignoredUsers.remove(n); notifyListeners(); }

  void handleMessage(IrcMessage message) {
    if (message.command == 'DISCONNECTED') { connected = false; connecting = false; if (!manualDisconnect && !permanentConnectionFailure) { status = 'Conexión perdida'; notifyListeners(); _scheduleReconnectIfAllowed(); } else { notifyListeners(); } return; }
    if (message.command == 'ERROR') { connected = false; connecting = false; status = message.trailing.isEmpty ? 'Error de conexión' : 'Error: ${message.trailing}'; notifyListeners(); _scheduleReconnectIfAllowed(); return; }
    if (message.command == '001') { connected = true; connecting = false; status = 'Conectado'; _reconnectTimer?.cancel(); }
    final numeric = int.tryParse(message.command);
    if (numeric != null && numeric >= 400 && numeric != 422) { status = friendlyError(message); if ({431, 432, 433, 436, 437, 451, 464, 465}.contains(numeric)) { connected = false; connecting = false; permanentConnectionFailure = true; _reconnectTimer?.cancel(); } }
    final sender = message.nick;
    if (message.command == 'JOIN' && message.params.isNotEmpty && sender != null) { final channel = message.params.last; final room = rooms.putIfAbsent(channel, () => ChatRoomModel(channel)); room.addUser(sender); if (_sameNick(sender, _lastNickname)) { activeRoom ??= channel; room.unread = 0; } }
    if (message.command == 'PART' && message.params.isNotEmpty && sender != null) { final channel = message.params.first; rooms[channel]?.removeUser(sender); if (_sameNick(sender, _lastNickname)) { rooms.remove(channel); if (activeRoom == channel) activeRoom = rooms.isEmpty ? null : rooms.keys.first; } }
    if (message.command == 'QUIT' && sender != null) { for (final room in rooms.values) { room.removeUser(sender); } }
    if (message.command == 'NICK' && sender != null && message.params.isNotEmpty) { final newNick = message.params.last; for (final room in rooms.values) { room.renameUser(sender, newNick); } if (_sameNick(sender, _lastNickname)) { _lastNickname = newNick; status = 'Nickname: $newNick'; } }
    if (message.command == 'KICK' && message.params.length >= 2) { final channel = message.params.first; final kicked = message.params[1]; rooms[channel]?.removeUser(kicked); if (_sameNick(kicked, _lastNickname)) { rooms.remove(channel); if (activeRoom == channel) activeRoom = rooms.isEmpty ? null : rooms.keys.first; status = 'Expulsado de $channel'; } }
    if (message.command == 'TOPIC' && message.params.isNotEmpty) { final room = rooms[message.params.first]; if (room != null) room.topic = message.trailing; }
    if (message.command == '332' && message.params.length >= 2) { final channel = message.params[1]; final room = rooms.putIfAbsent(channel, () => ChatRoomModel(channel)); room.topic = message.trailing; }
    if (message.command == 'PRIVMSG' || message.command == 'NOTICE') _handleTextMessage(message, sender);
    if (message.command == '353' && message.params.length >= 3) { final channel = message.params[2]; final room = rooms.putIfAbsent(channel, () => ChatRoomModel(channel)); final names = message.trailing.trim(); if (names.isNotEmpty) { for (final raw in names.split(RegExp(r'\s+'))) { if (raw.isEmpty) continue; final match = RegExp(r'^([~&@%+]+)(.+)$').firstMatch(raw); final prefixes = match?.group(1) ?? ''; final nick = match?.group(2) ?? raw; if (nick.isNotEmpty) room.addUser(nick, prefixes: prefixes); } } }
    if (message.command == 'MODE' && message.params.length >= 2) _applyUserModes(message);
    notifyListeners();
  }

  void _handleTextMessage(IrcMessage message, String? sender) {
    if (sender != null && ignoredUsers.contains(sender.toLowerCase())) return;
    if (message.params.isEmpty) return;
    final target = message.params.first;
    final isChannel = _isChannel(target);
    final roomName = isChannel ? target : (sender ?? target);
    final existingKey = rooms.keys.firstWhere((key) => key.toLowerCase() == roomName.toLowerCase(), orElse: () => '');
    final room = existingKey.isNotEmpty ? rooms[existingKey]! : rooms.putIfAbsent(roomName, () => ChatRoomModel(roomName, privateChat: !isChannel));
    room.messages.add(message);
    if (activeRoom != room.name) room.unread++; else room.unread = 0;
    activeRoom ??= room.name;
  }

  bool _isChannel(String value) => value.startsWith('#') || value.startsWith('&') || value.startsWith('+') || value.startsWith('!');
  bool _sameNick(String? a, String? b) => a != null && b != null && a.toLowerCase() == b.toLowerCase();

  void _applyUserModes(IrcMessage message) {
    final target = message.params.first; if (!_isChannel(target)) return; final room = rooms[target]; if (room == null) return;
    var adding = true; var arg = 2; const modeMap = {'q': '~', 'a': '&', 'o': '@', 'h': '%', 'v': '+'}; const modesWithArgument = {'q', 'a', 'o', 'h', 'v', 'b', 'e', 'I', 'k', 'l'};
    for (final mode in message.params[1].split('')) { if (mode == '+') { adding = true; continue; } if (mode == '-') { adding = false; continue; } if (!modesWithArgument.contains(mode)) continue; if (arg >= message.params.length) break; final value = message.params[arg++]; final prefix = modeMap[mode]; if (prefix == null) continue; var prefixes = room.users[value]?.prefixes ?? ''; if (adding && !prefixes.contains(prefix)) prefixes += prefix; if (!adding) prefixes = prefixes.replaceAll(prefix, ''); room.setUserPrefixes(value, prefixes); }
  }

  String friendlyError(IrcMessage message) { switch (message.command) { case '431': return 'Falta nickname'; case '432': return 'Nickname no válido: ${message.trailing}'; case '433': return 'Nickname en uso: ${message.trailing}'; case '436': return 'Nickname en conflicto: ${message.trailing}'; case '437': return 'Nickname/recurso no disponible: ${message.trailing}'; case '451': return 'El servidor aún no considera registrada la conexión'; case '464': return 'Contraseña incorrecta o requerida'; case '465': return 'Conexión rechazada/bloqueada: ${message.trailing}'; case '422': return 'Sin MOTD'; default: return 'IRC ${message.command}: ${message.trailing}'; } }
  @override void dispose() { _reconnectTimer?.cancel(); _subscription?.cancel(); client.dispose(); super.dispose(); }
}
