import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'models/irc_message.dart';
import 'services/irc_foreground_task.dart';
import 'services/irc_parser.dart';

export 'models/irc_message.dart';

class IrcClient {
  final _messages = StreamController<IrcMessage>.broadcast();
  Completer<void>? _readyCompleter;
  bool _connected = false;

  IrcClient() {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

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
    _connected = false;

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        serviceId: 2401,
        serviceTypes: const [ForegroundServiceTypes.remoteMessaging],
        notificationTitle: 'JersIRC conectado',
        notificationText: 'Manteniendo la conexión IRC activa',
        notificationInitialRoute: '/',
        callback: startIrcForegroundTask,
      );
    }

    FlutterForegroundTask.sendDataToTask(<String, dynamic>{
      'command': 'connect',
      'host': host,
      'port': port,
      'nickname': nickname,
      'secure': secure,
      'username': username ?? nickname,
    });

    try {
      await _readyCompleter!.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
          'El servidor no respondió con 001 Welcome.',
        ),
      );
    } catch (_) {
      _connected = false;
      rethrow;
    }
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    if (data['type'] == 'irc') {
      final raw = data['raw']?.toString();
      if (raw == null) return;
      final message = const IrcParser().parse(raw);
      if (message.command == '001') {
        _connected = true;
        if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!.complete();
        }
      }
      _messages.add(message);
      return;
    }
    if (data['type'] == 'banned') {
      _connected = false;
      _messages.add(const IrcMessage('', null, 'BANNED', []));
      return;
    }
    if (data['type'] == 'disconnected') {
      _connected = false;
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.completeError(
          StateError('El servidor cerró la conexión antes de completar el registro IRC.'),
        );
      }
      _messages.add(const IrcMessage('', null, 'DISCONNECTED', []));
      return;
    }
    if (data['type'] == 'error') {
      _connected = false;
      final error = data['error']?.toString() ?? 'Error de conexión';
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.completeError(StateError(error));
      }
      _messages.add(IrcMessage(error, null, 'ERROR', [error]));
    }
  }

  void sendRaw(String command) {
    FlutterForegroundTask.sendDataToTask(<String, dynamic>{
      'command': 'send',
      'raw': command,
    });
  }

  void send(String command) => sendRaw(command);
  void join(String channel) => sendRaw('JOIN $channel');
  void part(String channel, [String? reason]) =>
      sendRaw('PART $channel${reason == null ? '' : ' :$reason'}');
  void changeNick(String nickname) => sendRaw('NICK $nickname');
  void message(String target, String text) =>
      sendRaw('PRIVMSG $target :$text');
  void notice(String target, String text) =>
      sendRaw('NOTICE $target :$text');
  void quit([String reason = 'Leaving JersIRC']) =>
      sendRaw('QUIT :$reason');

  Future<void> disconnect() async {
    _connected = false;
    _readyCompleter = null;
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{
        'command': 'disconnect',
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> dispose() async {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    await _messages.close();
  }
}
