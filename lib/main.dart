import 'dart:async';
import 'package:flutter/material.dart';
import 'irc_client.dart';

void main() => runApp(const JersIrcApp());

class JersIrcApp extends StatelessWidget {
  const JersIrcApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JersIRC', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorSchemeSeed: Colors.indigo, scaffoldBackgroundColor: const Color(0xFF0D1117)),
    home: const IrcHomePage(),
  );
}

class ChannelState {
  final String name;
  final List<IrcMessage> messages = [];
  final Set<String> users = {};
  ChannelState(this.name);
}

class IrcHomePage extends StatefulWidget {
  const IrcHomePage({super.key});
  @override State<IrcHomePage> createState() => _IrcHomePageState();
}

class _IrcHomePageState extends State<IrcHomePage> {
  final client = IrcClient();
  final host = TextEditingController(text: 'irc.libera.chat');
  final port = TextEditingController(text: '6697');
  final nick = TextEditingController(text: 'JersIRC_User');
  final channelInput = TextEditingController(text: '#libera');
  final messageInput = TextEditingController();
  final channels = <String, ChannelState>{};
  StreamSubscription<IrcMessage>? subscription;
  String? activeChannel;
  bool connecting = false;
  bool connected = false;
  String status = 'Desconectado';

  ChannelState get active => channels[activeChannel] ?? ChannelState(activeChannel ?? 'Console');

  @override void initState() { super.initState(); subscription = client.messages.listen(handleMessage); }

