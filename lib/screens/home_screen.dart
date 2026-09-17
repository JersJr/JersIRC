import 'package:flutter/material.dart';
import '../controllers/irc_controller.dart';
import '../models/chat_room.dart';
import '../models.dart';
import '../storage.dart';
import '../widgets/user_action_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final controller = IrcController();
  final storage = JersStorage();
  final host = TextEditingController(text: 'irc.chateamos.org');
  final port = TextEditingController(text: '6667');
  final nick = TextEditingController(text: 'JersIRC_User');
  final channel = TextEditingController(text: '#panama');
  final message = TextEditingController();
  final scroll = ScrollController();
  bool secure = false, usersVisible = true;
  List<SavedServer> savedServers = [];
  String? selectedProfile;
  ChatRoomModel? get room => controller.currentRoom;

  @override void initState() { super.initState(); controller.addListener(_refresh); _loadServers(); }
  void _refresh() { if (mounted) setState(() {}); }

  Future<void> _loadServers() async {
    final list = await storage.loadServers();
    if (!mounted) return;
    setState(() => savedServers = list);
    await _loadLastServer();
  }

  Future<void> _loadLastServer() async {
    final name = await storage.getLastServer(); if (name == null) return;
    final list = savedServers.isNotEmpty ? savedServers : await storage.loadServers();
    SavedServer? saved;
    for (final s in list) { if (s.name == name) { saved = s; break; } }
    if (saved == null || !mounted) return;
    _applyProfile(saved);
  }

  void _applyProfile(SavedServer saved) {
    host.text = saved.host; port.text = '${saved.port}'; nick.text = saved.nickname;
    secure = saved.tls; selectedProfile = saved.name;
    if (saved.channels.isNotEmpty) channel.text = saved.channels.first;
    setState(() {});
  }

  Future<void> _saveProfile({SavedServer? existing}) async {
    final defaultName = existing?.name ?? host.text.trim();
    final nameController = TextEditingController(text: defaultName.isEmpty ? 'Mi servidor' : defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Guardar perfil' : 'Editar perfil'),
        content: TextField(controller: nameController, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre del perfil')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: () { final v = nameController.text.trim(); if (v.isNotEmpty) Navigator.pop(context, v); }, child: const Text('Guardar'))],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty) return;
    final p = int.tryParse(port.text.trim()) ?? (secure ? 6697 : 6667);
    final ch = channel.text.trim();
    final profile = SavedServer(name: name, host: host.text.trim(), port: p, nickname: nick.text.trim(), tls: secure, channels: ch.isEmpty ? const [] : [ch]);
    await storage.upsertServer(profile);
    await storage.setLastServer(name);
    final list = await storage.loadServers();
    if (!mounted) return;
    setState(() { savedServers = list; selectedProfile = name; });
  }

  Future<void> _deleteProfile(SavedServer profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(title: const Text('Eliminar perfil'), content: Text('¿Eliminar "${profile.name}"?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar'))]),
    );
    if (ok != true) return;
    await storage.deleteServer(profile.name);
    if (await storage.getLastServer() == profile.name) await storage.clearLastServer();
    final list = await storage.loadServers();
    if (!mounted) return;
    setState(() { savedServers = list; if (selectedProfile == profile.name) selectedProfile = null; });
  }

  Future<void> _connect() async {
    final p = int.tryParse(port.text) ?? (secure ? 6697 : 6667);
    final h = host.text.trim(), n = nick.text.trim(), ch = channel.text.trim();
    await controller.connect(host: h, port: p, nickname: n, secure: secure);
    if (!controller.connected) return;
    final profileName = selectedProfile?.trim().isNotEmpty == true ? selectedProfile! : h;
    await storage.upsertServer(SavedServer(name: profileName, host: h, port: p, nickname: n, tls: secure, channels: ch.isEmpty ? const [] : [ch]));
    await storage.setLastServer(profileName);
    final list = await storage.loadServers();
    if (mounted) setState(() => savedServers = list);
    if (ch.isNotEmpty) controller.join(ch);
  }

  void _send() {
    final text = message.text.trim(); if (text.isEmpty || !controller.connected) return;
    if (text.startsWith('/')) _command(text.substring(1)); else controller.sendMessage(text);
    message.clear(); _scrollBottom();
  }

  void _command(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+')); if (parts.isEmpty) return;
    final cmd = parts.first.toLowerCase(); final args = parts.skip(1).toList();
    switch (cmd) {
      case 'join': if (args.isNotEmpty) controller.join(args.first); break;
      case 'part': controller.closeRoom(room?.name ?? ''); break;
      case 'nick': if (args.isNotEmpty) controller.changeNick(args.first); break;
      case 'msg': if (args.length >= 2) { final target = args.first; final text = args.skip(1).join(' '); controller.openPrivate(target); controller.sendPrivate(target, text); } break;
      case 'notice': if (args.length >= 2) controller.sendNotice(args.first, args.skip(1).join(' ')); break;
      case 'me': if (room != null && args.isNotEmpty) controller.sendAction(room!.name, args.join(' ')); break;
      case 'query': if (args.isNotEmpty) controller.openPrivate(args.first); break;
      case 'whois': if (args.isNotEmpty) controller.client.send('WHOIS ${args.first}'); break;
      case 'ignore': if (args.isNotEmpty) controller.toggleIgnore(args.first); break;
      case 'raw': if (args.isNotEmpty) controller.client.send(args.join(' ')); break;
      default: controller.client.send(raw);
    }
  }

  void _showUserActions(String nickname) {
    final ignored = controller.ignoredUsers.contains(nickname.toLowerCase());
    showModalBottomSheet<void>(context: context, backgroundColor: const Color(0xFF202832), showDragHandle: true, builder: (_) => UserActionSheet(nickname: nickname, isIgnored: ignored, onPrivate: () => controller.openPrivate(nickname), onWhois: () => controller.client.send('WHOIS $nickname'), onIgnore: () => controller.toggleIgnore(nickname), onMode: (mode) { final target = room?.name; if (target != null && target.startsWith('#')) controller.client.send('MODE $target $mode $nickname'); }));
  }

  void _scrollBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 180), curve: Curves.easeOut); }); }
  @override void dispose() { controller.removeListener(_refresh); controller.dispose(); for (final c in [host, port, nick, channel, message, scroll]) c.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: const Color(0xFF151B22), title: const Row(children: [Icon(Icons.forum_rounded, size: 22), SizedBox(width: 8), Text('JersIRC', style: TextStyle(fontWeight: FontWeight.w700))]), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Row(children: [Icon(Icons.circle, size: 9, color: controller.connected ? const Color(0xFF8FB59B) : Colors.grey), const SizedBox(width: 6), SizedBox(width: 150, child: Text(controller.status, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))) ]))]),
    drawer: _drawer(), body: Column(children: [if (controller.rooms.isNotEmpty) _tabs(), Expanded(child: Row(children: [Expanded(child: room == null ? _welcome() : _chat(room!)), if (room != null && !room!.privateChat && usersVisible) _users(room!)])), if (room != null) _composer()]),
  );

  Widget _drawer() => Drawer(backgroundColor: const Color(0xFF151B22), child: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [const Center(child: Text('JersIRC', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))), const Center(child: Text('IRC, simple y claro', style: TextStyle(color: Colors.white54))), const SizedBox(height: 22), const Text('CONEXIÓN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)), const SizedBox(height: 10), TextField(controller: host, decoration: const InputDecoration(labelText: 'Servidor')), const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puerto'))), const SizedBox(width: 8), Expanded(child: TextField(controller: nick, decoration: const InputDecoration(labelText: 'Nickname')))]), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('TLS / SSL'), value: secure, onChanged: controller.connecting ? null : (v) => setState(() => secure = v)), FilledButton.icon(onPressed: controller.connecting ? null : (controller.connected ? controller.disconnect : _connect), icon: Icon(controller.connected ? Icons.link_off : Icons.link), label: Text(controller.connected ? 'Desconectar' : 'Conectar')), const Divider(height: 28, color: Colors.white12), const Text('PERFILES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)), const SizedBox(height: 8), FilledButton.tonalIcon(onPressed: () => _saveProfile(), icon: const Icon(Icons.save_outlined), label: const Text('Guardar perfil')), if (savedServers.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('No hay perfiles guardados', style: TextStyle(color: Colors.white54))) else ...savedServers.map((s) => ListTile(selected: selectedProfile == s.name, contentPadding: EdgeInsets.zero, leading: Icon(s.tls ? Icons.lock_outline : Icons.public), title: Text(s.name, overflow: TextOverflow.ellipsis), subtitle: Text('${s.host}:${s.port} • ${s.nickname}', overflow: TextOverflow.ellipsis), onTap: () { _applyProfile(s); Navigator.pop(context); }, trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') _saveProfile(existing: s); if (v == 'delete') _deleteProfile(s); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Editar')), PopupMenuItem(value: 'delete', child: Text('Eliminar'))])), const Divider(height: 28, color: Colors.white12), const Text('UNIRSE A CANAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)), const SizedBox(height: 8), Row(children: [Expanded(child: TextField(controller: channel, decoration: const InputDecoration(hintText: '#panama'))), const SizedBox(width: 8), IconButton.filled(onPressed: controller.connected ? () => controller.join(channel.text) : null, icon: const Icon(Icons.add))]) ])));

  Widget _welcome() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.forum_outlined, size: 62, color: Colors.white.withOpacity(.4)), const SizedBox(height: 14), const Text('Bienvenido a JersIRC', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 8), const Text('Conecta a un servidor IRC para comenzar', style: TextStyle(color: Colors.white54))]));
  Widget _tabs() => SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), children: controller.rooms.values.map((r) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Material(color: r.name == controller.activeRoom ? const Color(0xFF53677D) : const Color(0xFF252D36), borderRadius: BorderRadius.circular(18), child: InkWell(onTap: () { controller.activeRoom = r.name; r.unread = 0; setState(() {}); _scrollBottom(); }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(r.privateChat ? Icons.person_outline : Icons.forum_outlined, size: 14), const SizedBox(width: 5), Text(r.name, style: const TextStyle(fontSize: 12)), if (r.unread > 0) Padding(padding: const EdgeInsets.only(left: 5), child: Text('${r.unread}'))])))))).toList()));
  Widget _chat(ChatRoomModel r) => Column(children: [if (!controller.connected) Container(width: double.infinity, padding: const EdgeInsets.all(6), color: Colors.orange.withOpacity(.12), child: Text(controller.status, style: const TextStyle(fontSize: 12))), Expanded(child: r.messages.isEmpty ? Center(child: Text(r.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))) : ListView.builder(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), itemCount: r.messages.length, itemBuilder: (context, i) { final m = r.messages[i], user = m.nick ?? 'Sistema'; return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: RichText(text: TextSpan(children: [TextSpan(text: '$user: ', style: TextStyle(fontWeight: FontWeight.bold, color: _nickColor(user))), TextSpan(text: _clean(m.trailing), style: const TextStyle(color: Colors.white))]))); }))]);
  Widget _users(ChatRoomModel r) => Container(width: 148, decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(left: BorderSide(color: Colors.white10))), child: ListView(padding: const EdgeInsets.all(6), children: [Row(children: [const Expanded(child: Text('USUARIOS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54))), IconButton(onPressed: () => setState(() => usersVisible = false), icon: const Icon(Icons.keyboard_double_arrow_right, size: 17))]), ...r.users.values.map((u) => ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 2), leading: Text(u.prefixes.isEmpty ? '•' : u.prefixes), title: Text(u.nick, overflow: TextOverflow.ellipsis, style: TextStyle(color: _nickColor(u.nick), fontWeight: FontWeight.w600)), onTap: () => _showUserActions(u.nick))) ]));
  Widget _composer() => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 10), child: Row(children: [Expanded(child: TextField(controller: message, enabled: controller.connected, onSubmitted: (_) => _send(), maxLines: 4, minLines: 1, decoration: const InputDecoration(hintText: 'Escribe un mensaje o /comando'))), const SizedBox(width: 8), IconButton.filled(onPressed: controller.connected ? _send : null, icon: const Icon(Icons.send_rounded))])));
  String _clean(String s) => s.replaceAll(RegExp(r'\u0003(?:\d{1,2}(?:,\d{1,2})?)?'), '').replaceAll(RegExp(r'[\u0002\u000F\u0016\u001D\u001F]'), '');
  Color _nickColor(String user) { var h = 0; for (final c in user.codeUnits) h = (h * 31 + c) & 0x7fffffff; const c = [Color(0xFF7CB8FF), Color(0xFFFFA6C9), Color(0xFFB9E986), Color(0xFFFFCC80), Color(0xFFC7A7FF), Color(0xFF72E0D1), Color(0xFFFF9E80), Color(0xFF9FA8DA)]; return c[h % c.length]; }
}
