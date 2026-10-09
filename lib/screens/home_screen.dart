import 'package:flutter/material.dart';
import '../controllers/irc_controller.dart';
import '../models.dart';
import '../storage.dart';
import '../widgets/user_action_sheet.dart';
import '../services/country_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final controller = IrcController();
  final storage = JersStorage();
  final host = TextEditingController(text: 'irc.chateamos.org');
  final port = TextEditingController(text: '6667');
  final nick = TextEditingController();
  final channel = TextEditingController(text: '#panama');
  final message = TextEditingController();
  final messageFocus = FocusNode();
  final scroll = ScrollController();
  bool secure = false, usersVisible = true, privateVisible = false, nicknameDialogOpen = false, banDialogOpen = false;
  List<SavedServer> savedServers = [];
  String? selectedProfile;
  ChatRoomModel? get room => controller.currentRoom;
  String? _lastActiveRoom;
  DetectedCountry? _country;
  List<IrcChannelInfo> _channelCatalog = const [];
  bool _webChatEntry = false;
  bool _catalogLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_refresh);
    _loadServers();
    _loadLastNickname();
  }

  void _refresh() {
    if (!mounted) return;
    final activeRoomName = controller.activeRoom;
    final roomChanged = activeRoomName != _lastActiveRoom;
    _lastActiveRoom = activeRoomName;
    setState(() {});
    if (roomChanged) _scrollBottom();
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
    // La pantalla inicial usa siempre el acceso WebChat. Los perfiles se mantienen
    // disponibles únicamente desde la configuración avanzada después de conectar.
  }

  Future<void> _loadLastNickname() async {
    final last = await storage.getLastNickname();
    if (!mounted || nick.text.trim().isNotEmpty || last == null) return;
    nick.text = last;
    setState(() {});
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
      await _connect(autoSelectCountryRoom: _webChatEntry);
    }
  }

  Future<void> _connect({bool autoSelectCountryRoom = false}) async {
    final p = int.tryParse(port.text) ?? (secure ? 6697 : 6667);
    final h = host.text.trim();
    final n = nick.text.trim();
    var ch = channel.text.trim();

    await controller.connect(host: h, port: p, nickname: n, secure: secure);
    if (controller.connected) await storage.saveLastNickname(n);
    if (!controller.connected) {
      if (mounted && controller.banNotice != null) { await _showBanError(); return; }
      if (mounted && _isNicknameError(controller.status)) await _showNicknameError();
      return;
    }

    if (autoSelectCountryRoom) {
      _country ??= await CountryService.detect();
      if (mounted) setState(() => _catalogLoading = true);
      final catalog = await controller.listChannels();
      if (!mounted) return;
      setState(() {
        _channelCatalog = catalog;
        _catalogLoading = false;
      });
      final defaultRoom = _defaultCountryRoom(catalog, _country);
      if (defaultRoom != null) {
        ch = defaultRoom.channel;
        channel.text = ch;
      } else {
        ch = '';
        channel.clear();
      }
    }

    final profileName = selectedProfile?.trim().isNotEmpty == true ? selectedProfile! : h;
    await storage.upsertServer(SavedServer(
      name: profileName,
      host: h,
      port: p,
      nickname: n,
      tls: secure,
      channels: ch.isEmpty ? const [] : [ch],
    ));
    await storage.setLastServer(profileName);
    final list = await storage.loadServers();
    if (mounted) setState(() {
      savedServers = list;
      _webChatEntry = false;
    });

    if (ch.isNotEmpty) {
      controller.join(ch);
    } else if (autoSelectCountryRoom && mounted) {
      await _showRoomExplorer();
    }
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâãå]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöôõ]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9#&+!]+'), ' ');
  }

  bool _containsWord(String value, String word) {
    final source = _normalize(value);
    final target = _normalize(word).trim();
    if (target.isEmpty) return false;
    return RegExp(r'(^|\s)' + RegExp.escape(target) + r'(\s|$)').hasMatch(source);
  }

  // Nombres habituales de salas por país. Se usa el código ISO detectado por IP
  // para contemplar que el servidor puede nombrarlas en español o en inglés.
  static const Map<String, List<String>> _countryRoomAliases = {
    'ES': ['espana', 'spain'],
    'DE': ['alemania', 'germany', 'deutschland'],
    'US': ['estadosunidos', 'unitedstates', 'usa', 'america'],
    'GB': ['reinounido', 'unitedkingdom', 'uk', 'britain'],
    'FR': ['francia', 'france'],
    'IT': ['italia', 'italy'],
    'PT': ['portugal'],
    'MX': ['mexico'],
    'DO': ['republicadominicana', 'dominicanrepublic'],
    'CR': ['costarica'],
    'SV': ['elsalvador'],
    'NL': ['paisesbajos', 'netherlands', 'holland'],
    'BR': ['brasil', 'brazil'],
    'CH': ['suiza', 'switzerland'],
    'BE': ['belgica', 'belgium'],
    'JP': ['japon', 'japan'],
    'KR': ['coreadelsur', 'southkorea', 'korea'],
    'CA': ['canada'],
    'AR': ['argentina'],
    'CL': ['chile'],
    'CO': ['colombia'],
    'PE': ['peru'],
    'PA': ['panama'],
    'VE': ['venezuela'],
    'EC': ['ecuador'],
    'UY': ['uruguay'],
    'PY': ['paraguay'],
    'BO': ['bolivia'],
    'GT': ['guatemala'],
    'HN': ['honduras'],
    'NI': ['nicaragua'],
    'CU': ['cuba'],
    'PR': ['puertorico'],
    'AU': ['australia'],
    'IE': ['irlanda', 'ireland'],
    'RU': ['rusia', 'russia'],
    'UA': ['ucrania', 'ukraine'],
    'SE': ['suecia', 'sweden'],
    'NO': ['noruega', 'norway'],
    'DK': ['dinamarca', 'denmark'],
    'PL': ['polonia', 'poland'],
    'GR': ['grecia', 'greece'],
    'TR': ['turquia', 'turkey'],
    'MA': ['marruecos', 'morocco'],
    'IN': ['india'],
    'CN': ['china'],
  };

  IrcChannelInfo? _defaultCountryRoom(List<IrcChannelInfo> channels, DetectedCountry? country) {
    if (country == null) return null;
    final countryName = _normalize(country.name).replaceAll(' ', '').trim();
    final code = country.code.trim().toUpperCase();
    final candidates = <String>{
      if (countryName.isNotEmpty) countryName,
      if (code.isNotEmpty) code.toLowerCase(),
      ...?_countryRoomAliases[code]?.map(
        (alias) => _normalize(alias).replaceAll(' ', '').trim(),
      ),
    };
    if (candidates.isEmpty) return null;

    // Solo el nombre de la sala decide el ingreso automático, nunca el topic.
    // La coincidencia es exacta para no entrar por error a salas temáticas.
    for (final info in channels) {
      final name = _normalize(
        info.channel.replaceFirst(RegExp(r'^[#&+!]'), ''),
      ).replaceAll(' ', '').trim();
      if (candidates.contains(name)) return info;
    }
    return null;
  }

  static const Map<String, List<String>> _categoryKeywords = {
    'Amistad': ['amistad', 'amigos', 'amigas', 'amigo', 'friend', 'friends'],
    'Sex': ['sex', 'sexo', 'adult', 'adultos', 'erotico', 'erotica', 'xxx'],
    'Juegos': ['juegos', 'juego', 'gaming', 'gamer', 'gamers', 'videojuegos'],
    'Música': ['musica', 'music', 'musical', 'rock', 'pop', 'reggaeton'],
    'LGBT': ['lgbt', 'lgbtq', 'gay', 'gays', 'lesbiana', 'lesbianas', 'lesbian', 'trans', 'transgenero', 'transexual', 'bisexual', 'bisexuales', 'queer', 'orgullo', 'amistadgay', 'amigosgay'],
  };

  static const List<String> _countryKeywords = [
    'afganistan','albania','alemania','andorra','angola','arabia','argelia','argentina','armenia','australia','austria','azerbaiyan','bahamas','bahrein','bangladesh','barbados','belgica','belice','benin','bhutan','bolivia','bosnia','botsuana','brasil','brunei','bulgaria','burkina','burundi','cabo','camerun','canada','chad','chile','china','chipre','colombia','comoras','congo','corea','croacia','cuba','dinamarca','dominica','ecuador','egipto','elsalvador','emiratos','eritrea','eslovaquia','eslovenia','espana','estadosunidos','estonia','etiopia','filipinas','finlandia','fiyi','francia','gabon','gambia','georgia','ghana','granada','grecia','guatemala','guinea','guyana','haiti','honduras','hungria','india','indonesia','iran','iraq','irlanda','islandia','israel','italia','jamaica','japon','jordania','kazajistan','kenia','kirguistan','kuwait','laos','letonia','libano','liberia','libia','liechtenstein','lituania','luxemburgo','madagascar','malasia','malaui','maldivas','mali','malta','marruecos','mauritania','mauricio','mexico','moldavia','monaco','mongolia','montenegro','mozambique','namibia','nepal','nicaragua','niger','nigeria','noruega','nuevazelanda','oman','paisesbajos','pakistan','panama','paraguay','peru','polonia','portugal','qatar','republicadominicana','rumania','rusia','salvador','samoa','senegal','serbia','singapur','siria','somalia','srilanka','sudafrica','sudan','suecia','suiza','tailandia','taiwan','tanzania','togo','tonga','trinidad','tunez','turquia','ucrania','uganda','uruguay','uzbekistan','vanuatu','venezuela','vietnam','yemen','zambia','zimbabue'
  ];

  bool _channelNameMatches(IrcChannelInfo info, String keyword) {
    final name = _normalize(info.channel.replaceFirst(RegExp(r'^[#&+!]'), ''));
    final key = _normalize(keyword);
    return name == key || _containsWord(name, key) || name.startsWith('$key-') || name.startsWith('${key}_');
  }

  bool _isCountryRoom(IrcChannelInfo info) => _countryKeywords.any((country) => _channelNameMatches(info, country));

  String? _categoryFor(IrcChannelInfo info) {
    // Una sala solo puede pertenecer a una categoría y se analiza solo su nombre.
    for (final category in _categoryKeywords.keys) {
      if (_categoryKeywords[category]!.any((keyword) => _channelNameMatches(info, keyword))) return category;
    }
    if (_isCountryRoom(info)) return 'Países';
    return null;
  }

  List<IrcChannelInfo> _categoryRooms(String category) {
    final result = _channelCatalog.where((info) => _categoryFor(info) == category).toList();
    result.sort((a, b) => b.users.compareTo(a.users));
    return result.take(10).toList();
  }

  List<IrcChannelInfo> _generalRooms() {
    final result = _channelCatalog.where((info) => _categoryFor(info) == null).toList();
    result.sort((a, b) => b.users.compareTo(a.users));
    return result.take(10).toList();
  }
  Future<void> _confirmDisconnect() async {
    final shouldDisconnect = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desconectar'),
        content: const Text('¿Deseas desconectarte del chat?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (shouldDisconnect == true) await controller.disconnect();
  }

  Future<void> _showRoomExplorer() async {
    if (_catalogLoading) return;
    if (_channelCatalog.isEmpty && controller.connected) {
      setState(() => _catalogLoading = true);
      final catalog = await controller.listChannels();
      if (!mounted) return;
      setState(() {
        _channelCatalog = catalog;
        _catalogLoading = false;
      });
    }

    if (!mounted) return;
    String selected = 'Países';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151B22),
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final rooms = selected == 'General' ? _generalRooms() : _categoryRooms(selected);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * .78,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Salas de chats',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF55C7FF)),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Actualizar salas',
                          onPressed: () async {
                            setSheetState(() {});
                            final catalog = await controller.listChannels();
                            if (!mounted) return;
                            setState(() => _channelCatalog = catalog);
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Selecciona una categoría y entra a una sala que realmente esté disponible.', style: TextStyle(color: Color(0xFF9B7BFF))),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Países', ..._categoryKeywords.keys, 'LGBT', 'General'].map((category) {
                        final active = category == selected;
                        return ChoiceChip(
                          label: Text(category),
                          selected: active,
                          onSelected: (_) => setSheetState(() => selected = category),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: rooms.isEmpty
                          ? const Center(child: Text('No encontré salas de esta categoría.'))
                          : ListView.separated(
                              itemCount: rooms.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                              itemBuilder: (_, index) {
                                final info = rooms[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.forum_outlined, size: 18),
                                  title: Text('${info.channel} ${info.users} usuarios'),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    channel.text = info.channel;
                                    controller.join(info.channel);
                                    setState(() {});
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scrollBottom();
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
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_refresh);
    controller.dispose();
    for (final c in [host, port, nick, channel, message, scroll]) c.dispose();
    messageFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: controller.connected
            ? AppBar(
                backgroundColor: const Color(0xFF111820),
                leading: const SizedBox(width: 8),
                titleSpacing: 0,
                title: Row(mainAxisSize: MainAxisSize.min, children: [
                  const _JersIrcLogo(size: 24),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF55C7FF), Color(0xFF9B7BFF)],
                          ).createShader(bounds),
                          child: const Text('JersIRC', style: TextStyle(fontSize: 14, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                        Text(
                          nick.text.trim().isEmpty ? 'Nick' : nick.text.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, height: 1.2, color: Colors.white60, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ]),
                actions: [
                  IconButton(
                    tooltip: 'Descubrir salas',
                    onPressed: _showRoomExplorer,
                    icon: const Icon(Icons.explore_outlined, color: Color(0xFF9B7BFF)),
                  ),
                  _PrivateAppBarButton(
                    unreadCount: _privateUnreadTotal(),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                  IconButton(
                    tooltip: 'Configuración avanzada',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  IconButton(
                    tooltip: 'Desconectar',
                    onPressed: _confirmDisconnect,
                    icon: const Icon(Icons.logout_rounded, size: 19),
                  ),
                  const SizedBox(width: 4),
                ],
              )
            : AppBar(
                backgroundColor: const Color(0xFF111820),
                title: const Row(mainAxisSize: MainAxisSize.min, children: [
                  _JersIrcLogo(size: 28),
                  SizedBox(width: 8),
                  Text('JersIRC', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
        drawer: controller.connected ? _drawer() : null,
        body: Column(children: [
          if (room != null) _tabs(),
          Expanded(child: Row(children: [
            Expanded(child: room == null ? _welcome() : _chat(room!)),
            if (room != null && !room!.privateChat)
              usersVisible ? _users(room!) : _collapsedUsers(room!)
            else if (room != null && room!.privateChat)
              privateVisible ? _privateSidebar() : _collapsedPrivateSidebar(),
          ])),
          if (room != null) _composer(),
        ]),
      );

  Widget _navigationPanel() {
    final privates = _privateRooms();
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Row(children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: 7),
            const Text('CAMBIAR DE NICK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54)),
            const SizedBox(width: 10),
            Expanded(child: SizedBox(height: 40, child: TextField(
              controller: nick, enabled: controller.connected && !controller.connecting,
              textInputAction: TextInputAction.done, onSubmitted: (_) => _changeNickname(),
              decoration: const InputDecoration(hintText: 'Nuevo Nick', prefixIcon: Icon(Icons.edit_outlined, size: 18)),
            ))),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: 'Cambiar Nick', onPressed: controller.connected && !controller.connecting ? _changeNickname : null, icon: const Icon(Icons.check)),
          ])),
          const SizedBox(width: 18),
          SizedBox(width: MediaQuery.of(context).size.width * .36, child: _navigationSection(
            title: 'DM', icon: Icons.chat_bubble_outline,
            child: privates.isEmpty
                ? const Text('Sin conversaciones privadas', style: TextStyle(color: Colors.white38, fontSize: 12))
                : SizedBox(height: 42, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: privates.length, separatorBuilder: (_, __) => const SizedBox(width: 6), itemBuilder: (_, index) => _privateChip(privates[index]))),
          )),
        ]),
      ),
    );
  }
  Widget _navigationSection({required String title, required IconData icon, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54)),
          ],
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }

  Widget _privateChip(ChatRoomModel r) {
    final active = r.name == controller.activeRoom;
    final label = r.unread > 0 && !active ? '${r.name} (${r.unread})' : r.name;
    return ActionChip(
      avatar: Icon(Icons.person_outline, size: 16, color: _nickColor(r.name)),
      label: Text(label, overflow: TextOverflow.ellipsis),
      backgroundColor: active ? const Color(0xFF53677D) : null,
      onPressed: () => _openPrivateRoom(r.name),
    );
  }

  Future<void> _changeNickname() async {
    final value = nick.text.trim();
    if (value.isEmpty || !controller.connected) return;
    controller.changeNick(value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nick cambiado a $value')),
      );
      setState(() {});
    }
  }

  Widget _drawer() => Drawer(
        backgroundColor: const Color(0xFF151B22),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Center(child: Text('Configuración avanzada', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              const Center(child: Text('Nickname y conversaciones privadas', style: TextStyle(color: Colors.white54))),
              const SizedBox(height: 22),
              const Text('CAMBIAR DE NICK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: nick,
                    enabled: controller.connected && !controller.connecting,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _changeNickname(),
                    decoration: const InputDecoration(
                      hintText: 'Nuevo Nick',
                      prefixIcon: Icon(Icons.edit_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Cambiar Nick',
                  onPressed: controller.connected && !controller.connecting ? _changeNickname : null,
                  icon: const Icon(Icons.check),
                ),
              ]),
              const SizedBox(height: 18),
              const Text('CONVERSACIONES PRIVADAS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
              const SizedBox(height: 8),
              Builder(
                builder: (_) {
                  final privates = _privateRooms();
                  if (privates.isEmpty) {
                    return const Text('Sin conversaciones privadas', style: TextStyle(color: Colors.white38, fontSize: 12));
                  }
                  return Column(
                    children: privates.map((r) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      selected: r.name == controller.activeRoom,
                      leading: Icon(Icons.person_outline, color: _nickColor(r.name)),
                      title: r.unread > 0 && r.name != controller.activeRoom
                          ? _BlinkingUnread(label: Text(r.name), count: r.unread, color: _nickColor(r.name))
                          : Text(r.name, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.pop(context);
                        _openPrivateRoom(r.name);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => _closeRoom(r.name),
                      ),
                    )).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      );

  Widget _welcome() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.forum_rounded, size: 54),
                const SizedBox(height: 18),
                const Text(
                  'Escoja su Nick',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Elija cómo quiere aparecer en el chat',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
                if (_country != null) ...[
                  const SizedBox(height: 8),
                  Text('País detectado: ${_country!.name}', style: const TextStyle(color: Colors.white70)),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: nick,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _enterWebChat(),
                  decoration: const InputDecoration(
                    labelText: 'Nickname',
                    hintText: 'Escriba su Nick',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: controller.connecting ? null : _enterWebChat,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(controller.connecting ? 'Conectando...' : 'Entrar al chat'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _enterWebChat() async {
    final value = nick.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escriba un Nick para entrar al chat.')),
      );
      return;
    }
    host.text = 'irc.chateamos.org';
    port.text = '6667';
    channel.clear();
    secure = false;
    selectedProfile = null;
    _webChatEntry = true;
    _country = await CountryService.detect();
    if (mounted) setState(() {});
    await _connect(autoSelectCountryRoom: true);
  }

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
    Container(
      width: double.infinity,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF151B22),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(children: [
        Icon(r.privateChat ? Icons.person_outline_rounded : Icons.tag_rounded,
            size: 17, color: r.privateChat ? const Color(0xFF9B7BFF) : const Color(0xFF55C7FF)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            r.privateChat ? 'Chat privado · ${r.name}' : r.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        if (!r.privateChat) ...[
          const Icon(Icons.people_alt_outlined, size: 15, color: Colors.white54),
          const SizedBox(width: 5),
          Text('${r.users.length}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ] else
          const Text('Mensaje directo', style: TextStyle(fontSize: 10, color: Colors.white54)),
      ]),
    ),
    if (!controller.connected)
      Container(width: double.infinity, padding: const EdgeInsets.all(6), color: Colors.orange.withOpacity(.12), child: Text(controller.status, style: const TextStyle(fontSize: 12))),
    Expanded(child: r.messages.isEmpty
      ? Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(r.privateChat ? Icons.forum_outlined : Icons.tag_rounded, size: 30, color: Colors.white24),
            const SizedBox(height: 8),
            Text(r.privateChat ? 'Inicia una conversación con ${r.name}' : 'Sala ${r.name}', style: const TextStyle(fontSize: 14, color: Colors.white54)),
          ]),
        )
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

class _JersIrcLogo extends StatelessWidget {
  final double size;
  const _JersIrcLogo({this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .25),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF35C5FF), Color(0xFF7657FF)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x5535C5FF), blurRadius: 7, spreadRadius: 1),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'J',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .58,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _PrivateAppBarButton extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onPressed;
  const _PrivateAppBarButton({required this.unreadCount, required this.onPressed});

  @override
  State<_PrivateAppBarButton> createState() => _PrivateAppBarButtonState();
}

class _PrivateAppBarButtonState extends State<_PrivateAppBarButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = widget.unreadCount > 0;
    return IconButton(
      tooltip: hasUnread ? 'Privados: ${widget.unreadCount} por leer' : 'Privados',
      onPressed: widget.onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              final t = hasUnread ? Curves.easeInOut.transform(_controller.value) : 0.0;
              final color = Color.lerp(
                Theme.of(context).appBarTheme.foregroundColor ?? Colors.white,
                Colors.redAccent,
                t,
              );
              return Icon(Icons.chat_bubble_outline, color: color);
            },
          ),
          if (hasUnread)
            Positioned(
              right: -7,
              top: -7,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF151B22), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
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