  void handleMessage(IrcMessage m) {
    if (!mounted) return;
    setState(() {
      if (m.command == 'DISCONNECTED') { connected = false; status = 'Desconectado'; return; }
      if (m.command == 'ERROR') { status = 'Error'; return; }
      if (m.command == 'JOIN' && m.params.isNotEmpty) {
        final c = m.params.last;
        final state = channels.putIfAbsent(c, () => ChannelState(c));
        if (m.nick != null) state.users.add(m.nick!);
        activeChannel ??= c;
      }
      if (m.command == 'PART' && m.params.isNotEmpty && m.nick != null) channels[m.params.last]?.users.remove(m.nick);
      if ((m.command == 'PRIVMSG' || m.command == 'NOTICE') && m.params.isNotEmpty) {
        final target = m.params.first.startsWith('#') ? m.params.first : (m.nick ?? 'Private');
        final state = channels.putIfAbsent(target, () => ChannelState(target));
        state.messages.add(m);
        activeChannel ??= target;
      }
      if (m.command == '353' && m.params.length >= 3) {
        final state = channels.putIfAbsent(m.params[2], () => ChannelState(m.params[2]));
        state.users.addAll(m.trailing.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).map((x) => x.replaceFirst(RegExp(r'^[~&@%+]+'), '')));
      }
    });
  }

  Future<void> connect() async {
    setState(() { connecting = true; status = 'Conectando...'; });
    try {
      await client.connect(host: host.text.trim(), port: int.tryParse(port.text) ?? 6697, nickname: nick.text.trim(), secure: true);
      if (mounted) setState(() { connected = true; status = 'Conectado'; });
    } catch (_) { if (mounted) setState(() => status = 'Error de conexión'); }
    if (mounted) setState(() => connecting = false);
  }

  Future<void> disconnect() async { await client.disconnect(); if (mounted) setState(() { connected = false; status = 'Desconectado'; }); }
  void join() { final c = channelInput.text.trim(); if (c.isEmpty || !connected) return; channels.putIfAbsent(c, () => ChannelState(c)); activeChannel = c; client.join(c); setState(() {}); }
  void sendMessage() {
    final text = messageInput.text.trim(); final c = activeChannel;
    if (text.isEmpty || c == null || !connected) return;
    if (text.startsWith('/')) { handleCommand(text); } else { client.message(c, text); channels[c]!.messages.add(IrcMessage(':${nick.text}!local@local', nick.text, 'PRIVMSG', [c, text])); setState(() {}); }
    messageInput.clear();
  }
  void handleCommand(String text) {
    final p = text.substring(1).split(' '); final cmd = p.first.toLowerCase();
    if (cmd == 'join' && p.length > 1) { channelInput.text = p[1]; join(); }
    else if (cmd == 'part' && activeChannel != null) client.part(activeChannel!);
    else if (cmd == 'nick' && p.length > 1) { client.changeNick(p[1]); nick.text = p[1]; }
    else if (cmd == 'msg' && p.length > 2) client.message(p[1], p.sublist(2).join(' '));
    else client.send(text.substring(1));
  }

  @override void dispose() { subscription?.cancel(); client.dispose(); for (final c in [host,port,nick,channelInput,messageInput]) c.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('JersIRC'), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: Chip(avatar: Icon(Icons.circle, size: 10, color: connected ? Colors.green : Colors.grey), label: Text(status))))]),
    drawer: Drawer(child: SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [const ListTile(title: Text('CONEXIÓN', style: TextStyle(fontWeight: FontWeight.bold))),
      TextField(controller: host, decoration: const InputDecoration(labelText: 'Servidor')), const SizedBox(height: 8),
      Row(children: [Expanded(child: TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puerto'))), const SizedBox(width: 8), Expanded(child: TextField(controller: nick, decoration: const InputDecoration(labelText: 'Nickname')))]),
      const SizedBox(height: 12), FilledButton.icon(onPressed: connecting ? null : (connected ? disconnect : connect), icon: Icon(connected ? Icons.link_off : Icons.link), label: Text(connected ? 'Desconectar' : 'Conectar TLS')),
      const Divider(height: 28), const ListTile(title: Text('CANALES', style: TextStyle(fontWeight: FontWeight.bold))),
      ...channels.keys.map((c) => ListTile(leading: const Icon(Icons.tag), title: Text(c), selected: c == activeChannel, onTap: () { setState(() => activeChannel = c); Navigator.pop(context); })),
    ]))),
    body: Column(children: [
      SizedBox(height: 54, child: Row(children: [Expanded(child: ListView(scrollDirection: Axis.horizontal, children: [for (final c in channels.values) Padding(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7), child: ChoiceChip(label: Text(c.name), selected: c.name == activeChannel, onSelected: (_) => setState(() => activeChannel = c.name)))])),
        SizedBox(width: 150, child: Padding(padding: const EdgeInsets.all(6), child: TextField(controller: channelInput, onSubmitted: (_) => join(), decoration: const InputDecoration(prefixIcon: Icon(Icons.tag), hintText: 'Canal')))),
        IconButton(onPressed: connected ? join : null, icon: const Icon(Icons.add_circle)),
      ])),
      Expanded(child: Row(children: [Expanded(child: activeChannel == null ? _welcome() : _chat()), if (activeChannel != null) _usersPanel()])),
      _composer(),
    ]),
  );

  Widget _welcome() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.forum_outlined, size: 64), const SizedBox(height: 12), const Text('Bienvenido a JersIRC', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 6), const Text('Conecta un servidor y entra a un canal con /join #canal') ]));

  Widget _chat() { final msgs = active.messages; return ListView.builder(reverse: false, padding: const EdgeInsets.all(12), itemCount: msgs.length, itemBuilder: (_, i) { final m = msgs[i]; final isMe = m.nick == nick.text; return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: RichText(text: TextSpan(children: [TextSpan(text: '${m.nick ?? 'Sistema'}: ', style: TextStyle(fontWeight: FontWeight.bold, color: isMe ? Colors.indigoAccent : Colors.white70)), TextSpan(text: m.trailing, style: const TextStyle(color: Colors.white))]))); }); }

  Widget _usersPanel() => Container(width: 125, decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.white12))), child: ListView(padding: const EdgeInsets.all(8), children: [const Text('USUARIOS', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8), ...active.users.toList()..sort().map((u) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $u')))]));

  Widget _composer() => SafeArea(child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [Expanded(child: TextField(controller: messageInput, enabled: connected && activeChannel != null, onSubmitted: (_) => sendMessage(), decoration: const InputDecoration(hintText: 'Mensaje o /comando', border: OutlineInputBorder()))), const SizedBox(width: 8), IconButton.filled(onPressed: connected && activeChannel != null ? sendMessage : null, icon: const Icon(Icons.send))])));
}
