import 'dart:async';
import 'dart:convert';
import 'dart:io';

class IrcMessage {
  final String raw;
  final String? prefix;
  final String command;
  final List<String> params;

  IrcMessage(this.raw, this.prefix, this.command, this.params);

  String get trailing => params.isEmpty ? '' : params.last;

  static IrcMessage parse(String raw) {
    var line = raw;
    String? prefix;
    if (line.startsWith(':')) {
      final space = line.indexOf(' ');
      if (space > 0) {
        prefix = line.substring(1, space);
        line = line.substring(space + 1);
      }
    }

    final parts = <String>[];
    while (line.isNotEmpty) {
      line = line.trimLeft();
      if (line.isEmpty) break;
      if (line.startsWith(':')) {
        parts.add(line.substring(1));
        break;
      }
      final space = line.indexOf(' ');
      if (space < 0) {
        parts.add(line);
        break;
      }
      parts.add(line.substring(0, space));
      line = line.substring(space + 1);
    }

    final command = parts.isEmpty ? '' : parts.removeAt(0);
    return IrcMessage(raw, prefix, command, parts);
  }
}

class IrcClient {
  Socket? _socket;
  StreamSubscription<String>? _subscription;
  final _messages = StreamController<IrcMessage>.broadcast();
  bool _connected = false;

  Stream<IrcMessage> get messages => _messages.stream;
  bool get isConnected => _connected;

  Future<void> connect({
    required String host,
    required int port,
    required String nickname,
    String? username,
    bool secure = true,
  }) async {
    await disconnect();

    final socket = secure
        ? await SecureSocket.connect(host, port, timeout: const Duration(seconds: 15))
        : await Socket.connect(host, port, timeout: const Duration(seconds: 15));

    _socket = socket;
    _connected = true;

    _subscription = socket
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: () {
      _connected = false;
      _messages.add(IrcMessage(':jersirc DISCONNECTED', null, 'DISCONNECTED', const []));
    }, onError: (Object error) {
      _connected = false;
      _messages.add(IrcMessage(':jersirc ERROR', null, 'ERROR', [error.toString()]));
    });

    send('CAP LS 302');
    send('NICK $nickname');
    send('USER ${username ?? nickname} 0 * :JersIRC user');
  }

  void _handleLine(String line) {
    final message = IrcMessage.parse(line);
    _messages.add(message);

    if (message.command == 'PING') {
      send('PONG :${message.trailing}');
    }
  }

  void send(String command) {
    if (!_connected || _socket == null) return;
    _socket!.write('$command\r\n');
  }

  void join(String channel) => send('JOIN $channel');
  void part(String channel) => send('PART $channel');
  void changeNick(String nickname) => send('NICK $nickname');
  void message(String target, String text) => send('PRIVMSG $target :$text');

  Future<void> disconnect() async {
    _connected = false;
    await _subscription?.cancel();
    _subscription = null;
    try {
      _socket?.write('QUIT :Leaving JersIRC\r\n');
    } catch (_) {}
    await _socket?.close();
    _socket = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}
