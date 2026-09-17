import 'package:flutter/material.dart';
import '../controllers/irc_controller.dart';
import '../models/chat_room.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final controller = IrcController();
  final host = TextEditingController(text: 'irc.chateamos.org');
  final port = TextEditingController(text: '6667');
  final nick = TextEditingController(text: 'JersIRC_User');
  final channel = TextEditingController(text: '#panama');
  final message = TextEditingController();
  final scroll = ScrollController();
  bool secure = false;
  bool usersVisible = true;

  ChatRoomModel? get room => controller.currentRoom;
  @override void initState() { super.initState(); controller.addListener(_refresh); }
  void _refresh() { if (mounted) setState(() {}); }

  Future<void> _connect() async {
    await controller.connect(host: host.text, port: int.tryParse(port.text) ?? (secure ? 6697 : 6667), nickname: nick.text, secure: secure);
    if (controller.connected && channel.text.trim().isNotEmpty) controller.join(channel.text);
  }

  void _send() {
    final text = message.text.trim(); if (text.isEmpty) return;
    if (text.startsWith('/')) {
      final p = text.substring(1).split(RegExp(r'\s+')); final cmd = p.first.toLowerCase();
      if (cmd == 'join' && p.length > 1) controller.join(p[1]);
      else if (cmd == 'part' && room != null) controller.closeRoom(room!.name);
      else if (cmd == 'nick' && p.length > 1) controller.client.changeNick(p[1]);
      else if (cmd == 'msg' && p.length > 2) { controller.openPrivate(p[1]); controller.client.message(p[1], p.sublist(2).join(' ')); }
      else controller.client.send(text.substring(1));
    } else controller.sendMessage(text);
    message.clear(); _scrollBottom();
  }

  void _scrollBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 180), curve: Curves.easeOut); }); }
  @override void dispose() { controller.removeListener(_refresh); controller.dispose(); host.dispose(); port.dispose(); nick.dispose(); channel.dispose(); message.dispose(); scroll.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: const Color(0xFF151B22), title: const Row(children: [Icon(Icons.forum_rounded, size: 22), SizedBox(width: 8), Text('JersIRC', style: TextStyle(fontWeight: FontWeight.w700))]), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Row(children: [Icon(Icons.circle, size: 9, color: controller.connected ? const Color(0xFF8FB59B) : Colors.grey), const SizedBox(width: 6), SizedBox(width: 150, child: Text(controller.status, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))]))]),
    drawer: _drawer(),
    body: Column(children: [if (controller.rooms.isNotEmpty) _tabs(), Expanded(child: Row(children: [Expanded(child: room == null ? _welcome() : _chat(room!)), if (room != null && !room!.privateChat && usersVisible) _users(room!)])), if (room != null) _composer()]),
  );

  Widget _drawer() => Drawer(backgroundColor: const Color(0xFF151B22), child: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
    const Center(child: Text('JersIRC', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))), const Center(child: Text('IRC, simple y claro', style: TextStyle(color: Colors.white54))), const SizedBox(height: 22),
    const Text('CONEXIÓN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)), const SizedBox(height: 10),
    TextField(controller: host, decoration: const InputDecoration(labelText: 'Servidor')), const SizedBox(height: 8),
    Row(children: [Expanded(child: TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puerto'))), const SizedBox(width: 8), Expanded(child: TextField(controller: nick, decoration: const InputDecoration(labelText: 'Nickname')))]),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('TLS / SSL'), value: secure, onChanged: controller.connecting ? null : (v) => setState(() => secure = v)),
    FilledButton.icon(onPressed: controller.connecting ? null : (controller.connected ? controller.disconnect : _connect), icon: Icon(controller.connected ? Icons.link_off : Icons.link), label: Text(controller.connected ? 'Desconectar' : 'Conectar')),
    const Divider(height: 28, color: Colors.white12), const Text('UNIRSE A CANAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)), const SizedBox(height: 8),
    Row(children: [Expanded(child: TextField(controller: channel, decoration: const InputDecoration(hintText: '#panama'))), const SizedBox(width: 8), IconButton.filled(onPressed: controller.connected ? () => controller.join(channel.text) : null, icon: const Icon(Icons.add))])
  ])));

  Widget _welcome() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.forum_outlined, size: 62, color: Colors.white.withOpacity(.4)), const SizedBox(height: 14), const Text('Bienvenido a JersIRC', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 8), const Text('Conecta a un servidor IRC para comenzar', style: TextStyle(color: Colors.white54))]));

  Widget _tabs() => SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), children: controller.rooms.values.map((r) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Material(color: r.name == controller.activeRoom ? const Color(0xFF53677D) : const Color(0xFF252D36), borderRadius: BorderRadius.circular(18), child: InkWell(onTap: () { controller.activeRoom = r.name; r.unread = 0; setState(() {}); _scrollBottom(); }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(r.privateChat ? Icons.person_outline : Icons.forum_outlined, size: 14), const SizedBox(width: 5), Text(r.name, style: const TextStyle(fontSize: 12)), if (r.unread > 0) Padding(padding: const EdgeInsets.only(left: 5), child: Text('${r.unread}'))])))))).toList()));

  Widget _chat(ChatRoomModel r) => Column(children: [if (!controller.connected) Container(width: double.infinity, padding: const EdgeInsets.all(6), color: Colors.orange.withOpacity(.12), child: Text(controller.status, style: const TextStyle(fontSize: 12))), Expanded(child: r.messages.isEmpty ? Center(child: Text(r.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))) : ListView.builder(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), itemCount: r.messages.length, itemBuilder: (_, i) { final m = r.messages[i]; final user = m.nick ?? 'Sistema'; return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: RichText(text: TextSpan(children: [TextSpan(text: '$user: ', style: TextStyle(fontWeight: FontWeight.bold, color: _nickColor(user))), TextSpan(text: _clean(m.trailing), style: const TextStyle(color: Colors.white))]))); }))]);

  Widget _users(ChatRoomModel r) => Container(width: 148, decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(left: BorderSide(color: Colors.white10))), child: ListView(padding: const EdgeInsets.all(6), children: [Row(children: [const Expanded(child: Text('USUARIOS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54))), IconButton(onPressed: () => setState(() => usersVisible = false), icon: const Icon(Icons.keyboard_double_arrow_right, size: 17))]), ...r.users.values.map((u) => ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 2), leading: Text(u.prefixes.isEmpty ? '•' : u.prefixes), title: Text(u.nick, overflow: TextOverflow.ellipsis, style: TextStyle(color: _nickColor(u.nick), fontWeight: FontWeight.w600)), onTap: () => controller.openPrivate(u.nick)))]));

  Widget _composer() => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 10), child: Row(children: [Expanded(child: TextField(controller: message, enabled: controller.connected, onSubmitted: (_) => _send(), maxLines: 4, minLines: 1, decoration: const InputDecoration(hintText: 'Escribe un mensaje o /comando'))), const SizedBox(width: 8), IconButton.filled(onPressed: controller.connected ? _send : null, icon: const Icon(Icons.send_rounded))])));
  String _clean(String s) => s.replaceAll(RegExp(r'\u0003(?:\d{1,2}(?:,\d{1,2})?)?'), '').replaceAll(RegExp(r'[\u0002\u000F\u0016\u001D\u001F]'), '');
  Color _nickColor(String user) { var h = 0; for (final c in user.codeUnits) h = (h * 31 + c) & 0x7fffffff; const c = [Color(0xFF7CB8FF), Color(0xFFFFA6C9), Color(0xFFB9E986), Color(0xFFFFCC80), Color(0xFFC7A7FF), Color(0xFF72E0D1), Color(0xFFFF9E80), Color(0xFF9FA8DA)]; return c[h % c.length]; }
}
