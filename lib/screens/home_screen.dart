import 'package:flutter/material.dart';
import '../controllers/irc_controller.dart';
import '../models/chat_room.dart';
import '../models.dart';
import '../storage.dart';
import '../widgets/user_action_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final controller = IrcController();
  final storage = JersStorage();
  final host = TextEditingController(text: 'irc.chateamos.org');
  final port = TextEditingController(text: '6667');
  final nick = TextEditingController(text: 'JersIRC_User');
  final channel = TextEditingController(text: '#panama');
  final message = TextEditingController();
  final messageFocus = FocusNode();
  final scroll = ScrollController();
  bool secure = false, usersVisible = true, privateVisible = false, nicknameDialogOpen = false, banDialogOpen = false;
  List<SavedServer> savedServers = [];
  String? selectedProfile;
  ChatRoomModel? get room => controller.currentRoom;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    _loadServers();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    if (!banDialogOpen && controller.banNotice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !banDialogOpen && controller.banNotice != null) _showBanError();
      });
    } else if (!controller.connected && _isBanError(controller.status) && !banDialogOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !controller.connected && !banDialogOpen && _isBanError(controller.status)) _showBanError();
      });
    }
    if (!controller.connected && _isNicknameError(controller.status) && !nicknameDialogOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !controller.connected && !nicknameDialogOpen && _isNicknameError(controller.status)) _showNicknameError();
      });
    }
  }

  Future<void> _loadServers() async {
    final list = await storage.loadServers();
    if (!mounted) return;
    setState(() => savedServers = list);
    await _loadLastServer();
  }

  Future<void> _loadLastServer() async {
    final name = await storage.getLastServer();
    if (name == null) return;
    final list = savedServers.isNotEmpty ? savedServers : await storage.loadServers();
    SavedServer? saved;
    for (final s in list) {
      if (s.name == name) {
        saved = s;
        break;
      }
    }
    if (saved == null || !mounted) return;
    _applyProfile(saved);
  }

  void _applyProfile(SavedServer saved) {
    host.text = saved.host;
    port.text = '${saved.port}';
    nick.text = saved.nickname;
    secure = saved.tls;
    selectedProfile = saved.name;
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = nameController.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('Guardar'),
          ),
        ],
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
      builder: (_) => AlertDialog(
        title: const Text('Eliminar perfil'),
        content: Text('¿Eliminar "${profile.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await storage.deleteServer(profile.name);
    if (await storage.getLastServer() == profile.name) await storage.clearLastServer();
    final list = await storage.loadServers();
    if (!mounted) return;
    setState(() { savedServers = list; if (selectedProfile == profile.name) selectedProfile = null; });
  }

  bool _isNicknameError(String value) {
    final x = value.toLowerCase();
    return x.contains('nickname en uso') ||
        x.contains('nickname en conflicto') ||
        x.contains('nickname/recurso no disponible') ||
        x.contains('nickname no válido') ||
        x.contains('contraseña incorrecta') ||
        x.contains('contraseña incorrecta o requerida');
  }

  bool _isBanError(String value) {
    final x = value.toLowerCase();
    return x.contains('rechazada/bloqueada') || x.contains('baneado') || x.contains('banned');
  }

  Future<void> _showBanError() async {
    if (banDialogOpen || !mounted) return;
    final notice = controller.banNotice?.trim();
    final channelName = controller.banChannel?.trim();
    final isChannel = channelName != null && channelName.isNotEmpty && !controller.banIsServer;
    final title = isChannel ? 'Estás baneado de $channelName' : 'Estás baneado';
    final reason = notice == null || notice.isEmpty ? (isChannel ? 'No puedes entrar a esta sala.' : 'Tu conexión ha sido bloqueada por el servidor.') : notice;
    banDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(reason),
          const SizedBox(height: 14),
          const Text('Si deseas dejar de estar baneado mira este tutorial:'),
          const SizedBox(height: 6),
          const SelectableText('https://youtube.com'),
        ]),
        actions: [FilledButton(onPressed: () { controller.clearBanNotice(); Navigator.pop(context); }, child: const Text('Cerrar'))],
      ),
    );
    banDialogOpen = false;
  }

  Future<void> _showNicknameError() async {
    if (nicknameDialogOpen || !mounted) return;
    nicknameDialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Nickname ocupado o registrado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('El nickname no está disponible. Favor coloque un nuevo nickname.'),
            const SizedBox(height: 14),
            TextField(controller: nick, autofocus: true, decoration: const InputDecoration(labelText: 'Nuevo nickname'), onSubmitted: (_) => Navigator.pop(context, true)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reintentar')),
        ],
      ),
    );
    nicknameDialogOpen = false;
    if (result == true && mounted && nick.text.trim().isNotEmpty) {
      await _connect();
    }
  }

  Future<void> _connect() async {
    final p = int.tryParse(port.text) ?? (secure ? 6697 : 6667);
    final h = host.text.trim();
    final n = nick.text.trim();
    final ch = channel.text.trim();
    await controller.connect(host: h, port: p, nickname: n, secure: secure);
    if (!controller.connected) {
      if (mounted && controller.banNotice != null) { await _showBanError(); return; }
      if (mounted && _isNicknameError(controller.status)) await _showNicknameError();
      return;
    }
    final profileName = selectedProfile?.trim().isNotEmpty == true ? selectedProfile! : h;
    await storage.upsertServer(SavedServer(name: profileName, host: h, port: p, nickname: n, tls: secure, channels: ch.isEmpty ? const [] : [ch]));
    await storage.setLastServer(profileName);
    final list = await storage.loadServers();
    if (mounted) setState(() => savedServers = list);
    if (ch.isNotEmpty) controller.join(ch);
  }

  List<ChatRoomModel> _privateRooms() => controller.rooms.values.where((r) => r.privateChat).toList();
  int _privateUnreadTotal() => _privateRooms().fold(0, (sum, r) => sum + r.unread);

  void _openPrivateRoom(String name) {
    controller.activeRoom = name;
    final r = controller.rooms[name];
    if (r != null) r.unread = 0;
    setState(() {});
    _scrollBottom();
  }

  void _send() {
    final text = message.text.trim();
    if (text.isEmpty || !controller.connected) return;
    if (text.startsWith('/')) _command(text.substring(1)); else controller.sendMessage(text);
    message.clear();
    _scrollBottom();
  }

  void _command(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return;
    final cmd = parts.first.toLowerCase();
    final args = parts.skip(1).toList();
    switch (cmd) {
      case 'join': if (args.isNotEmpty) controller.join(args.first); break;
      case 'part': controller.closeRoom(room?.name ?? ''); break;
      case 'nick': if (args.isNotEmpty) controller.changeNick(args.first); break;
      case 'msg':
        if (args.length >= 2) {
          final target = args.first;
          controller.openPrivate(target);
          controller.sendPrivate(target, args.skip(1).join(' '));
        }
        break;
      case 'notice': if (args.length >= 2) controller.sendNotice(args.first, args.skip(1).join(' ')); break;
      case 'me': if (room != null && args.isNotEmpty) controller.sendAction(room!.name, args.join(' ')); break;
      case 'query': if (args.isNotEmpty) controller.openPrivate(args.first); break;
      case 'whois': if (args.isNotEmpty) controller.client.send('WHOIS ${args.first}'); break;
      case 'ignore': if (args.isNotEmpty) controller.toggleIgnore(args.first); break;
      case 'raw': if (args.isNotEmpty) controller.client.send(args.join(' ')); break;
      default: controller.client.send(raw);
    }
  }

  void _mentionUser(String nickname) {
    final current = message.text.trimLeft();
    message.text = '${current.isEmpty ? '' : '$current '}$nickname ';
    message.selection = TextSelection.collapsed(offset: message.text.length);
    messageFocus.requestFocus();
  }

  void _showUserActions(String nickname) {
    final ignored = controller.ignoredUsers.contains(nickname.toLowerCase());
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF202832),
      showDragHandle: true,
      builder: (_) => UserActionSheet(
        nickname: nickname,
        isIgnored: ignored,
        onPrivate: () => controller.openPrivate(nickname),
        onMention: () => _mentionUser(nickname),
        onWhois: () => controller.client.send('WHOIS $nickname'),
        onIgnore: () => controller.toggleIgnore(nickname),
        onMode: (mode) {
          final target = room?.name;
          if (target != null && target.startsWith('#')) controller.client.send('MODE $target $mode $nickname');
        },
      ),
    );
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  void _closeRoom(String name) => controller.closeRoom(name);

  int _rank(String prefixes) {
    if (prefixes.contains('~')) return 0;
    if (prefixes.contains('&')) return 1;
    if (prefixes.contains('@')) return 2;
    if (prefixes.contains('%')) return 3;
    if (prefixes.contains('+')) return 4;
    return 5;
  }

  List<IrcUserView> _sortedUsers(ChatRoomModel r) {
    final list = r.users.values.map((u) => IrcUserView(u.nick, u.prefixes)).toList();
    list.sort((a, b) {
      final rank = _rank(a.prefixes).compareTo(_rank(b.prefixes));
      if (rank != 0) return rank;
      return a.nick.toLowerCase().compareTo(b.nick.toLowerCase());
    });
    return list;
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    for (final c in [host, port, nick, channel, message, scroll]) c.dispose();
    messageFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF151B22),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_rounded, size: 22),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Privados',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('PRIVADOS', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 3),
                  if (_privateUnreadTotal() > 0)
                    _BlinkingUnread(label: const Text(''), count: _privateUnreadTotal(), color: _nickColor(_privateRooms().first.name)),
                  const Icon(Icons.arrow_drop_down, size: 22),
                ]),
                onSelected: _openPrivateRoom,
                itemBuilder: (_) {
                  final privates = _privateRooms();
                  if (privates.isEmpty) return const [PopupMenuItem<String>(enabled: false, child: Text('No hay privados abiertos'))];
                  return privates.map((r) => PopupMenuItem<String>(
                    value: r.name,
                    child: Row(children: [
                      Icon(Icons.person_outline, size: 17, color: _nickColor(r.name)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.name, overflow: TextOverflow.ellipsis, style: TextStyle(color: _nickColor(r.name)))),
                      if (r.unread > 0) ...[const SizedBox(width: 8), _BlinkingUnread(label: const Text(''), count: r.unread, color: _nickColor(r.name))],
                    ]),
                  )).toList();
                },
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(children: [
                Icon(Icons.circle, size: 9, color: controller.connected ? const Color(0xFF8FB59B) : Colors.grey),
                const SizedBox(width: 6),
                SizedBox(width: 150, child: Text(controller.status, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              ]),
            ),
          ],
        ),
        drawer: _drawer(),
        body: Column(
          children: [
            if (controller.rooms.isNotEmpty) _tabs(),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: room == null ? _welcome() : _chat(room!)),
                  if (room != null && !room!.privateChat) ...[
                    usersVisible ? _users(room!) : _collapsedUsers(room!),
                  ],
                ],
              ),
            ),
            if (room != null) _composer(),
          ],
        ),
      );

  Widget _drawer() => Drawer(
        backgroundColor: const Color(0xFF151B22),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Center(child: Text('JersIRC', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
              const Center(child: Text('IRC, simple y claro', style: TextStyle(color: Colors.white54))),
              const SizedBox(height: 22),
              const Text('CONEXIÓN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
              const SizedBox(height: 10),
              TextField(controller: host, decoration: const InputDecoration(labelText: 'Servidor')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puerto'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: nick, decoration: const InputDecoration(labelText: 'Nickname')),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('TLS / SSL'), value: secure, onChanged: controller.connecting ? null : (v) => setState(() => secure = v)),
              FilledButton.icon(onPressed: controller.connecting ? null : (controller.connected ? controller.disconnect : _connect), icon: Icon(controller.connected ? Icons.link_off : Icons.link), label: Text(controller.connected ? 'Desconectar' : 'Conectar')),
              const Divider(height: 28, color: Colors.white12),
              const Text('PERFILES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(onPressed: () => _saveProfile(), icon: const Icon(Icons.save_outlined), label: const Text('Guardar perfil')),
              if (savedServers.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('No hay perfiles guardados', style: TextStyle(color: Colors.white54)))
              else
                ...savedServers.map((s) => ListTile(
                  selected: selectedProfile == s.name,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(s.tls ? Icons.lock_outline : Icons.public),
                  title: Text(s.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${s.host}:${s.port} • ${s.nickname}', overflow: TextOverflow.ellipsis),
                  onTap: () { _applyProfile(s); Navigator.pop(context); },
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) { if (v == 'edit') _saveProfile(existing: s); if (v == 'delete') _deleteProfile(s); },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Editar')), PopupMenuItem(value: 'delete', child: Text('Eliminar'))],
                  ),
                )),
              const Divider(height: 28, color: Colors.white12),
              const Text('UNIRSE A CANAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: channel, decoration: const InputDecoration(hintText: '#panama'))),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: controller.connected ? () => controller.join(channel.text) : null, icon: const Icon(Icons.add)),
              ]),
            ],
          ),
        ),
      );

  Widget _welcome() => Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 62, color: Colors.white.withOpacity(.4)),
          const SizedBox(height: 14),
          const Text('Bienvenido a JersIRC', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Conecta a un servidor IRC para comenzar', style: TextStyle(color: Colors.white54)),
        ],
      ));

  Widget _tabs() => SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          children: controller.rooms.values.where((r) => !r.privateChat).map((r) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: r.name == controller.activeRoom ? const Color(0xFF53677D) : const Color(0xFF252D36),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: () { controller.activeRoom = r.name; r.unread = 0; setState(() {}); _scrollBottom(); },
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.forum_outlined, size: 14),
                    const SizedBox(width: 5),
                    _tabTitle(r),
                    const SizedBox(width: 2),
                    InkWell(onTap: () => _closeRoom(r.name), borderRadius: BorderRadius.circular(12), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 14))),
                  ]),
                ),
              ),
            ),
          )).toList(),
        ),
      );

  Widget _tabTitle(ChatRoomModel r) {
    final label = Text(r.name, style: const TextStyle(fontSize: 12));
    if (r.unread <= 0 || r.name == controller.activeRoom) return label;
    return _BlinkingUnread(label: label, count: r.unread, color: _nickColor(r.name));
  }

  Widget _chat(ChatRoomModel r) => Column(children: [
    if (!controller.connected)
      Container(width: double.infinity, padding: const EdgeInsets.all(6), color: Colors.orange.withOpacity(.12), child: Text(controller.status, style: const TextStyle(fontSize: 12))),
    Expanded(child: r.messages.isEmpty
      ? Center(child: Text(r.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))
      : ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          itemCount: r.messages.length,
          itemBuilder: (context, i) {
            final m = r.messages[i];
            final user = m.nick ?? 'Sistema';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: RichText(text: TextSpan(children: [
                WidgetSpan(alignment: PlaceholderAlignment.middle, child: InkWell(
                  onTap: user == 'Sistema' ? null : () => _showUserActions(user),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1), child: Text('$user:', style: TextStyle(fontWeight: FontWeight.bold, color: _nickColor(user)))),
                )),
                TextSpan(text: ' ${_clean(m.trailing)}', style: const TextStyle(color: Colors.white)),
              ])),
            );
          },
        )),
  ]);

  Widget _users(ChatRoomModel r) => Container(
        width: 148,
        decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(left: BorderSide(color: Colors.white10))),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(7, 5, 4, 2), child: Row(children: [
            Expanded(child: Text('USUARIOS · ${r.users.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54))),
            IconButton(onPressed: () => setState(() => usersVisible = false), icon: const Icon(Icons.keyboard_double_arrow_right, size: 17), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
          ])),
          Expanded(child: ListView(padding: const EdgeInsets.all(6), children: _sortedUsers(r).map((u) => ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 2),
            title: Text('${u.prefixes}${u.nick}', overflow: TextOverflow.ellipsis, style: TextStyle(color: _nickColor(u.nick), fontWeight: FontWeight.w600)),
            onTap: () => _showUserActions(u.nick),
          )).toList())),
        ]),
      );

  Widget _collapsedUsers(ChatRoomModel r) => Material(color: const Color(0xFF151B22), child: InkWell(
        onTap: () => setState(() => usersVisible = true),
        child: SizedBox(width: 44, child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
          const SizedBox(height: 8),
          const Icon(Icons.people_alt_outlined, size: 20),
          const SizedBox(height: 4),
          Text('${r.users.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ])),
      ));

  Widget _privateSidebar() {
    final privates = _privateRooms();
    return Container(
      width: 148,
      decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(left: BorderSide(color: Colors.white10))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(7, 5, 4, 2), child: Row(children: [
          Expanded(child: Text('PRIVADOS · ${privates.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54))),
          IconButton(onPressed: () => setState(() => privateVisible = false), icon: const Icon(Icons.keyboard_double_arrow_right, size: 17), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
        ])),
        Expanded(
          child: privates.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Sin privados', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11))))
              : ListView(
                  padding: const EdgeInsets.all(6),
                  children: privates.map((r) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    selected: r.name == controller.activeRoom,
                    leading: Icon(Icons.person_outline, size: 17, color: _nickColor(r.name)),
                    title: r.unread > 0 && r.name != controller.activeRoom
                        ? _BlinkingUnread(label: Text(r.name), count: r.unread, color: _nickColor(r.name))
                        : Text(r.name, overflow: TextOverflow.ellipsis, style: TextStyle(color: _nickColor(r.name), fontWeight: FontWeight.w600)),
                    onTap: () => _openPrivateRoom(r.name),
                    trailing: IconButton(icon: const Icon(Icons.close, size: 15), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _closeRoom(r.name)),
                  )).toList(),
                ),
        ),
      ]),
    );
  }

  Widget _collapsedPrivateSidebar() => Material(
        color: const Color(0xFF151B22),
        child: InkWell(
          onTap: () => setState(() => privateVisible = true),
          child: SizedBox(
            width: 44,
            child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
              const SizedBox(height: 8),
              const Icon(Icons.chat_bubble_outline, size: 20),
              const SizedBox(height: 4),
              if (_privateUnreadTotal() > 0)
                Text('${_privateUnreadTotal()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))
              else
                Text('${_privateRooms().length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _composer() => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Row(children: [
          Expanded(child: TextField(controller: message, focusNode: messageFocus, enabled: controller.connected, onSubmitted: (_) => _send(), maxLines: 4, minLines: 1, decoration: const InputDecoration(hintText: 'Escribe un mensaje o /comando'))),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: controller.connected ? _send : null, icon: const Icon(Icons.send_rounded)),
        ]),
      ));

  String _clean(String s) => s.replaceAll(RegExp(r'\u0003(?:\d{1,2}(?:,\d{1,2})?)?'), '').replaceAll(RegExp(r'[\u0002\u000F\u0016\u001D\u001F]'), '');

  Color _nickColor(String user) {
    var h = 0;
    for (final c in user.codeUnits) h = (h * 31 + c) & 0x7fffffff;
    const c = [
      Color(0xFF7CB8FF), Color(0xFFFFA6C9), Color(0xFFB9E986), Color(0xFFFFCC80),
      Color(0xFFC7A7FF), Color(0xFF72E0D1), Color(0xFFFF9E80), Color(0xFF9FA8DA),
    ];
    return c[h % c.length];
  }
}

class IrcUserView {
  final String nick, prefixes;
  const IrcUserView(this.nick, this.prefixes);
}

class _BlinkingUnread extends StatefulWidget {
  final Widget label;
  final int count;
  final Color color;
  const _BlinkingUnread({required this.label, required this.count, required this.color});
  @override
  State<_BlinkingUnread> createState() => _BlinkingUnreadState();
}

class _BlinkingUnreadState extends State<_BlinkingUnread> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..repeat(reverse: true);
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (_, __) {
      final t = Curves.easeInOut.transform(_controller.value);
      final c = Color.lerp(Theme.of(context).colorScheme.onSurface, widget.color, t)!;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.label is Text ? (widget.label as Text).data ?? '' : '', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text('(${widget.count})', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.bold)),
      ]);
    },
  );
}
