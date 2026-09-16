import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models/irc_message.dart';
import 'services/irc_parser.dart';

// Kept as a public re-export so existing UI code can continue importing
// IrcMessage from irc_client.dart while the model lives in its own layer.
export 'models/irc_message.dart';

class IrcClient {
  Socket? _socket;
  StreamSubscription<String>? _subscription;
  final _messages = StreamController<IrcMessage>.broadcast();
  final _parser = const IrcParser();
  Completer<void>? _readyCompleter;
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
    _readyCompleter = Completer<void>();

    try {
      final socket = secure
          ? await SecureSocket.connect(host, port, timeout: const Duration(seconds: 15))
          : await Socket.connect(host, port, timeout: const Duration(seconds: 15));

      _socket = socket;
      _connected = true;

      // Some IRC servers can emit malformed UTF-8 during banners/NAMES.
      // Do not tear down an otherwise valid IRC connection because of it.
      _subscription = const Utf8Decoder(allowMalformed: true)
          .bind(socket)
          .transform(const LineSplitter())
          .listen(_handleLine, onDone: () {
            _connected = false;
            if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
              _readyCompleter!.completeError(
                StateError('El servidor cerró la conexión antes de completar el registro IRC.'),
              );
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

      await _readyCompleter!.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('El servidor no respondió con 001 Welcome.'),
      );
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  void _handleLine(String line) {
    final message = _parser.parse(line);

    // IRC servers use PING as the application-level keepalive. It must be
    // answered even before registration has completed.
    if (message.command == 'PING') {
      sendRaw('PONG :${message.trailing}');
    }

    if (_isRegistrationError(message.command) &&
        _readyCompleter != null &&
        !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(
        StateError('IRC ${message.command}: ${message.trailing}'),
      );
    }

    if (message.command == '001' &&
        _readyCompleter != null &&
        !_readyCompleter!.isCompleted) {
      _readyCompleter!.complete();
    }

    _messages.add(message);
  }

  bool _isRegistrationError(String command) {
    return const {
      '431',
      '432',
      '433',
      '436',
      '437',
      '451',
      '462',
      '464',
      '465',
    }.contains(command);
  }

  /// Sends one complete IRC command. CRLF is appended automatically.
  void sendRaw(String command) {
    if (_connected && _socket != null) {
      _socket!.write('$command\r\n');
    }
  }

  // Backwards-compatible alias used by the existing UI.
  void send(String command) => sendRaw(command);

  void join(String channel) => sendRaw('JOIN $channel');

  void part(String channel, [String? reason]) => sendRaw(
        'PART $channel${reason == null ? '' : ' :$reason'}',
      );

  void changeNick(String nickname) => sendRaw('NICK $nickname');

  void message(String target, String text) => sendRaw('PRIVMSG $target :$text');

  void notice(String target, String text) => sendRaw('NOTICE $target :$text');

  void quit([String reason = 'Leaving JersIRC']) => sendRaw('QUIT :$reason');

  Future<void> disconnect() async {
    final socket = _socket;
    _connected = false;
    _readyCompleter = null;
    await _subscription?.cancel();
    _subscription = null;

    try {
      socket?.write('QUIT :Leaving JersIRC\r\n');
    } catch (_) {}

    try {
      await socket?.close();
    } catch (_) {}

    _socket = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
  }
}
