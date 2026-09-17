import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models/irc_message.dart';
import 'services/irc_parser.dart';

export 'models/irc_message.dart';

class IrcClient {
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  final _messages = StreamController<IrcMessage>.broadcast();
  final _parser = const IrcParser();
  Completer<void>? _readyCompleter;
  bool _connected = false;
  final List<int> _lineBuffer = <int>[];

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
    _readyCompleter = Completer<void>();
    _lineBuffer.clear();
    try {
      final socket = secure
          ? await SecureSocket.connect(host, port, timeout: const Duration(seconds: 15))
          : await Socket.connect(host, port, timeout: const Duration(seconds: 15));
      _socket = socket;
      _connected = true;
      _subscription = socket.listen(_handleBytes, onDone: () {
        _connected = false;
        if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!.completeError(StateError('El servidor cerró la conexión antes de completar el registro IRC.'));
        }
        _messages.add(const IrcMessage('', null, 'DISCONNECTED', []));
      }, onError: (Object e) {
        _connected = false;
        if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!.completeError(e);
        }
        _messages.add(IrcMessage(e.toString(), null, 'ERROR', [e.toString()]));
      });
      sendRaw('NICK $nickname');
      sendRaw('USER ${username ?? nickname} 0 * :JersIRC Android Client');
      await _readyCompleter!.future.timeout(const Duration(seconds: 20), onTimeout: () => throw TimeoutException('El servidor no respondió con 001 Welcome.'));
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  void _handleBytes(List<int> bytes) {
    _lineBuffer.addAll(bytes);
    while (true) {
      final newline = _lineBuffer.indexOf(10);
      if (newline < 0) return;
      var lineBytes = _lineBuffer.sublist(0, newline);
      _lineBuffer.removeRange(0, newline + 1);
      if (lineBytes.isNotEmpty && lineBytes.last == 13) {
        lineBytes = lineBytes.sublist(0, lineBytes.length - 1);
      }
      String line;
      try {
        line = utf8.decode(lineBytes, allowMalformed: false);
      } catch (_) {
        line = latin1.decode(lineBytes);
      }
      _handleLine(line);
    }
  }

  void _handleLine(String line) {
    final message = _parser.parse(line);
    if (message.command == 'PING') sendRaw('PONG :${message.trailing}');
    if (_isRegistrationError(message.command) && _readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(StateError('IRC ${message.command}: ${message.trailing}'));
    }
    if (message.command == '001' && _readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.complete();
    }
    _messages.add(message);
  }

  bool _isRegistrationError(String command) => const {'431', '432', '433', '436', '437', '451', '462', '464', '465'}.contains(command);

  void sendRaw(String command) { if (_connected && _socket != null) _socket!.write('$command\r\n'); }
  void send(String command) => sendRaw(command);
  void join(String channel) => sendRaw('JOIN $channel');
  void part(String channel, [String? reason]) => sendRaw('PART $channel${reason == null ? '' : ' :$reason'}');
  void changeNick(String nickname) => sendRaw('NICK $nickname');
  void message(String target, String text) => sendRaw('PRIVMSG $target :$text');
  void notice(String target, String text) => sendRaw('NOTICE $target :$text');
  void quit([String reason = 'Leaving JersIRC']) => sendRaw('QUIT :$reason');

  Future<void> disconnect() async {
    final socket = _socket;
    _connected = false;
    _readyCompleter = null;
    _lineBuffer.clear();
    await _subscription?.cancel();
    _subscription = null;
    try { socket?.write('QUIT :Leaving JersIRC\r\n'); } catch (_) {}
    try { await socket?.close(); } catch (_) {}
    _socket = null;
  }

  Future<void> dispose() async { await disconnect(); await _messages.close(); }
}
