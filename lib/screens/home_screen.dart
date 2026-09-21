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
  bool secure = false, usersVisible = true, privateVisible = true, nicknameDialogOpen = false, banDialogOpen = false;
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
          FilledButton(onPressed: () { final v = nameController.text.trim(); if (v.isNotEmpty) Navigator.pop(context, v); }, child: const Text('Guardar')),
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
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Eliminar perfil'), content: Text('¿Eliminar "${profile.name}"?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar'))]));
    if (ok != true) return;
    await storage.deleteServer(profile.name);
    if (await storage.getLastServer() == profile.name) await storage.clearLastServer();
    final list = await storage.loadServers();
    if (!mounted) return;
    setState(() { savedServers = list; if (selectedProfile == profile.name) selectedProfile = null; });
  }

  bool _isNicknameError(String value) {
    final x = value.toLowerCase();
    return x.contains('nickname en uso') || x.contains('nickname en conflicto') || x.contains('nickname/recurso no disponible') || x.contains('nickname no válido') || x.contains('contraseña incorrecta') || x.contains('contraseña incorrecta o requerida');
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
    final result = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => AlertDialog(title: const Text('Nickname ocupado o registrado'), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('El nickname no está disponible. Favor coloque un nuevo nickname.'), const SizedBox(height: 14), TextField(controller: nick, autofocus: true, decoration: const InputDecoration(labelText: 'Nuevo nickname'), onSubmitted: (_) => Navigator.pop(context, true))]), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reintentar'))]));
    nicknameDialogOpen = false;
    if (result == true && mounted && nick.text.trim().isNotEmpty) await _connect();
  }

  Future<void> _connect() async {
    final p = int.tryParse(port.text) ?? (secure ? 6697 : 6667);
    final h = host.text.trim(); final n = nick.text.trim(); final ch = channel.text.trim();
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
