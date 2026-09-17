import 'dart:async';
import 'package:flutter/foundation.dart';
import '../irc_client.dart';
import '../models/chat_room.dart';
import '../models/irc_message.dart';

class IrcController extends ChangeNotifier {
  IrcController({IrcClient? client}) : client = client ?? IrcClient() { _subscription = this.client.messages.listen(handleMessage); }
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
  bool connected = false, connecting = false, manualDisconnect = false;
  ChatRoomModel? get currentRoom => activeRoom == null ? null : rooms[activeRoom];

  Future<void> connect({required String host, required int port, required String nickname, bool secure = false, bool automatic = false}) async {
    if (connecting || connected) return;
    _lastHost = host.trim(); _lastPort = port; _lastNickname = nickname.trim(); _lastSecure = secure;
    _reconnectTimer?.cancel(); manualDisconnect = false; connecting = true; connected = false; status = automatic ? 'Reconectando...' : 'Conectando...'; notifyListeners();
    try { await client.connect(host: _lastHost!, port: port, nickname: _lastNickname!, secure: secure); connected = true; connecting = false; status = 'Conectado'; notifyListeners(); }
    catch (error) { connected = false; connecting = false; status = error.toString().replaceFirst('StateError: ', '').replaceFirst('Exception: ', ''); notifyListeners(); _scheduleReconnectIfAllowed(); }
  }
  void _scheduleReconnectIfAllowed() { if (manualDisconnect || connected || connecting || _lastHost == null || _lastPort == null || _lastNickname == null || _isPermanentConnectionError(status)) return; _reconnectTimer?.cancel(); status = 'Conexión perdida. Reintentando en 5 s...'; notifyListeners(); _reconnectTimer = Timer(const Duration(seconds: 5), () => connect(host: _lastHost!, port: _lastPort!, nickname: _lastNickname!, secure: _lastSecure, automatic: true)); }
  bool _isPermanentConnectionError(String v) { final x = v.toLowerCase(); return x.contains('nickname en uso') || x.contains('nickname no válido') || x.contains('contraseña incorrecta') || x.contains('rechazada/bloqueada'); }
  void scheduleReconnect({required String host, required int port, required String nickname, required bool secure}) { _lastHost = host.trim(); _lastPort = port; _lastNickname = nickname.trim(); _lastSecure = secure; _scheduleReconnectIfAllowed(); }
  Future<void> disconnect() async { manualDisconnect = true; _reconnectTimer?.cancel(); await client.disconnect(); connected = false; connecting = false; status = 'Desconectado'; notifyListeners(); }
  void join(String channel) { final n = channel.trim(); if (!connected || n.isEmpty) return; rooms.putIfAbsent(n, () => ChatRoomModel(n)); activeRoom = n; rooms[n]!.unread = 0; client.join(n); notifyListeners(); }
  void openPrivate(String nickname) { final n = nickname.trim(); if (!connected || n.isEmpty) return; rooms.putIfAbsent(n, () => ChatRoomModel(n, privateChat: true)); activeRoom = n; rooms[n]!.unread = 0; notifyListeners(); }
  void closeRoom(String name) { if (name.isEmpty) return; final r = rooms[name]; if (r == null) return; if (!r.privateChat && connected) client.part(name); rooms.remove(name); if (activeRoom == name) activeRoom = rooms.isEmpty ? null : rooms.keys.first; notifyListeners(); }
  void changeNick(String nickname) { final n = nickname.trim(); if (connected && n.isNotEmpty) client.changeNick(n); }
  void sendMessage(String text) { final target = activeRoom, value = text.trim(); if (!connected || target == null || value.isEmpty) return; client.message(target, value); rooms[target]?.messages.add(IrcMessage(':local!local@local', 'local', 'PRIVMSG', [target, value])); notifyListeners(); }
  void sendPrivate(String target, String text) { final t = target.trim(), v = text.trim(); if (!connected || t.isEmpty || v.isEmpty) return; openPrivate(t); client.message(t, v); rooms[t]?.messages.add(IrcMessage(':local!local@local', 'local', 'PRIVMSG', [t, v])); notifyListeners(); }
  void sendNotice(String target, String text) { if (connected && target.trim().isNotEmpty && text.trim().isNotEmpty) client.notice(target.trim(), text.trim()); }
  void sendAction(String target, String text) { if (connected && target.trim().isNotEmpty && text.trim().isNotEmpty) client.message(target.trim(), '\u0001ACTION ${text.trim()}\u0001'); }
  void toggleIgnore(String nickname) { final n = nickname.trim().toLowerCase(); if (n.isEmpty) return; if (!ignoredUsers.add(n)) ignoredUsers.remove(n); notifyListeners(); }

