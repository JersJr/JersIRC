import 'dart:async';
import 'package:flutter/foundation.dart';
import '../irc_client.dart';
import '../models/chat_room.dart';

class IrcController extends ChangeNotifier {
  IrcController({IrcClient? client}) : client = client ?? IrcClient() {
    _subscription = this.client.messages.listen(handleMessage);
  }

  final IrcClient client;
  final Map<String, ChatRoomModel> rooms = {};
  final Set<String> ignoredUsers = <String>{};
  bool ignorePrivateMessages = false;
  bool showActivityNotifications = false;
  String? whoisNotice;
  String? _whoisTarget;
  final List<String> _whoisLines = <String>[];
  String? _pendingHostBanChannel, _pendingHostBanNick;
  final Set<String> _disconnectedUsers = <String>{};
  StreamSubscription<IrcMessage>? _subscription;
  Timer? _reconnectTimer;
  final List<String> moderationActivity = <String>[];
  final Map<String, String> channelBans = <String, String>{};
  final Map<String, Timer> _temporaryBanTimers = <String, Timer>{};
  Completer<void>? _banListCompleter;
  String? _pendingKickHostReason;
  String? _pendingKickHostChannel;
  String? _pendingKickHostNick;
  String? _lastHost, _lastNickname;
  int? _lastPort;
  bool _lastSecure = true;
  String? activeRoom;
  String status = 'Desconectado';
  String? banNotice;
  String? banChannel;
  bool banIsServer = true;
  bool connected = false, connecting = false, manualDisconnect = false, permanentConnectionFailure = false;
  Completer<List<IrcChannelInfo>>? _channelListCompleter;
  final Map<String, IrcChannelInfo> _listedChannels = <String, IrcChannelInfo>{};
  ChatRoomModel? get currentRoom => activeRoom == null ? null : rooms[activeRoom];

