import 'dart:async';
import 'package:flutter/material.dart';
import 'irc_client.dart';

void main() => runApp(const JersIrcApp());

class JersIrcApp extends StatelessWidget {
  const JersIrcApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JersIRC', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark, useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF91A7C4), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF11161C), cardColor: const Color(0xFF1A2129),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xFF171D24), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
    ), home: const IrcHomePage(),
  );
}

class ChannelState { final String name; final List<IrcMessage> messages = []; final Set<String> users = {}; ChannelState(this.name); }
class IrcHomePage extends StatefulWidget { const IrcHomePage({super.key}); @override State<IrcHomePage> createState() => _IrcHomePageState(); }

class _IrcHomePageState extends State<IrcHomePage> {
  final client = IrcClient();
  final host = TextEditingController(text: 'irc.libera.chat');
  final port = TextEditingController(text: '6697');
  final nick = TextEditingController(text: 'JersIRC_User');
  final channelInput = TextEditingController(text: '#libera');
  final messageInput = TextEditingController();
  final channels = <String, ChannelState>{};
  StreamSubscription<IrcMessage>? subscription;
  String? activeChannel; bool connecting = false; bool connected = false; String status = 'Desconectado';
  ChannelState get active => channels[activeChannel] ?? ChannelState(activeChannel ?? 'JersIRC');

