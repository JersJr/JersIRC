import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/irc_parser.dart';

@pragma('vm:entry-point')
void startIrcForegroundTask() {
  FlutterForegroundTask.setTaskHandler(IrcForegroundTaskHandler());
}

class IrcForegroundTaskHandler extends TaskHandler {
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  final _parser = const IrcParser();
  final List<int> _lineBuffer = <int>[];
  bool _manualDisconnect = false;
  bool _connecting = false;
  String? _host;
  int? _port;
  String? _nickname;
  bool _secure = false;
  Timer? _reconnectTimer;
  bool _permanentConnectionFailure = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.updateService(
      notificationTitle: 'JersIRC conectado',
      notificationText: 'Manteniendo la conexión IRC activa',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _reconnectTimer?.cancel();
    await _closeSocket();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final command = data['command']?.toString();
    switch (command) {
      case 'connect':
        _host = data['host']?.toString().trim();
        _port = int.tryParse('${data['port']}');
        _nickname = data['nickname']?.toString().trim();
        _secure = data['secure'] == true;
        _manualDisconnect = false;
        _permanentConnectionFailure = false;
        _reconnectTimer?.cancel();
        _connect();
        break;
      case 'disconnect':
        _manualDisconnect = true;
        _reconnectTimer?.cancel();
        _closeSocket();
        break;
      case 'send':
        final raw = data['raw']?.toString();
        if (raw != null && raw.trim().isNotEmpty) _sendRaw(raw);
        break;
    }
  }

  Future<void> _connect() async {
    if (_connecting || _socket != null) return;
    if (_host == null || _port == null || _nickname == null || _nickname!.isEmpty) return;

    _connecting = true;
    _lineBuffer.clear();
    await _closeSocket();

    try {
      final socket = _secure
          ? await SecureSocket.connect(_host!, _port!, timeout: const Duration(seconds: 15))
          : await Socket.connect(_host!, _port!, timeout: const Duration(seconds: 15));
      _socket = socket;
      _subscription = socket.listen(
        _handleBytes,
        onDone: _handleDisconnect,
        onError: (Object error) {
          _emitError(error.toString());
          _handleDisconnect();
        },
        cancelOnError: false,
      );
      _sendRaw('NICK $_nickname');
      _sendRaw('USER $_nickname 0 * :JersIRC Android Client');
      FlutterForegroundTask.updateService(
        notificationTitle: 'JersIRC conectado',
        notificationText: 'Conectado a $_host:$_port',
      );
    } catch (error) {
      _emitError(error.toString());
      _scheduleReconnect();
    } finally {
      _connecting = false;
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
    if (message.command == 'PING') _sendRaw('PONG :${message.trailing}');
    if (_isBanMessage(message)) {
      _permanentConnectionFailure = true;
      FlutterForegroundTask.sendDataToMain(<String, dynamic>{'type': 'banned'});
    }
    FlutterForegroundTask.sendDataToMain(<String, dynamic>{
      'type': 'irc',
      'raw': line,
    });

    if (message.command == 'PRIVMSG' && message.params.isNotEmpty && message.nick != null) {
      final target = message.params.first;
      final isChannel = target.startsWith('#') ||
          target.startsWith('&') ||
          target.startsWith('+') ||
          target.startsWith('!');
      if (!isChannel) {
        final text = message.trailing.replaceAll(RegExp(r'\\x01ACTION |\\x01'), '');
        FlutterForegroundTask.updateService(
          notificationTitle: 'Mensaje privado de ${message.nick}',
          notificationText: text.isEmpty ? 'Nuevo mensaje privado' : text,
        );
      }
    }
  }

  void _sendRaw(String command) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.write('$command\r\n');
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (_socket == null && !_connecting) return;
    _socket = null;
    _subscription?.cancel();
    _subscription = null;
    FlutterForegroundTask.sendDataToMain(<String, dynamic>{
      'type': 'disconnected',
    });
    if (!_manualDisconnect && !_permanentConnectionFailure) _scheduleReconnect();
  }

  bool _isBanMessage(IrcMessage message) {
    if (message.command == '465') return true;
    if (message.command != 'ERROR' && message.command != 'NOTICE') return false;
    final text = '${message.trailing} ${message.params.join(' ')}'.toLowerCase();
    return text.contains('banned') || text.contains('ban') || text.contains('k-line') || text.contains('kline') || text.contains('g-line') || text.contains('gline') || text.contains('z-line') || text.contains('zline') || text.contains('akill');
  }

  void _emitError(String error) {
    FlutterForegroundTask.sendDataToMain(<String, dynamic>{
      'type': 'error',
      'error': error,
    });
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  Future<void> _closeSocket() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final socket = _socket;
    _socket = null;
    try {
      await socket?.close();
    } catch (_) {}
  }
}