  void handleMessage(IrcMessage message) {
    if (message.command == 'DISCONNECTED') { connected = false; connecting = false; if (!manualDisconnect) { status = 'Conexión perdida'; notifyListeners(); _scheduleReconnectIfAllowed(); } else notifyListeners(); return; }
    if (message.command == 'ERROR') { connected = false; connecting = false; status = message.trailing.isEmpty ? 'Error de conexión' : 'Error: ${message.trailing}'; notifyListeners(); _scheduleReconnectIfAllowed(); return; }
    if (message.command == '001') { connected = true; connecting = false; status = 'Conectado'; _reconnectTimer?.cancel(); }
    final numeric = int.tryParse(message.command);
    if (numeric != null && numeric >= 400 && numeric != 422) { status = friendlyError(message); if ({431,432,433,436,437,451,464,465}.contains(numeric)) { connected = false; connecting = false; _reconnectTimer?.cancel(); } }
    if (message.command == 'JOIN' && message.params.isNotEmpty) { final n = message.params.last; final r = rooms.putIfAbsent(n, () => ChatRoomModel(n)); if (message.nick != null) r.addUser(message.nick!); activeRoom ??= n; }
    if (message.command == 'PART' && message.params.isNotEmpty && message.nick != null) rooms[message.params.first]?.removeUser(message.nick!);
    if (message.command == 'QUIT' && message.nick != null) for (final r in rooms.values) r.removeUser(message.nick!);
    if (message.command == 'NICK' && message.nick != null && message.params.isNotEmpty) for (final r in rooms.values) r.renameUser(message.nick!, message.params.last);
    if (message.command == 'KICK' && message.params.length >= 2) rooms[message.params.first]?.removeUser(message.params[1]);
    if ((message.command == 'PRIVMSG' || message.command == 'NOTICE') && message.params.isNotEmpty) { final sender = message.nick; if (sender != null && ignoredUsers.contains(sender.toLowerCase())) return; final target = message.params.first; final isChannel = target.startsWith('#') || target.startsWith('&') || target.startsWith('+') || target.startsWith('!'); final n = isChannel ? target : (sender ?? target); final r = rooms.putIfAbsent(n, () => ChatRoomModel(n, privateChat: !isChannel)); r.messages.add(message); if (activeRoom != n) r.unread++; else r.unread = 0; activeRoom ??= n; }
    if (message.command == '353' && message.params.length >= 3) { final r = rooms.putIfAbsent(message.params[2], () => ChatRoomModel(message.params[2])); for (final raw in message.trailing.split(RegExp(r'\s+'))) { if (raw.isEmpty) continue; final m = RegExp(r'^([~&@%+]+)(.+)$').firstMatch(raw); final prefixes = m?.group(1) ?? ''; final user = m?.group(2) ?? raw; if (user.isNotEmpty) r.addUser(user, prefixes: prefixes); } }
    if (message.command == 'MODE' && message.params.length >= 2) _applyUserModes(message);
    notifyListeners();
  }
  void _applyUserModes(IrcMessage message) { final target = message.params.first; if (!target.startsWith('#')) return; final room = rooms[target]; if (room == null) return; var adding = true; var arg = 2; const modeMap = {'q':'~','a':'&','o':'@','h':'%','v':'+'}; for (final mode in message.params[1].split('')) { if (mode == '+') { adding = true; continue; } if (mode == '-') { adding = false; continue; } final prefix = modeMap[mode]; if (prefix == null || arg >= message.params.length) continue; final user = message.params[arg++]; var prefixes = room.users[user]?.prefixes ?? ''; if (adding && !prefixes.contains(prefix)) prefixes += prefix; if (!adding) prefixes = prefixes.replaceAll(prefix, ''); room.setUserPrefixes(user, prefixes); } }
  String friendlyError(IrcMessage message) { switch (message.command) { case '431': return 'Falta nickname'; case '432': return 'Nickname no válido: ${message.trailing}'; case '433': return 'Nickname en uso: ${message.trailing}'; case '436': return 'Nickname en conflicto: ${message.trailing}'; case '437': return 'Nickname/recurso no disponible: ${message.trailing}'; case '451': return 'El servidor aún no considera registrada la conexión'; case '464': return 'Contraseña incorrecta o requerida'; case '465': return 'Conexión rechazada/bloqueada: ${message.trailing}'; case '422': return 'Sin MOTD'; default: return 'IRC ${message.command}: ${message.trailing}'; } }
  @override void dispose() { _reconnectTimer?.cancel(); _subscription?.cancel(); client.dispose(); super.dispose(); }
}