  @override void initState() { super.initState(); subscription = client.messages.listen(handleMessage); }
  void handleMessage(IrcMessage m) {
    if (!mounted) return;
    setState(() {
      if (m.command == 'DISCONNECTED') { connected = false; status = 'Desconectado'; return; }
      if (m.command == 'ERROR') { status = 'Error'; return; }
      if (m.command == 'JOIN' && m.params.isNotEmpty) { final c = m.params.last; final state = channels.putIfAbsent(c, () => ChannelState(c)); if (m.nick != null) state.users.add(m.nick!); activeChannel ??= c; }
      if (m.command == 'PART' && m.params.isNotEmpty && m.nick != null) channels[m.params.last]?.users.remove(m.nick);
      if ((m.command == 'PRIVMSG' || m.command == 'NOTICE') && m.params.isNotEmpty) { final target = m.params.first.startsWith('#') ? m.params.first : (m.nick ?? 'Privado'); final state = channels.putIfAbsent(target, () => ChannelState(target)); state.messages.add(m); activeChannel ??= target; }
      if (m.command == '353' && m.params.length >= 3) { final state = channels.putIfAbsent(m.params[2], () => ChannelState(m.params[2])); state.users.addAll(m.trailing.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).map((x) => x.replaceFirst(RegExp(r'^[~&@%+]+'), ''))); }
    });
  }
  Future<void> connect() async { setState(() { connecting = true; status = 'Conectando...'; }); try { await client.connect(host: host.text.trim(), port: int.tryParse(port.text) ?? 6697, nickname: nick.text.trim(), secure: true); if (mounted) setState(() { connected = true; status = 'Conectado'; }); } catch (_) { if (mounted) setState(() => status = 'Error de conexión'); } if (mounted) setState(() => connecting = false); }
  Future<void> disconnect() async { await client.disconnect(); if (mounted) setState(() { connected = false; status = 'Desconectado'; }); }
  void join() { final c = channelInput.text.trim(); if (c.isEmpty || !connected) return; channels.putIfAbsent(c, () => ChannelState(c)); activeChannel = c; client.join(c); setState(() {}); }
  void sendMessage() { final text = messageInput.text.trim(); final c = activeChannel; if (text.isEmpty || c == null || !connected) return; if (text.startsWith('/')) handleCommand(text); else { client.message(c, text); channels[c]!.messages.add(IrcMessage(':${nick.text}!local@local', nick.text, 'PRIVMSG', [c, text])); setState(() {}); } messageInput.clear(); }
  void handleCommand(String text) { final p = text.substring(1).split(' '); final cmd = p.first.toLowerCase(); if (cmd == 'join' && p.length > 1) { channelInput.text = p[1]; join(); } else if (cmd == 'part' && activeChannel != null) client.part(activeChannel!); else if (cmd == 'nick' && p.length > 1) { client.changeNick(p[1]); nick.text = p[1]; } else if (cmd == 'msg' && p.length > 2) client.message(p[1], p.sublist(2).join(' ')); else client.send(text.substring(1)); }
  @override void dispose() { subscription?.cancel(); client.dispose(); for (final c in [host,port,nick,channelInput,messageInput]) c.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: const Color(0xFF151B22), leading: Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu_rounded), onPressed: () => Scaffold.of(context).openDrawer())), title: Row(children: [const Icon(Icons.forum_rounded, size: 22), const SizedBox(width: 8), const Text('JersIRC', style: TextStyle(fontWeight: FontWeight.w700)), if (activeChannel != null) ...[const SizedBox(width: 12), Text(activeChannel!, style: const TextStyle(fontSize: 15, color: Colors.white60))]]), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: Row(children: [Icon(Icons.circle, size: 9, color: connected ? const Color(0xFF8FB59B) : const Color(0xFF777F89)), const SizedBox(width: 6), Text(status, style: const TextStyle(fontSize: 12, color: Colors.white60))])))],
    drawer: _drawer(context),
    body: Column(children: [
      if (channels.isNotEmpty) SizedBox(height: 54, child: Row(children: [Expanded(child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [for (final c in channels.values) Padding(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7), child: ChoiceChip(label: Text(c.name), selected: c.name == activeChannel, onSelected: (_) => setState(() => activeChannel = c.name)))])), SizedBox(width: 145, child: Padding(padding: const EdgeInsets.all(6), child: TextField(controller: channelInput, onSubmitted: (_) => join(), decoration: const InputDecoration(prefixIcon: Icon(Icons.tag, size: 18), hintText: 'Canal', contentPadding: EdgeInsets.symmetric(horizontal: 8))))), IconButton(onPressed: connected ? join : null, icon: const Icon(Icons.add_circle_outline))])),
      Expanded(child: Row(children: [Expanded(child: activeChannel == null ? _welcome() : _chat()), if (activeChannel != null) _usersPanel()])), _composer(),
    ]),
  );

  Widget _drawer(BuildContext context) => Drawer(backgroundColor: const Color(0xFF151B22), child: SafeArea(child: ListView(padding: const EdgeInsets.all(14), children: [const SizedBox(height: 8), const Center(child: Text('JersIRC', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1))), const Center(child: Text('IRC, simple y claro', style: TextStyle(color: Colors.white54))), const SizedBox(height: 24), const Text('CONEXIÓN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)), const SizedBox(height: 8), TextField(controller: host, decoration: const InputDecoration(labelText: 'Servidor')), const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puerto'))), const SizedBox(width: 8), Expanded(child: TextField(controller: nick, decoration: const InputDecoration(labelText: 'Nickname')))]), const SizedBox(height: 12), FilledButton.icon(onPressed: connecting ? null : (connected ? disconnect : connect), icon: Icon(connected ? Icons.link_off : Icons.link), label: Text(connected ? 'Desconectar' : 'Conectar con TLS')), const SizedBox(height: 22), const Text('CANALES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)), const SizedBox(height: 6), ...channels.keys.map((c) => ListTile(dense: true, leading: const Icon(Icons.tag, size: 20), title: Text(c), selected: c == activeChannel, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), onTap: () { setState(() => activeChannel = c); Navigator.pop(context); })), const SizedBox(height: 28), Center(child: Text('JersIRC', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(.12), fontWeight: FontWeight.bold, letterSpacing: 3))), ])));

  Widget _welcome() => Stack(children: [Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.forum_outlined, size: 62, color: Colors.white.withOpacity(.45)), const SizedBox(height: 14), const Text('Bienvenido a JersIRC', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 8), const Text('Conecta un servidor para comenzar', style: TextStyle(color: Colors.white54)), const SizedBox(height: 18), Builder(builder: (context) => OutlinedButton.icon(onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.settings_outlined), label: const Text('Configurar conexión')))])), Center(child: IgnorePointer(child: Text('JersIRC', style: TextStyle(fontSize: 74, fontWeight: FontWeight.w900, color: Colors.white.withOpacity(.025), letterSpacing: 8))))]);

  Widget _chat() { final msgs = active.messages; if (msgs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.tag, size: 42, color: Colors.white.withOpacity(.3)), const SizedBox(height: 10), Text(active.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const Text('No hay mensajes todavía', style: TextStyle(color: Colors.white54))])); return ListView.builder(padding: const EdgeInsets.fromLTRB(16, 12, 16, 18), itemCount: msgs.length, itemBuilder: (_, i) { final m = msgs[i]; final isMe = m.nick == nick.text; return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: RichText(text: TextSpan(children: [TextSpan(text: '${m.nick ?? 'Sistema'}  ', style: TextStyle(fontWeight: FontWeight.bold, color: isMe ? const Color(0xFFA9BBD2) : const Color(0xFF9CA7B3))), TextSpan(text: m.trailing, style: const TextStyle(color: Colors.white, height: 1.35))]))); }); }
  Widget _usersPanel() { final users = active.users.toList()..sort(); return Container(width: 132, decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(left: BorderSide(color: Colors.white10))), child: ListView(padding: const EdgeInsets.all(10), children: [const Text('USUARIOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54)), const SizedBox(height: 10), for (final u in users) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [const Icon(Icons.person_outline, size: 15, color: Colors.white38), const SizedBox(width: 6), Expanded(child: Text(u, overflow: TextOverflow.ellipsis))]))])); }
  Widget _composer() => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 10), child: Row(children: [Expanded(child: TextField(controller: messageInput, enabled: connected && activeChannel != null, onSubmitted: (_) => sendMessage(), decoration: InputDecoration(hintText: connected ? 'Escribe un mensaje o /comando' : 'Conecta un servidor para chatear', prefixIcon: const Icon(Icons.chat_bubble_outline, size: 19), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18))))), const SizedBox(width: 8), IconButton.filled(onPressed: connected && activeChannel != null ? sendMessage : null, icon: const Icon(Icons.send_rounded))])));
}