  Future<void> connect({required String host, required int port, required String nickname, bool secure = false, bool automatic = false}) async {
    if (connecting || connected) return;
    _lastHost = host.trim(); _lastPort = port; _lastNickname = nickname.trim(); _lastSecure = secure;
    _reconnectTimer?.cancel(); manualDisconnect = false; permanentConnectionFailure = false; banNotice = null; banChannel = null; banIsServer = true; connecting = true; connected = false;
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
  bool _isPermanentConnectionError(String value) { final x = value.toLowerCase(); return x.contains('nickname en uso') || x.contains('nickname en conflicto') || x.contains('nickname/recurso no disponible') || x.contains('nickname no válido') || x.contains('contraseña incorrecta') || x.contains('rechazada/bloqueada') || x.contains('baneado') || x.contains('banned') || x.contains('clones') || x.contains('clone') || x.contains('too many connections') || x.contains('k-line') || x.contains('g-line') || x.contains('z-line') || x.contains('akill'); }
  void scheduleReconnect({required String host, required int port, required String nickname, required bool secure}) { _lastHost = host.trim(); _lastPort = port; _lastNickname = nickname.trim(); _lastSecure = secure; _scheduleReconnectIfAllowed(); }

  Future<List<IrcChannelInfo>> listChannels({Duration timeout = const Duration(seconds: 10)}) async {
    if (!connected) return const <IrcChannelInfo>[];
    _channelListCompleter?.complete(_listedChannels.values.toList(growable: false));
    _channelListCompleter = Completer<List<IrcChannelInfo>>();
    _listedChannels.clear();
    client.sendRaw('LIST');
    try {
      return await _channelListCompleter!.future.timeout(timeout);
    } on TimeoutException {
      return _listedChannels.values.toList(growable: false);
    } finally {
      _channelListCompleter = null;
    }
  }

  void _cancelTemporaryBanTimers({String? channel}) {
    final prefix = channel == null ? null : '${channel.toLowerCase()}|';
    final keys = _temporaryBanTimers.keys.where((key) => prefix == null || key.startsWith(prefix)).toList();
    for (final key in keys) {
      _temporaryBanTimers.remove(key)?.cancel();
    }
  }

  Future<void> disconnect() async { manualDisconnect = true; _reconnectTimer?.cancel(); _cancelTemporaryBanTimers(); await client.disconnect(); connected = false; connecting = false; status = 'Desconectado'; notifyListeners(); }

  void join(String channel) { final n = channel.trim(); if (!connected || n.isEmpty) return; rooms.putIfAbsent(n, () => ChatRoomModel(n)); activeRoom = n; rooms[n]!.unread = 0; client.join(n); notifyListeners(); }
  void openPrivate(String nickname) { final n = nickname.trim(); if (!connected || n.isEmpty || ignoredUsers.contains(n.toLowerCase())) return; final existing = rooms.keys.firstWhere((key) => key.toLowerCase() == n.toLowerCase(), orElse: () => ''); if (existing.isNotEmpty) { activeRoom = existing; rooms[existing]!.unread = 0; } else { rooms[n] = ChatRoomModel(n, privateChat: true); activeRoom = n; } notifyListeners(); }
  void closeRoom(String name) { if (name.isEmpty) return; final key = rooms.keys.firstWhere((k) => k.toLowerCase() == name.toLowerCase(), orElse: () => ''); if (key.isEmpty) return; final r = rooms[key]!; if (!r.privateChat && connected) client.part(key); rooms.remove(key); if (activeRoom == key) activeRoom = rooms.isEmpty ? null : rooms.keys.first; notifyListeners(); }
  void changeNick(String nickname) { final n = nickname.trim(); if (connected && n.isNotEmpty) client.changeNick(n); }

  void sendMessage(String text) {
    final target = activeRoom, value = text.trim(); if (!connected || target == null || value.isEmpty) return;
    final targetRoom = rooms[target];
    if (targetRoom?.privateChat == true && _disconnectedUsers.contains(target.toLowerCase())) {
      _addDisconnectedNotice(target);
      return;
    }
    client.message(target, value);
    final localNick = (_lastNickname?.trim().isNotEmpty == true) ? _lastNickname!.trim() : 'local';
    rooms[target]?.messages.add(IrcMessage(':$localNick!local@local', localNick, 'PRIVMSG', [target, value]));
    notifyListeners();
  }

  void sendPrivate(String target, String text) {
    final t = target.trim(), v = text.trim(); if (!connected || t.isEmpty || v.isEmpty || ignoredUsers.contains(t.toLowerCase())) return;
    openPrivate(t);
    if (_disconnectedUsers.contains(t.toLowerCase())) {
      _addDisconnectedNotice(t);
      return;
    }
    client.message(t, v);
    final localNick = (_lastNickname?.trim().isNotEmpty == true) ? _lastNickname!.trim() : 'local';
    rooms[activeRoom]?.messages.add(IrcMessage(':$localNick!local@local', localNick, 'PRIVMSG', [t, v]));
    notifyListeners();
  }

  void _addDisconnectedNotice(String nickname) {
    final key = rooms.keys.firstWhere(
      (name) => name.toLowerCase() == nickname.toLowerCase(),
      orElse: () => '',
    );
    if (key.isEmpty) return;
    rooms[key]!.messages.add(
      const IrcMessage('', null, 'DISCONNECTED_USER', ['Usuario desconectado']),
    );
    rooms[key]!.unread = 0;
    activeRoom = key;
    notifyListeners();
  }

  void sendNotice(String target, String text) { if (connected && target.trim().isNotEmpty && text.trim().isNotEmpty) client.notice(target.trim(), text.trim()); }
  void sendAction(String target, String text) { if (connected && target.trim().isNotEmpty && text.trim().isNotEmpty) client.message(target.trim(), '\u0001ACTION ${text.trim()}\u0001'); }
  void toggleIgnore(String nickname) { final n = nickname.trim().toLowerCase(); if (n.isEmpty) return; if (!ignoredUsers.add(n)) ignoredUsers.remove(n); notifyListeners(); }
  void setIgnorePrivateMessages(bool value) { ignorePrivateMessages = value; notifyListeners(); }
  void setShowActivityNotifications(bool value) { showActivityNotifications = value; notifyListeners(); }
  void clearWhoisNotice() { whoisNotice = null; notifyListeners(); }
  void requestWhois(String nickname) { final n = nickname.trim(); if (!connected || n.isEmpty) return; _whoisTarget = n; _whoisLines.clear(); whoisNotice = null; client.sendRaw('WHOIS $n'); }
  void _logModeration(String line) {
    moderationActivity.insert(0, '${DateTime.now().toLocal().toString().substring(11, 19)} · $line');
    if (moderationActivity.length > 200) moderationActivity.removeLast();
  }

  ChatRoomModel? _findRoom(String channel) {
    for (final entry in rooms.entries) {
      if (entry.key.toLowerCase() == channel.toLowerCase()) return entry.value;
    }
    return null;
  }

  bool _roomContainsUser(ChatRoomModel room, String nickname) =>
      room.users.keys.any((nick) => nick.toLowerCase() == nickname.toLowerCase());

  void _addSystemEvent(String channel, String text) {
    if (!showActivityNotifications || channel.isEmpty || text.trim().isEmpty) return;
    final room = _findRoom(channel);
    if (room == null || room.privateChat) return;
    room.messages.add(IrcMessage('', null, 'SYSTEM', [channel, text]));
    if (activeRoom != room.name) room.unread++;
  }

  String _banKey(String channel, String mask) => '${channel.toLowerCase()}|${mask.toLowerCase()}';

  void requestBanList(String channel) {
    if (!connected || channel.isEmpty) return;
    channelBans.clear();
    _banListCompleter?.complete();
    _banListCompleter = Completer<void>();
    client.sendRaw('MODE $channel +b');
    notifyListeners();
  }

  void removeBan(String channel, String mask) {
    if (!connected || channel.isEmpty || mask.isEmpty) return;
    client.sendRaw('MODE $channel -b $mask');
    _logModeration('Solicitud para quitar ban $mask en $channel');
    notifyListeners();
  }

  void banNickname(String channel, String nickname) {
    if (!connected || channel.isEmpty || nickname.isEmpty) return;
    final mask = '$nickname!*@*';
    client.sendRaw('MODE $channel +b $mask');
    _logModeration('${_lastNickname ?? 'Tú'} baneó $mask en $channel');
    notifyListeners();
  }

  void temporaryBan(String channel, String nickname, int minutes) {
    if (!connected || channel.isEmpty || nickname.isEmpty || minutes < 1) return;
    final mask = '$nickname!*@*';
    final key = _banKey(channel, mask);
    _temporaryBanTimers.remove(key)?.cancel();
    final actor = _lastNickname ?? 'Un operador';
    client.sendRaw('MODE $channel +b $mask');
    client.sendRaw('KICK $channel $nickname :Silenciado durante $minutes ${minutes == 1 ? 'minuto' : 'minutos'}');
    _logModeration('$actor aplicó ban temporal a $mask por $minutes min en $channel');
    _temporaryBanTimers[key] = Timer(Duration(minutes: minutes), () {
      if (connected) {
        client.sendRaw('MODE $channel -b $mask');
        _logModeration('Ban temporal vencido: solicitud de quitar $mask en $channel');
        notifyListeners();
      }
      _temporaryBanTimers.remove(key);
    });
    notifyListeners();
  }

  void kickBanNickname(String channel, String nickname, String reason) {
    if (!connected || channel.isEmpty || nickname.isEmpty) return;
    final mask = '$nickname!*@*';
    final why = reason.trim().isEmpty ? 'Nick inadecuado' : reason.trim();
    final actor = _lastNickname ?? 'Un operador';
    client.sendRaw('MODE $channel +b $mask');
    client.sendRaw('KICK $channel $nickname :$why');
    _logModeration('$actor aplicó ban y kick a $nickname en $channel: $why');
    notifyListeners();
  }

  void kickBanVirtualHost(String channel, String nickname, String reason) {
    if (!connected || channel.isEmpty || nickname.isEmpty || reason.trim().isEmpty) return;
    _pendingKickHostChannel = channel;
    _pendingKickHostNick = nickname;
    _pendingKickHostReason = reason.trim();
    client.sendRaw('WHOIS $nickname');
  }
  void banVirtualHost(String channel, String nickname) { if (!connected || channel.isEmpty || nickname.isEmpty) return; _pendingHostBanChannel = channel; _pendingHostBanNick = nickname; client.sendRaw('WHOIS $nickname'); }
  void clearBanNotice() { banNotice = null; banChannel = null; banIsServer = true; }

  bool _looksLikeAccessBan(String text) {
    final x = text.toLowerCase();
    return x.contains('banned') || x.contains('baneado') || x.contains('ban from') || x.contains('k-line') || x.contains('kline') || x.contains('g-line') || x.contains('gline') || x.contains('z-line') || x.contains('zline') || x.contains('akill') || x.contains('clone') || x.contains('clon') || x.contains('too many connections') || x.contains('too many clients') || x.contains('connections from your host') || x.contains('more than 3') || x.contains('session limit');
  }

  void handleMessage(IrcMessage message) {
    if (message.command == 'BANNED') {
      connected = false; connecting = false; permanentConnectionFailure = true; _reconnectTimer?.cancel();
      banNotice = message.trailing.isEmpty ? 'Tu conexión ha sido bloqueada por el servidor.' : message.trailing; banIsServer = true; banChannel = null;
      status = 'Estás baneado del servidor'; notifyListeners(); return;
    }
    if (message.command == 'DISCONNECTED') { _cancelTemporaryBanTimers(); connected = false; connecting = false; if (!manualDisconnect && !permanentConnectionFailure) { status = 'Conexión perdida'; notifyListeners(); _scheduleReconnectIfAllowed(); } else { notifyListeners(); } return; }
    if (message.command == 'ERROR' || message.command == 'NOTICE') {
      final text = message.trailing.isEmpty ? message.params.join(' ') : message.trailing;
      if (_looksLikeAccessBan(text)) {
        connected = false; connecting = false; permanentConnectionFailure = true; _reconnectTimer?.cancel();
        banNotice = text.isEmpty ? 'El servidor rechazó la conexión.' : text; banIsServer = true; banChannel = null; status = 'Estás baneado del servidor'; notifyListeners(); return;
      }
      if (message.command == 'ERROR') { connected = false; connecting = false; status = text.isEmpty ? 'Error de conexión' : 'Error: $text'; notifyListeners(); _scheduleReconnectIfAllowed(); return; }
    }
    if (message.command == '001') { connected = true; connecting = false; status = 'Conectado'; _reconnectTimer?.cancel(); }
    final numeric = int.tryParse(message.command);
    if (numeric == 311 && message.params.length >= 5) {
      final targetNick = message.params[1];
      final user = message.params[2];
      final host = message.params[3];
      final realName = message.params.last;
      if (_whoisTarget != null && targetNick.toLowerCase() == _whoisTarget!.toLowerCase()) {
        _whoisLines.add('Nick: $targetNick');
        _whoisLines.add('Usuario: $user');
        _whoisLines.add('Host virtual: $host');
        if (realName.isNotEmpty) _whoisLines.add('Nombre: $realName');
      }
      if (_pendingKickHostNick != null && targetNick.toLowerCase() == _pendingKickHostNick!.toLowerCase()) {
        final channel = _pendingKickHostChannel!;
        final reason = _pendingKickHostReason!;
        final actor = _lastNickname ?? 'Un operador';
        client.sendRaw('MODE $channel +b *!*@$host');
        client.sendRaw('KICK $channel $targetNick :$reason');
        _logModeration('$actor aplicó ban de host y kick a $targetNick en $channel: $reason');
        _pendingKickHostChannel = null;
        _pendingKickHostNick = null;
        _pendingKickHostReason = null;
      }
      if (_pendingHostBanNick != null && targetNick.toLowerCase() == _pendingHostBanNick!.toLowerCase()) {
        final channel = _pendingHostBanChannel!;
        client.sendRaw('MODE $channel +b *!*@$host');
        _pendingHostBanChannel = null;
        _pendingHostBanNick = null;
      }
    }
    if (_whoisTarget != null && message.params.length >= 2 && message.params[1].toLowerCase() == _whoisTarget!.toLowerCase()) {
      if (numeric == 312) _whoisLines.add('Servidor: ${message.params.length > 2 ? message.params[2] : message.trailing}');
      if (numeric == 317) _whoisLines.add('Inactivo: ${message.params.length > 2 ? message.params[2] : message.trailing} segundos');
      if (numeric == 319) _whoisLines.add('Salas: ${message.trailing}');
      if (numeric == 301) _whoisLines.add('Ausencia: ${message.trailing}');
      if (numeric == 318) {
        if (_whoisLines.isEmpty) _whoisLines.add('El servidor no proporcionó datos WHOIS adicionales.');
        whoisNotice = 'Consulta de $_whoisTarget\n\n${_whoisLines.join('\n')}';
        _whoisTarget = null;
        notifyListeners();
      }
    }
    if (numeric != null && numeric >= 400 && numeric != 422) {
      status = friendlyError(message);
      if (numeric == 465) {
        connected = false; connecting = false; permanentConnectionFailure = true; _reconnectTimer?.cancel(); banNotice = message.trailing.isEmpty ? 'Tu conexión ha sido bloqueada por el servidor.' : message.trailing; banIsServer = true; banChannel = null;
      } else if (numeric == 474) {
        final channel = message.params.length >= 2 ? message.params[1] : (message.params.isNotEmpty ? message.params.last : 'la sala');
        banNotice = message.trailing.isEmpty ? 'No puedes entrar a esta sala.' : message.trailing; banIsServer = false; banChannel = channel; status = 'Estás baneado de $channel';
      } else if ({431, 432, 433, 436, 437, 451, 464}.contains(numeric)) {
        connected = false; connecting = false; permanentConnectionFailure = true; _reconnectTimer?.cancel();
      }
    }
    final sender = message.nick;
    if (message.command == 'JOIN' && message.params.isNotEmpty && sender != null) { final channel = message.params.last; final room = _findRoom(channel) ?? ( _sameNick(sender, _lastNickname) ? rooms.putIfAbsent(channel, () => ChatRoomModel(channel)) : null ); if (room != null) { room.addUser(sender); _disconnectedUsers.remove(sender.toLowerCase()); if (_sameNick(sender, _lastNickname)) { activeRoom ??= room.name; room.unread = 0; } else { _logModeration('$sender entró en ${room.name}'); _addSystemEvent(room.name, '$sender entró en la sala'); } } }
    if (message.command == 'PART' && message.params.isNotEmpty && sender != null) { final channel = message.params.first; final room = _findRoom(channel); room?.removeUser(sender); _logModeration('$sender salió de $channel'); if (!_sameNick(sender, _lastNickname) && room != null) _addSystemEvent(room.name, '$sender salió de la sala'); if (_sameNick(sender, _lastNickname)) { _cancelTemporaryBanTimers(channel: channel); final key = rooms.keys.firstWhere((name) => name.toLowerCase() == channel.toLowerCase(), orElse: () => ''); if (key.isNotEmpty) rooms.remove(key); if (activeRoom?.toLowerCase() == channel.toLowerCase()) activeRoom = rooms.isEmpty ? null : rooms.keys.first; } }
    if (message.command == 'QUIT' && sender != null) { _disconnectedUsers.add(sender.toLowerCase()); for (final room in rooms.values) { final wasInRoom = _roomContainsUser(room, sender); if (wasInRoom) { room.removeUser(sender); if (!room.privateChat) _addSystemEvent(room.name, '$sender se desconectó${message.trailing.isNotEmpty ? ' (${message.trailing})' : ''}'); } } _logModeration('$sender se desconectó (${message.trailing})'); }
    if (message.command == 'NICK' && sender != null && message.params.isNotEmpty) { final newNick = message.params.last; if (_disconnectedUsers.remove(sender.toLowerCase())) _disconnectedUsers.add(newNick.toLowerCase()); for (final room in rooms.values) { room.renameUser(sender, newNick); } if (_sameNick(sender, _lastNickname)) { _lastNickname = newNick; status = 'Nickname: $newNick'; } }
    if (message.command == 'KICK' && message.params.length >= 2) { final channel = message.params.first; final kicked = message.params[1]; final room = _findRoom(channel); room?.removeUser(kicked); if (room != null) _addSystemEvent(room.name, '$kicked fue expulsado por ${sender ?? 'operador'}${message.trailing.isNotEmpty ? ': ${message.trailing}' : ''}'); _logModeration('$kicked recibió kick en $channel por ${sender ?? 'operador'}: ${message.trailing}'); if (_sameNick(kicked, _lastNickname)) { final key = rooms.keys.firstWhere((name) => name.toLowerCase() == channel.toLowerCase(), orElse: () => ''); if (key.isNotEmpty) rooms.remove(key); if (activeRoom?.toLowerCase() == channel.toLowerCase()) activeRoom = rooms.isEmpty ? null : rooms.keys.first; status = 'Expulsado de $channel'; } }
    if (message.command == 'TOPIC' && message.params.isNotEmpty) { final room = rooms[message.params.first]; if (room != null) room.topic = message.trailing; }
    if (message.command == '332' && message.params.length >= 2) { final channel = message.params[1]; final room = rooms.putIfAbsent(channel, () => ChatRoomModel(channel)); room.topic = message.trailing; }
    if (message.command == '322' && message.params.length >= 4) {
      final channel = message.params[1];
      final users = int.tryParse(message.params[2]) ?? 0;
      final topic = message.params.last;
      _listedChannels[channel] = IrcChannelInfo(channel: channel, users: users, topic: topic);
    }
    if (message.command == '323') {
      final completer = _channelListCompleter;
      if (completer != null && !completer.isCompleted) completer.complete(_listedChannels.values.toList(growable: false));
    }
    if ((message.command == 'PRIVMSG' || message.command == 'NOTICE') && sender != null) _disconnectedUsers.remove(sender.toLowerCase());
    if (message.command == 'PRIVMSG' || message.command == 'NOTICE') _handleTextMessage(message, sender);
    if (message.command == '353' && message.params.length >= 3) { final channel = message.params[2]; final room = rooms.putIfAbsent(channel, () => ChatRoomModel(channel)); final names = message.trailing.trim(); if (names.isNotEmpty) { for (final raw in names.split(RegExp(r'\s+'))) { if (raw.isEmpty) continue; final match = RegExp(r'^([~&@%+]+)(.+)$').firstMatch(raw); final prefixes = match?.group(1) ?? ''; final nick = match?.group(2) ?? raw; if (nick.isNotEmpty) room.addUser(nick, prefixes: prefixes); } } }
    if (message.command == 'MODE' && message.params.length >= 2) {
      final channel = message.params.first;
      final modes = message.params[1];
      if (channel.startsWith('#') && modes.contains('b')) {
        final adding = !modes.startsWith('-');
        final mask = message.params.length > 2 ? message.params[2] : '';
        if (mask.isNotEmpty) {
          if (adding) channelBans[_banKey(channel, mask)] = mask;
          else channelBans.remove(_banKey(channel, mask));
          _logModeration('${sender ?? 'Servidor'} ${adding ? 'puso ban' : 'quitó ban'} $mask en $channel');
          _addSystemEvent(channel, '${sender ?? 'Servidor'} ${adding ? 'puso ban a' : 'quitó el ban de'} $mask');
        }
      }
      _applyUserModes(message);
    }
    if (message.command == '367' && message.params.length >= 3) {
      final channel = message.params[1], mask = message.params[2];
      channelBans[_banKey(channel, mask)] = mask;
    }
    if (message.command == '368') {
      _banListCompleter?.complete();
      _banListCompleter = null;
    }
    notifyListeners();
  }

  void _handleTextMessage(IrcMessage message, String? sender) {
    if (sender != null && ignoredUsers.contains(sender.toLowerCase())) return;
    if (message.params.isEmpty) return;
    final target = message.params.first;
    final isChannel = _isChannel(target);
    if (!isChannel && ignorePrivateMessages && !_sameNick(sender, _lastNickname)) return;
    final roomName = isChannel ? target : (sender ?? target);
    final existingKey = rooms.keys.firstWhere((key) => key.toLowerCase() == roomName.toLowerCase(), orElse: () => '');
    final room = existingKey.isNotEmpty ? rooms[existingKey]! : rooms.putIfAbsent(roomName, () => ChatRoomModel(roomName, privateChat: !isChannel));
    room.messages.add(message);
    if (activeRoom != room.name) {
      room.unread++;
    } else {
      room.unread = 0;
    }
    activeRoom ??= room.name;
  }

  bool _isChannel(String value) => value.startsWith('#') || value.startsWith('&') || value.startsWith('+') || value.startsWith('!');
  bool _sameNick(String? a, String? b) => a != null && b != null && a.toLowerCase() == b.toLowerCase();

  void _applyUserModes(IrcMessage message) {
    final target = message.params.first; if (!_isChannel(target)) return; final room = _findRoom(target); if (room == null) return;
    var adding = true; var arg = 2; const modeMap = {'q': '~', 'a': '&', 'o': '@', 'h': '%', 'v': '+'}; const modesWithArgument = {'q', 'a', 'o', 'h', 'v', 'b', 'e', 'I', 'k', 'l'};
    for (final mode in message.params[1].split('')) { if (mode == '+') { adding = true; continue; } if (mode == '-') { adding = false; continue; } if (!modesWithArgument.contains(mode)) continue; if (arg >= message.params.length) break; final value = message.params[arg++]; final prefix = modeMap[mode]; if (prefix == null) continue; var prefixes = room.users[value]?.prefixes ?? ''; if (adding && !prefixes.contains(prefix)) prefixes += prefix; if (!adding) prefixes = prefixes.replaceAll(prefix, ''); room.setUserPrefixes(value, prefixes); }
  }

  String friendlyError(IrcMessage message) { switch (message.command) { case '431': return 'Falta nickname'; case '432': return 'Nickname no válido: ${message.trailing}'; case '433': return 'Nickname en uso: ${message.trailing}'; case '436': return 'Nickname en conflicto: ${message.trailing}'; case '437': return 'Nickname/recurso no disponible: ${message.trailing}'; case '451': return 'El servidor aún no considera registrada la conexión'; case '464': return 'Contraseña incorrecta o requerida'; case '465': return 'Estás baneado del servidor: ${message.trailing}'; case '474': return 'Estás baneado de ${message.params.length >= 2 ? message.params[1] : 'la sala'}: ${message.trailing}'; case '422': return 'Sin MOTD'; default: return 'IRC ${message.command}: ${message.trailing}'; } }
  @override void dispose() { _reconnectTimer?.cancel(); for (final timer in _temporaryBanTimers.values) { timer.cancel(); } _temporaryBanTimers.clear(); _subscription?.cancel(); client.dispose(); super.dispose(); }
}


class IrcChannelInfo {
  final String channel;
  final int users;
  final String topic;

  const IrcChannelInfo({
    required this.channel,
    required this.users,
    required this.topic,
  });
}
