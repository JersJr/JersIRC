import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final controller = IrcController();
  final storage = JersStorage();
  final host = TextEditingController(text: 'irc.chateamos.org');
  final port = TextEditingController(text: '6667');
  final nick = TextEditingController();
  final channel = TextEditingController(text: '#panama');
  final message = TextEditingController();
  final messageFocus = FocusNode();
  final scroll = ScrollController();
  bool secure = false, usersVisible = true, nicknameDialogOpen = false, banDialogOpen = false;
  List<SavedServer> savedServers = [];
  String? selectedProfile;
  ChatRoomModel? get room => controller.currentRoom;
  String? _lastActiveRoom;
  DetectedCountry? _country;
  List<IrcChannelInfo> _channelCatalog = const [];
  bool _webChatEntry = false;
  bool _catalogLoading = false;
  bool _operatorToolsEnabled = false;
  String? _lastWhoisNotice;

  bool get _hasOperatorRank {
    final active = room;
    if (active == null || active.privateChat) return false;
    var me = '';
    for (final entry in active.users.entries) {
      if (entry.key.toLowerCase() == nick.text.trim().toLowerCase()) { me = entry.value.prefixes; break; }
    }
    return me.contains('@') || me.contains('~') || me.contains('&');
  }

  bool get _operatorToolsAvailable => _operatorToolsEnabled && _hasOperatorRank;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_refresh);
    _loadServers();
    _loadLastNickname();
    _loadActivityNotifications();
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
    final whois = controller.whoisNotice;
    if (whois != null && whois != _lastWhoisNotice) {
      _lastWhoisNotice = whois;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showWhoisNotice(whois);
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

  Future<void> _loadActivityNotifications() async {
    final enabled = await storage.getShowActivityNotifications();
    if (!mounted) return;
    controller.setShowActivityNotifications(enabled);
    setState(() {});
  }

  String _cleanNickname(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();

  Future<void> _loadLastNickname() async {
    final last = await storage.getLastNickname();
    if (!mounted || nick.text.trim().isNotEmpty || last == null) return;
    nick.text = _cleanNickname(last);
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
    nick.text = _cleanNickname(saved.nickname);
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
    final n = _cleanNickname(nick.text);
    var ch = channel.text.trim();

    await controller.connect(host: h, port: p, nickname: n, secure: secure);
    if (controller.connected) await storage.saveLastNickname(n);
    if (!controller.connected) {
      if (mounted && controller.banNotice != null) { await _showBanError(); return; }
      if (mounted && _isNicknameError(controller.status)) { await _showNicknameError(); return; }
      if (mounted) {
        setState(() {
          _catalogLoading = false;
          _webChatEntry = false;
        });
        final detail = controller.status.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(detail.isEmpty || detail == 'Desconectado'
                ? 'No se pudo conectar al chat. Comprueba tu conexión e inténtalo de nuevo.'
                : 'No se pudo entrar al chat: $detail'),
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return;
    }

    var autoJoinedCountryRoom = false;
    if (autoSelectCountryRoom) {
      // Mostrar el chat inmediatamente. La detección de país y LIST se resuelven
      // después, en segundo plano, para que no parezca que el botón no funciona.
      ch = _fallbackCountryRoom(_country);
      channel.text = ch;
      if (ch.isNotEmpty) {
        controller.join(ch);
        autoJoinedCountryRoom = true;
      }
      if (mounted) setState(() => _catalogLoading = true);
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

    if (ch.isNotEmpty && !autoJoinedCountryRoom) {
      controller.join(ch);
    } else if (autoSelectCountryRoom && ch.isEmpty && mounted) {
      await _showRoomExplorer();
    }
    if (autoSelectCountryRoom && ch.isNotEmpty) {
      _refineCountryRoomInBackground(ch);
    }
  }

  Future<void> _refineCountryRoomInBackground(String initialRoom) async {
    try {
      _country ??= await CountryService.detect();
      if (!mounted || !controller.connected ||
          controller.activeRoom?.toLowerCase() != initialRoom.toLowerCase()) {
        if (mounted) setState(() => _catalogLoading = false);
        return;
      }
      final catalog = await controller.listChannels(timeout: const Duration(seconds: 7));
      if (!mounted) return;
      setState(() {
        _channelCatalog = catalog;
        _catalogLoading = false;
      });
      final listedCountryRoom = _defaultCountryRoom(catalog, _country);
      final desiredRoom = listedCountryRoom?.channel ?? _fallbackCountryRoom(_country);
      if (desiredRoom.isEmpty ||
          desiredRoom.toLowerCase() == initialRoom.toLowerCase() ||
          controller.activeRoom?.toLowerCase() != initialRoom.toLowerCase()) {
        return;
      }
      controller.closeRoom(initialRoom);
      channel.text = desiredRoom;
      controller.join(desiredRoom);
    } catch (_) {
      if (mounted) setState(() => _catalogLoading = false);
      // La sala de respaldo ya está abierta; un fallo de geolocalización/LIST
      // no debe bloquear la conversación.
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

  String _fallbackCountryRoom(DetectedCountry? country) {
    if (country == null) return '#panama';
    final code = country.code.trim().toUpperCase();
    if (code == 'ES') return '#españa';
    if (code == 'PA') return '#panama';
    final aliases = _countryRoomAliases[code];
    if (aliases != null && aliases.isNotEmpty) return '#${aliases.first}';
    final normalized = _normalize(country.name).replaceAll(' ', '').trim();
    return normalized.isEmpty ? '#panama' : '#$normalized';
  }

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
    if (shouldDisconnect == true) {
      await controller.disconnect();
      if (mounted) SystemNavigator.pop();
    }
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
    final roomEntry = TextEditingController();
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
                    TextField(
                      controller: roomEntry,
                      textInputAction: TextInputAction.join,
                      onSubmitted: (value) => _submitExplorerRoom(value, sheetContext),
                      decoration: InputDecoration(
                        hintText: 'Escribe un # seguido de la sala, ejemplo #Juegos',
                        prefixIcon: const Icon(Icons.tag),
                        suffixIcon: IconButton(
                          tooltip: 'Entrar a la sala',
                          onPressed: () => _submitExplorerRoom(roomEntry.text, sheetContext),
                          icon: const Icon(Icons.arrow_forward),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Países', ..._categoryKeywords.keys, 'General'].map((category) {
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
    roomEntry.dispose();
  }

  void _submitExplorerRoom(String value, BuildContext sheetContext) {
    final name = value.trim();
    if (name.isEmpty) return;
    if (!name.startsWith('#')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La sala debe comenzar con #, por ejemplo #Juegos')),
      );
      return;
    }
    if (name.length < 2 || name.substring(1).contains(RegExp(r'\s'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un nombre de sala válido, por ejemplo #Juegos')),
      );
      return;
    }
    final existing = controller.rooms.keys.firstWhere(
      (key) => key.toLowerCase() == name.toLowerCase(),
      orElse: () => '',
    );
    Navigator.pop(sheetContext);
    if (existing.isNotEmpty) {
      controller.activeRoom = existing;
      controller.rooms[existing]?.unread = 0;
      setState(() {});
      _scrollBottom();
    } else {
      channel.text = name;
      controller.join(name);
      setState(() {});
    }
  }

  List<ChatRoomModel> _privateRooms() => controller.rooms.values.where((r) => r.privateChat && !controller.ignoredUsers.contains(r.name.toLowerCase())).toList();
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

  Future<void> _confirmAdvancedSettings() async {
    // El botón de opciones debe abrirse directamente, sin un diálogo intermedio.
    if (mounted) _scaffoldKey.currentState?.openEndDrawer();
  }

  Widget _settingsDrawer() => Drawer(
    width: MediaQuery.sizeOf(context).width * .86 > 390 ? 390 : MediaQuery.sizeOf(context).width * .86,
    backgroundColor: const Color(0xFF151B22),
    child: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Row(children: [Icon(Icons.settings_outlined, color: Color(0xFF9B7BFF)), SizedBox(width: 10), Text('Configuraciones', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))]),
      const SizedBox(height: 18),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: controller.ignorePrivateMessages,
        title: const Text('Ignorar privados'),
        subtitle: const Text('Oculta los mensajes privados entrantes sin bloquear a sus remitentes.'),
        secondary: const Icon(Icons.mark_chat_unread_outlined),
        onChanged: (value) => setState(() => controller.setIgnorePrivateMessages(value)),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: controller.showActivityNotifications,
        title: const Text('Mostrar notificaciones de actividad'),
        subtitle: const Text('Muestra entradas, salidas y acciones de moderación solo en este dispositivo.'),
        secondary: const Icon(Icons.notifications_active_outlined),
        onChanged: (value) async {
          controller.setShowActivityNotifications(value);
          await storage.setShowActivityNotifications(value);
          if (mounted) setState(() {});
        },
      ),
      const Divider(height: 28),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.tag, color: Color(0xFF38BDF8)),
        title: const Text('Sala actual'),
        subtitle: Text('${room?.name ?? 'Sin sala'} · ${_hasOperatorRank ? 'Operador' : 'Usuario'}'),
      ),
      const Divider(height: 28),
      const Text('MODERACIÓN', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white54, fontWeight: FontWeight.bold)),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _operatorToolsEnabled,
        title: const Text('Modo Operador'),
        subtitle: Text(_operatorToolsAvailable ? 'Rango de operador detectado en esta sala.' : _operatorToolsEnabled ? 'Activado, pero no se detecta rango OP en la sala actual.' : 'Muestra herramientas adicionales cuando tengas rango OP.'),
        secondary: const Icon(Icons.admin_panel_settings_outlined),
        onChanged: (value) => setState(() => _operatorToolsEnabled = value),
      ),
      if (_operatorToolsEnabled && !_hasOperatorRank)
        const Padding(padding: EdgeInsets.only(left: 4, right: 4, bottom: 12), child: Text('Las acciones de moderación solo estarán disponibles cuando el servidor te conceda rango de operador (@) en una sala.', style: TextStyle(color: Colors.amber, fontSize: 12))),
      if (_operatorToolsAvailable && room != null && !room!.privateChat) ...[
        const Divider(height: 28),
        const Text('HERRAMIENTAS DE SALA', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white54, fontWeight: FontWeight.bold)),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.block_outlined), title: const Text('Lista de bans'), subtitle: const Text('Consultar y retirar bans de esta sala'), onTap: () { Navigator.pop(context); _showBanList(); }),
      ],
    ])),
  );

  Future<String?> _askReason(String title, {String initial = '', required bool requireReason}) async {
    final text = TextEditingController(text: initial);
    final result = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(controller: text, autofocus: true, maxLines: 3, decoration: InputDecoration(labelText: 'Motivo', hintText: requireReason ? 'Escribe el motivo antes de ejecutar' : 'Nick inadecuado')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        FilledButton(onPressed: () { if (!requireReason || text.text.trim().isNotEmpty) Navigator.pop(dialogContext, text.text.trim().isEmpty ? 'Nick inadecuado' : text.text.trim()); }, child: const Text('Continuar')),
      ],
    ));
    text.dispose();
    return result;
  }

  Future<int?> _askBanMinutes() async {
    final text = TextEditingController(text: '5');
    final result = await showDialog<int>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Silenciar temporalmente'),
      content: TextField(controller: text, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duración en minutos')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
        FilledButton(onPressed: () { final minutes = int.tryParse(text.text.trim()); if (minutes != null && minutes > 0 && minutes <= 10080) Navigator.pop(dialogContext, minutes); }, child: const Text('Aplicar ban')),
      ],
    ));
    text.dispose();
    return result;
  }

  Future<void> _showModerationActivity() async {
    await showDialog<void>(context: context, builder: (_) => AlertDialog(
      content: SizedBox(width: 420, height: 420, child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) => controller.moderationActivity.isEmpty
          ? const Center(child: Text('Todavía no hay actividad registrada.'))
          : ListView.builder(itemCount: controller.moderationActivity.length, itemBuilder: (_, i) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(controller.moderationActivity[i]))),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    ));
  }

  Future<void> _showBanList() async {
    final target = room?.name;
    if (target == null || !target.startsWith('#')) return;
    controller.requestBanList(target);
    await showDialog<void>(context: context, builder: (dialogContext) => AnimatedBuilder(
      animation: controller,
      builder: (_, __) => AlertDialog(
        title: Text('Bans de $target'),
        content: SizedBox(width: 420, height: 420, child: controller.channelBans.isEmpty
          ? const Center(child: Text('No hay bans o el servidor aún no respondió.'))
          : ListView(children: controller.channelBans.values.map((mask) => ListTile(
              dense: true,
              title: SelectableText(mask),
              trailing: IconButton(tooltip: 'Quitar ban', icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent), onPressed: () => controller.removeBan(target, mask)),
            )).toList())),
        actions: [
          TextButton(onPressed: () { controller.requestBanList(target); }, child: const Text('Actualizar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar')),
        ],
      ),
    ));
  }

  Future<void> _showWhoisNotice(String details) async {
    await showDialog<void>(context: context, builder: (_) => AlertDialog(
      title: const Text('Información WHOIS'),
      content: SingleChildScrollView(child: SelectableText(details)),
      actions: [TextButton(onPressed: () { controller.clearWhoisNotice(); _lastWhoisNotice = null; Navigator.pop(context); }, child: const Text('Cerrar'))],
    ));
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
        isOperator: _operatorToolsAvailable,
        onWhois: () => controller.requestWhois(nickname),
        onIgnore: () => controller.toggleIgnore(nickname),
        onBanNick: () async {
          final target = room?.name;
          if (target != null && target.startsWith('#')) {
            final reason = await _askReason('Kick + Ban por nick', initial: 'Nick inadecuado', requireReason: false);
            if (reason != null) controller.kickBanNickname(target, nickname, reason);
          }
        },
        onBanHost: () async {
          final target = room?.name;
          if (target != null && target.startsWith('#')) {
            final reason = await _askReason('Kick + Ban por IP virtual', requireReason: true);
            if (reason != null) controller.kickBanVirtualHost(target, nickname, reason);
          }
        },
        onTemporaryBan: () async {
          final target = room?.name;
          if (target == null || !target.startsWith('#')) return;
          final minutes = await _askBanMinutes();
          if (minutes != null) controller.temporaryBan(target, nickname, minutes);
        },
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
        key: _scaffoldKey,
        appBar: controller.connected
            ? AppBar(
                backgroundColor: const Color(0xFF0D0D1B),
                leading: const SizedBox.shrink(),
                leadingWidth: 8,
                titleSpacing: 4,
                title: Row(children: [
                  Flexible(
                    child: Text(
                      room?.name ?? 'Parloteo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ]),
                actions: [
                  if (room != null && !room!.privateChat)
                    TextButton(
                      onPressed: _toggleUsers,
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFC4B5FD), padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.people_alt_outlined, size: 20),
                        const SizedBox(width: 5),
                        Text('${room!.users.length}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 3),
                        Icon(usersVisible ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_left, size: 18),
                      ]),
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
                backgroundColor: const Color(0xFF0D0D1B),
                title: const Row(mainAxisSize: MainAxisSize.min, children: [
                  _ParloteoLogo(size: 28),
                  SizedBox(width: 8),
                  Text('Parloteo', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
        drawer: controller.connected ? _drawer() : null,
        endDrawer: controller.connected ? _settingsDrawer() : null,
        bottomNavigationBar: controller.connected ? _bottomNavigationBar() : null,
        body: Column(children: [
          if (room != null) _tabs(),
          Expanded(child: Row(children: [
            Expanded(child: room == null ? _welcome() : _chat(room!)),
            if (room != null && !room!.privateChat)
              usersVisible ? _users(room!) : _collapsedUsers(room!),
          ])),
          if (room != null) _composer(),
        ]),
      );

  Widget _bottomNavigationBar() => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D1B),
            border: Border(top: BorderSide(color: Color(0x332C2B48))),
          ),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          child: Row(children: [
            Expanded(child: _bottomNavItem(Icons.explore_outlined, 'Salas', _showRoomExplorer)),
            Expanded(child: _bottomNavItem(Icons.mail_outline_rounded, 'Privados', () => _scaffoldKey.currentState?.openDrawer(), badge: _privateUnreadTotal())),
            Expanded(child: _bottomNavItem(Icons.tune_rounded, 'Opciones', () => _scaffoldKey.currentState?.openEndDrawer())),
          ]),
        ),
      );

  Widget _bottomNavItem(IconData icon, String label, VoidCallback onTap, {int badge = 0}) =>
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(icon, size: 22, color: const Color(0xFFC4B5FD)),
              if (badge > 0) Positioned(right: -10, top: -5, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFD946EF), borderRadius: BorderRadius.circular(10)),
                child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              )),
            ]),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA5A3C2), fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  void _toggleUsers() {
    final active = room;
    if (active == null || active.privateChat) return;
    setState(() => usersVisible = !usersVisible);
  }

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
    final hasExchangedMessages = r.messages.any(
      (m) => m.command == 'PRIVMSG' || m.command == 'NOTICE',
    );
    return ActionChip(
      avatar: Icon(Icons.person_outline, size: 16, color: _nickColor(r.name)),
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        if (hasExchangedMessages) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('DM', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ],
        Text(label, overflow: TextOverflow.ellipsis),
      ]),
      backgroundColor: active ? const Color(0xFF53677D) : null,
      onPressed: () => _openPrivateRoom(r.name),
    );
  }

  Future<void> _changeNickname() async {
    final value = nick.text.trim();
    if (value.isEmpty || !controller.connected) return;
    controller.changeNick(value);
    await storage.saveLastNickname(value);
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
              const Text('Cambio de nick', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
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
              const Text('Privados', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF171329), Color(0xFF101121)]),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0x338B5CF6)),
                boxShadow: const [BoxShadow(color: Color(0x221D1640), blurRadius: 28, offset: Offset(0, 12))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _ParloteoLogo(size: 64),
                  const SizedBox(height: 16),
                  const Text('Bienvenido a Parloteo', textAlign: TextAlign.center, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                  const SizedBox(height: 7),
                  const Text('Conversa, descubre salas y conoce personas.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA5A3C2), height: 1.4)),
                  const SizedBox(height: 24),
                  Align(alignment: Alignment.centerLeft, child: Text('¿Cómo te llamamos?', style: TextStyle(color: Color(0xFFC4B5FD), fontWeight: FontWeight.w700, fontSize: 13))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nick,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _enterWebChat(),
                    decoration: const InputDecoration(labelText: 'Tu nick', hintText: 'Escribe tu apodo', prefixIcon: Icon(Icons.person_outline_rounded)),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: const Color(0xFF0C0D1A), borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      const Icon(Icons.public_rounded, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_country == null ? 'Sala de tu comunidad' : 'País detectado: ${_country!.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 3),
                        Text(_country == null ? 'Te conectaremos a una sala disponible.' : 'Buscaremos la sala de ${_country!.name} automáticamente.', style: const TextStyle(color: Color(0xFFA5A3C2), fontSize: 11)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: controller.connecting ? null : _enterWebChat,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(controller.connecting ? 'Conectando…' : 'Entrar a Parloteo'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  )),
                  if (controller.connecting || (!controller.connected && controller.status != 'Desconectado')) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: controller.connecting
                            ? const Color(0x1A8B5CF6)
                            : const Color(0x1AD946EF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: controller.connecting
                              ? const Color(0x558B5CF6)
                              : const Color(0x55D946EF),
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          controller.connecting ? Icons.sync_rounded : Icons.error_outline_rounded,
                          color: controller.connecting ? const Color(0xFFC4B5FD) : const Color(0xFFF0ABFC),
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            controller.status,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                        if (controller.connecting)
                          const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text('Tu último nick se recordará para la próxima vez.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8589A6), fontSize: 11)),
                ],
              ),
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
    await storage.saveLastNickname(_cleanNickname(value));
    host.text = 'irc.chateamos.org';
    port.text = '6667';
    channel.clear();
    secure = false;
    selectedProfile = null;
    _webChatEntry = true;
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
              color: r.name == controller.activeRoom ? const Color(0xFF34205B) : const Color(0xFF171329),
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

  String _messageTime(DateTime? timestamp) {
    final value = (timestamp ?? DateTime.now()).toLocal();
    return '${value.hour}:${value.minute.toString().padLeft(2, '0')}';
  }

  Widget _chat(ChatRoomModel r) => Column(children: [
    if (r.privateChat)
      Container(
        width: double.infinity,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(
          color: Color(0xFF151B22),
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(children: [
          const Icon(Icons.person_outline_rounded, size: 17, color: Color(0xFF9B7BFF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Chat privado · ${r.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
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
            if (m.command == 'SYSTEM') {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _clean(m.trailing),
                    textAlign: TextAlign.left,
                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              );
            }
            if (m.command == 'DISCONNECTED_USER') {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  _clean(m.trailing),
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                ),
              );
            }
            final user = m.nick ?? 'Sistema';
            final ownMessage = user.toLowerCase() == _cleanNickname(nick.text).toLowerCase();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: ownMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  if (!ownMessage) ...[
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF21163B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(user.isEmpty ? '?' : user.substring(0, 1).toUpperCase(),
                        style: TextStyle(color: _nickColor(user), fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Column(
                      crossAxisAlignment: ownMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(child: InkWell(
                            onTap: user == 'Sistema' ? null : () => _showUserActions(user),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text(ownMessage ? 'Tú' : user,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _nickColor(user))),
                            ),
                          )),
                          const SizedBox(width: 6),
                          Text(_messageTime(m.timestamp), style: const TextStyle(fontSize: 9, letterSpacing: .15, color: Color(0xFF85819D), fontWeight: FontWeight.w500)),
                        ]),
                        Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                          decoration: BoxDecoration(
                            color: ownMessage ? const Color(0xFF34205B) : const Color(0xFF171329),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(ownMessage ? 16 : 5),
                              bottomRight: Radius.circular(ownMessage ? 5 : 16),
                            ),
                            border: Border.all(color: ownMessage ? const Color(0x558B5CF6) : const Color(0x222C2B48)),
                          ),
                          child: Text(_clean(m.trailing), style: const TextStyle(color: Color(0xFFF4F3FA), height: 1.35)),
                        ),
                      ],
                    ),
                  ),
                  if (ownMessage) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A194D),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(user.isEmpty ? '?' : user.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Color(0xFFF5D0FE), fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
            );
          },
        )),
  ]);

  Widget _users(ChatRoomModel r) => Container(
        width: (MediaQuery.sizeOf(context).width * .38).clamp(124.0, 176.0).toDouble(),
        decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(left: BorderSide(color: Colors.white10))),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(7, 5, 4, 2), child: Row(children: [
            Expanded(child: Text('USUARIOS · ${r.users.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54))),
            IconButton(onPressed: _toggleUsers, icon: const Icon(Icons.keyboard_double_arrow_right, size: 17), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
          ])),
          Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), children: _sortedUsers(r).map((u) {
            final ignored = controller.ignoredUsers.contains(u.nick.toLowerCase());
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF171329), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x222C2B48))),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _showUserActions(u.nick),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                  child: Row(children: [
                    CircleAvatar(radius: 12, backgroundColor: const Color(0xFF292044), child: Text(u.nick.isEmpty ? '?' : u.nick.substring(0, 1).toUpperCase(), style: TextStyle(fontSize: 10, color: _nickColor(u.nick), fontWeight: FontWeight.w800))),
                    const SizedBox(width: 5),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        if (ignored) const Padding(padding: EdgeInsets.only(right: 3), child: Icon(Icons.block, size: 12, color: Colors.redAccent)),
                        if (u.prefixes.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 3), child: Text(u.prefixes, style: TextStyle(fontSize: 10, color: _nickColor(u.nick), fontWeight: FontWeight.w700))),
                        Expanded(child: Text(u.nick, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: _nickColor(u.nick), fontWeight: FontWeight.w700))),
                      ]),
                    ])),
                  ]),
                ),
              ),
            );
          }).toList())),
        ]),
      );

  Widget _collapsedUsers(ChatRoomModel r) => Material(color: const Color(0xFF111323), child: InkWell(
        onTap: () => setState(() => usersVisible = true),
        child: Container(width: 38, decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0x332C2B48)))), child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
          const SizedBox(height: 9),
          const Icon(Icons.keyboard_arrow_left, size: 17, color: Color(0xFFC4B5FD)),
          const SizedBox(height: 5),
          const Icon(Icons.people_alt_outlined, size: 19, color: Color(0xFFC4B5FD)),
          const SizedBox(height: 4),
          Text('${r.users.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white)),
        ])),
      ));

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: const BoxDecoration(color: Color(0xFF0D0D1B), border: Border(top: BorderSide(color: Color(0x222C2B48)))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: TextField(
              controller: message,
              focusNode: messageFocus,
              enabled: controller.connected,
              onSubmitted: (_) => _send(),
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje…',
                prefixIcon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                filled: true,
                fillColor: const Color(0xFF171329),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 9),
            Container(
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFD946EF)]), borderRadius: BorderRadius.circular(18)),
              child: IconButton(onPressed: controller.connected ? _send : null, color: Colors.white, icon: const Icon(Icons.send_rounded), tooltip: 'Enviar mensaje'),
            ),
          ]),
        ),
      );

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

class _ParloteoLogo extends StatelessWidget {
  final double size;
  const _ParloteoLogo({this.size = 28});

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
          colors: [Color(0xFF1D4ED8), Color(0xFF172554)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x553B82F6), blurRadius: 7, spreadRadius: 1),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.chat_bubble_rounded, color: Colors.white, size: size * .63),
          Positioned(
            top: -size * .12,
            child: Text('👑', style: TextStyle(fontSize: size * .38, height: 1)),
          ),
        ],
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