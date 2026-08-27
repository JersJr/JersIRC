import 'dart:async';
import 'dart:convert';
import 'dart:io';

class IrcMessage {
  final String raw; final String? prefix; final String command; final List<String> params;
  const IrcMessage(this.raw, this.prefix, this.command, this.params);
  String get trailing => params.isEmpty ? '' : params.last;
  String? get nick => prefix?.split('!').first;
  static IrcMessage parse(String raw) {
    var line = raw; String? prefix;
    if (line.startsWith(':')) { final space = line.indexOf(' '); if (space > 0) { prefix = line.substring(1, space); line = line.substring(space + 1); } }
    final parts = <String>[];
    while (line.isNotEmpty) { line = line.trimLeft(); if (line.isEmpty) break; if (line.startsWith(':')) { parts.add(line.substring(1)); break; } final space = line.indexOf(' '); if (space < 0) { parts.add(line); break; } parts.add(line.substring(0, space)); line = line.substring(space + 1); }
    final command = parts.isEmpty ? '' : parts.removeAt(0).toUpperCase();
    return IrcMessage(raw, prefix, command, parts);
  }
}

class IrcClient {
  Socket? _socket; StreamSubscription<String>? _subscription; final _messages = StreamController<IrcMessage>.broadcast(); bool _connected = false;
  Stream<IrcMessage> get messages => _messages.stream; bool get isConnected => _connected;
  Future<void> connect({required String host, required int port, required String nickname, String? username, bool secure = true}) async {
    await disconnect();
    final socket = secure ? await SecureSocket.connect(host, port, timeout: const Duration(seconds: 15)) : await Socket.connect(host, port, timeout: const Duration(seconds: 15));
    _socket = socket; _connected = true;
    _subscription = utf8.decoder.bind(socket).transform(const LineSplitter()).listen(_handleLine, onDone: () { _connected = false; _messages.add(const IrcMessage('', null, 'DISCONNECTED', [])); }, onError: (Object e) { _connected = false; _messages.add(IrcMessage(e.toString(), null, 'ERROR', [e.toString()])); });
    send('CAP LS 302'); send('NICK $nickname'); send('USER ${username ?? nickname} 0 * :JersIRC Android Client');
  }
  void _handleLine(String line) { final m = IrcMessage.parse(line); if (m.command == 'PING') send('PONG :${m.trailing}'); _messages.add(m); }
  void send(String command) { if (_connected && _socket != null) _socket!.write('$command\r\n'); }
  void join(String channel) => send('JOIN $channel');
  void part(String channel, [String? reason]) => send('PART $channel${reason == null ? '' : ' :$reason'}');
  void changeNick(String nickname) => send('NICK $nickname');
  void message(String target, String text) => send('PRIVMSG $target :$text');
  void notice(String target, String text) => send('NOTICE $target :$text');
  void quit([String reason = 'Leaving JersIRC']) => send('QUIT :$reason');
  Future<void> disconnect() async { _connected = false; await _subscription?.cancel(); _subscription = null; try { _socket?.write('QUIT :Leaving JersIRC\r\n'); } catch (_) {} try { await _socket?.close(); } catch (_) {} _socket = null; }
  Future<void> dispose() async { await disconnect(); await _messages.close(); }
}
