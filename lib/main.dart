import 'package:flutter/material.dart';
import 'irc_client.dart';

void main() => runApp(const JersIrcApp());

class JersIrcApp extends StatelessWidget {
  const JersIrcApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'JersIRC',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          scaffoldBackgroundColor: const Color(0xFF0D1117),
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _client = IrcClient();
  final _host = TextEditingController(text: 'irc.libera.chat');
  final _port = TextEditingController(text: '6697');
  final _nick = TextEditingController(text: 'JersIRC_User');
  final _channel = TextEditingController(text: '#libera');
  final _message = TextEditingController();
  final _messages = <String>[];
  StreamSubscription<IrcMessage>? _sub;
  bool _connecting = false;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _sub = _client.messages.listen(_onIrcMessage);
  }

  void _onIrcMessage(IrcMessage m) {
    if (!mounted) return;
    setState(() {
      if (m.command == 'DISCONNECTED') {
        _connected = false;
        _messages.add('[desconectado]');
      } else if (m.command == 'ERROR') {
        _messages.add('[error] ${m.trailing}');
      } else {
        _messages.add(m.raw);
      }
    });
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      await _client.connect(
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 6697,
        nickname: _nick.text.trim(),
        secure: true,
      );
      if (mounted) setState(() => _connected = true);
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add('[error de conexión] $e'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo conectar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    await _client.disconnect();
    if (mounted) setState(() => _connected = false);
  }

  void _join() {
    final channel = _channel.text.trim();
    if (channel.isNotEmpty) _client.join(channel);
  }

  void _sendMessage() {
    final text = _message.text.trim();
    final channel = _channel.text.trim();
    if (text.isEmpty || channel.isEmpty) return;
    _client.message(channel, text);
    _message.clear();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _client.dispose();
    _host.dispose();
    _port.dispose();
    _nick.dispose();
    _channel.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JersIRC'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                avatar: Icon(Icons.circle, size: 10, color: _connected ? Colors.green : Colors.grey),
                label: Text(_connected ? 'Conectado' : 'Desconectado'),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(child: TextField(controller: _host, decoration: const InputDecoration(labelText: 'Servidor'))),
                      const SizedBox(width: 8),
                      SizedBox(width: 80, child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puerto'))),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(controller: _nick, decoration: const InputDecoration(labelText: 'Nickname'))),
                      const SizedBox(width: 8),
                      SizedBox(width: 130, child: TextField(controller: _channel, decoration: const InputDecoration(labelText: 'Canal'))),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: FilledButton.icon(onPressed: _connecting ? null : (_connected ? _disconnect : _connect), icon: Icon(_connected ? Icons.link_off : Icons.link), label: Text(_connecting ? 'Conectando...' : (_connected ? 'Desconectar' : 'Conectar TLS')))),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(onPressed: _connected ? _join : null, icon: const Icon(Icons.tag), label: const Text('JOIN')),
                    ]),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: const Color(0xFF090D12), borderRadius: BorderRadius.circular(12)),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: SelectableText(_messages[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: TextField(controller: _message, enabled: _connected, onSubmitted: (_) => _sendMessage(), decoration: const InputDecoration(hintText: 'Escribe un mensaje...', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _connected ? _sendMessage : null, icon: const Icon(Icons.send)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
