import 'dart:async';
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
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF91A7C4), brightness: Brightness.dark),
          scaffoldBackgroundColor: const Color(0xFF11161C),
        ),
        home: const IrcHomePage(),
      );
}

class ChatRoom {
  ChatRoom(this.name, {this.privateChat = false});
  final String name;
  final bool privateChat;
  final List<IrcMessage> messages = [];
  final Set<String> users = {};
  final Map<String, String> modes = {};
  int unread = 0;
}

class IrcHomePage extends StatefulWidget {
  const IrcHomePage({super.key});
  @override
  State<IrcHomePage> createState() => _IrcHomePageState();
}

class _IrcHomePageState extends State<IrcHomePage> {
  final client = IrcClient();
  final host = TextEditingController(text: 'irc.chateamos.org');
  final port = TextEditingController(text: '6667');
  final nick = TextEditingController(text: 'JersIRC_User');
  final channel = TextEditingController(text: '#panama');
  final message = TextEditingController();
  final rooms = <String, ChatRoom>{};
  final chatScroll = ScrollController();
  StreamSubscription<IrcMessage>? subscription;
  Timer? reconnectTimer;
  Timer? blinkTimer;
  String? active;
  bool connected = false;
  bool connecting = false;
  bool secure = false;
  bool usersVisible = true;
  bool manualDisconnect = false;
  bool showSuggestions = false;
  bool blink = false;
  bool userHasScrolled = false;
  String status = 'Desconectado';

  ChatRoom get current => rooms[active] ?? ChatRoom(active ?? 'JersIRC');

  @override
  void initState() {
    super.initState();
    subscription = client.messages.listen(handleMessage);
    message.addListener(_onMessageChanged);
    chatScroll.addListener(() {
      if (!chatScroll.hasClients) return;
      final distance = chatScroll.position.maxScrollExtent - chatScroll.position.pixels;
      userHasScrolled = distance > 100;
    });
    blinkTimer = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (mounted && rooms.values.any((r) => r.privateChat && r.unread > 0)) {
        setState(() => blink = !blink);
      } else if (blink) {
        setState(() => blink = false);
      }
    });
  }

  void _onMessageChanged() {
    if (!mounted) return;
    final text = message.text;
    final match = RegExp(r'(^|\s)(\S*)$').firstMatch(text);
    final partial = match?.group(2) ?? '';
    final shouldShow = connected && active != null && partial.length >= 1 &&
        current.users.any((u) => u.toLowerCase().startsWith(partial.toLowerCase()));
    if (showSuggestions != shouldShow) setState(() => showSuggestions = shouldShow);
    // Mientras el usuario escribe, conservar siempre visible el último mensaje.
    _scrollToBottom(force: true);
  }

  List<String> get nickSuggestions {
    final text = message.text;
    final match = RegExp(r'(^|\s)(\S*)$').firstMatch(text);
    final partial = match?.group(2) ?? '';
    if (partial.isEmpty) return [];
    return current.users
        .where((u) => u.toLowerCase().startsWith(partial.toLowerCase()))
        .take(8)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !chatScroll.hasClients) return;
      if (!force && userHasScrolled) return;
      chatScroll.animateTo(
        chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void chooseNick(String user) {
    final text = message.text;
    final match = RegExp(r'(^|\s)(\S*)$').firstMatch(text);
    if (match == null) return;
    final prefix = text.substring(0, match.start + (match.group(1)?.length ?? 0));
    message.value = TextEditingValue(
      text: '$prefix$user ',
      selection: TextSelection.collapsed(offset: '$prefix$user '.length),
    );
    setState(() => showSuggestions = false);
  }

  String friendlyError(IrcMessage m) {
    switch (m.command) {
      case '422': return 'Sin MOTD (normal: el archivo de bienvenida del servidor no existe)';
      case '431': return 'Falta nickname';
      case '432': return 'Nickname no válido: ${m.trailing}';
      case '433': return 'Nickname en uso: ${m.trailing}';
      case '436': return 'Nickname en conflicto: ${m.trailing}';
      case '437': return 'Nickname/recurso no disponible: ${m.trailing}';
      case '451': return 'El servidor aún no considera registrada la conexión';
      case '464': return 'Contraseña incorrecta o requerida';
      case '465': return 'Conexión rechazada/bloqueada: ${m.trailing}';
      default: return 'IRC ${m.command}: ${m.trailing}';
    }
  }

  void handleMessage(IrcMessage m) {
    if (!mounted) return;
    setState(() {
      if (m.command == 'DISCONNECTED') {
        connected = false;
        if (!manualDisconnect) {
          connecting = false;
          status = 'Conexión perdida — reconectando...';
          _scheduleReconnect();
        } else {
          connecting = false;
          status = 'Desconectado';
        }
        return;
      }
      if (m.command == 'ERROR') {
        connected = false;
        connecting = false;
        status = m.trailing.isEmpty ? 'Error de conexión' : 'Error: ${m.trailing}';
        if (!manualDisconnect) _scheduleReconnect();
        return;
      }
      if (m.command == '001') status = 'Conectado';

      final numeric = int.tryParse(m.command);
      // 422 ERR_NOMOTD NO es un error de conexión. Se ignora para que no parezca
      // que JersIRC está fallando cuando el servidor simplemente no tiene MOTD.
      if (numeric != null && numeric >= 400 && numeric != 422) {
        status = friendlyError(m);
        if ({431, 432, 433, 436, 437, 451, 464, 465}.contains(numeric)) {
          connected = false;
          connecting = false;
          reconnectTimer?.cancel();
        }
      }

      if (m.command == 'JOIN' && m.params.isNotEmpty) {
        final name = m.params.last;
        final room = rooms.putIfAbsent(name, () => ChatRoom(name));
        if (m.nick != null) room.users.add(m.nick!);
        active ??= name;
      }
      if (m.command == 'PART' && m.params.isNotEmpty) {
        final room = rooms[m.params.first];
        if (room != null && m.nick != null) {
          room.users.remove(m.nick);
          room.modes.remove(m.nick);
        }
      }
      if (m.command == 'QUIT' && m.nick != null) {
        for (final room in rooms.values) {
          room.users.remove(m.nick);
          room.modes.remove(m.nick);
        }
      }
      if (m.command == 'NICK' && m.nick != null && m.params.isNotEmpty) {
        final oldNick = m.nick!;
        final newNick = m.params.last;
        for (final room in rooms.values) {
          if (room.users.remove(oldNick)) room.users.add(newNick);
          final mode = room.modes.remove(oldNick);
          if (mode != null) room.modes[newNick] = mode;
        }
      }
      if (m.command == 'KICK' && m.params.length >= 2) {
        rooms[m.params.first]?.users.remove(m.params[1]);
        rooms[m.params.first]?.modes.remove(m.params[1]);
      }
      if ((m.command == 'PRIVMSG' || m.command == 'NOTICE') && m.params.isNotEmpty) {
        final target = m.params.first;
        final isChannel = target.startsWith('#') || target.startsWith('&') || target.startsWith('+') || target.startsWith('!');
        final name = isChannel ? target : (m.nick ?? target);
        final room = rooms.putIfAbsent(name, () => ChatRoom(name, privateChat: !isChannel));
        room.messages.add(m);
        if (active != name) room.unread++;
        active ??= name;
        if (active == name) {
          room.unread = 0;
          userHasScrolled = false;
        }
        _scrollToBottom();
      }
      if (m.command == '353' && m.params.length >= 3) {
        final room = rooms.putIfAbsent(m.params[2], () => ChatRoom(m.params[2]));
        for (final rawUser in m.trailing.split(RegExp(r'\s+'))) {
          if (rawUser.isEmpty) continue;
          final prefixMatch = RegExp(r'^([~&@%+]+)(.+)$').firstMatch(rawUser);
          final prefix = prefixMatch?.group(1) ?? '';
          final user = prefixMatch?.group(2) ?? rawUser;
          if (user.isEmpty) continue;
          room.users.add(user);
          if (prefix.isNotEmpty) room.modes[user] = prefix;
        }
      }
      if (m.command == '366' && m.params.isNotEmpty) {
        final roomName = m.params.length > 1 ? m.params[1] : m.params.first;
        if (rooms.containsKey(roomName)) active ??= roomName;
      }
      if (m.command == 'MODE' && m.params.length >= 2) {
        final target = m.params.first;
        if (target.startsWith('#') && rooms.containsKey(target)) {
          final room = rooms[target]!;
          var adding = true;
          var arg = 2;
          for (final mode in m.params[1].split('')) {
            if (mode == '+') { adding = true; continue; }
            if (mode == '-') { adding = false; continue; }
            final needsNick = 'ovhqa'.contains(mode);
            if (needsNick && arg < m.params.length) {
              final user = m.params[arg++];
              var prefixes = room.modes[user] ?? '';
              const map = {'q': '~', 'a': '&', 'o': '@', 'h': '%', 'v': '+'};
              final p = map[mode];
              if (p != null) {
                if (adding && !prefixes.contains(p)) prefixes += p;
                if (!adding) prefixes = prefixes.replaceAll(p, '');
                if (prefixes.isEmpty) room.modes.remove(user); else room.modes[user] = prefixes;
              }
            }
          }
        }
      }
    });
  }

  Future<void> connect({bool automatic = false}) async {
    if (connecting || connected) return;
    reconnectTimer?.cancel();
    final server = host.text.trim();
    final nickname = nick.text.trim();
    final selectedPort = int.tryParse(port.text.trim()) ?? (secure ? 6697 : 6667);
    if (server.isEmpty || nickname.isEmpty) {
      setState(() => status = 'Servidor y nickname son obligatorios');
      return;
    }
    manualDisconnect = false;
    setState(() {
      connecting = true;
      connected = false;
      status = automatic ? 'Reconectando...' : 'Conectando...';
    });
    try {
      await client.connect(host: server, port: selectedPort, nickname: nickname, secure: secure);
      if (!mounted) return;
      setState(() {
        connected = true;
        connecting = false;
        status = 'Conectado';
      });
      final name = channel.text.trim();
      if (name.isNotEmpty) {
        rooms.putIfAbsent(name, () => ChatRoom(name));
        setState(() => active = name);
        client.join(name);
      }
    } catch (e) {
      if (mounted) {
        final text = e.toString().replaceFirst('StateError: ', '').replaceFirst('Exception: ', '');
        setState(() {
          connected = false;
          connecting = false;
          status = text;
        });
        if (!automatic && !manualDisconnect && !text.toLowerCase().contains('nickname en uso')) _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    if (manualDisconnect || connected || connecting) return;
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 5), () => connect(automatic: true));
  }

  Future<void> disconnect() async {
    manualDisconnect = true;
    reconnectTimer?.cancel();
    await client.disconnect();
    if (mounted) setState(() { connected = false; connecting = false; status = 'Desconectado'; });
  }

  void joinChannel() {
    final name = channel.text.trim();
    if (!connected || name.isEmpty) return;
    rooms.putIfAbsent(name, () => ChatRoom(name));
    setState(() { active = name; rooms[name]!.unread = 0; userHasScrolled = false; });
    client.join(name);
    _scrollToBottom(force: true);
  }

  void openPrivate(String user) {
    if (!connected || user.isEmpty) return;
    setState(() {
      rooms.putIfAbsent(user, () => ChatRoom(user, privateChat: true));
      active = user;
      rooms[user]!.unread = 0;
      userHasScrolled = false;
    });
    _scrollToBottom(force: true);
  }

  void closeRoom(String name) {
    final room = rooms[name];
    if (room == null) return;
    if (!room.privateChat && connected) client.part(name);
    final wasActive = active == name;
    rooms.remove(name);
    if (wasActive) {
      active = rooms.isEmpty ? null : rooms.keys.first;
      userHasScrolled = false;
    }
    setState(() {});
    _scrollToBottom(force: true);
  }

  void showUserActions(String user) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.alternate_email), title: Text('Mencionar @$user'), onTap: () {
          Navigator.pop(context);
          message.text = '${message.text}$user ';
          message.selection = TextSelection.collapsed(offset: message.text.length);
        }),
        ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('Privado'), onTap: () {
          Navigator.pop(context);
          openPrivate(user);
        }),
      ])),
    );
  }

  Color nickColor(String user) {
    var hash = 0;
    for (final c in user.codeUnits) hash = (hash * 31 + c) & 0x7fffffff;
    const colors = [
      Color(0xFF7CB8FF), Color(0xFFFFA6C9), Color(0xFFB9E986), Color(0xFFFFCC80),
      Color(0xFFC7A7FF), Color(0xFF72E0D1), Color(0xFFFF9E80), Color(0xFF9FA8DA),
    ];
    return colors[hash % colors.length];
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    blinkTimer?.cancel();
    subscription?.cancel();
    message.removeListener(_onMessageChanged);
    chatScroll.dispose();
    client.dispose();
    host.dispose();
    port.dispose();
    nick.dispose();
    channel.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF151B22),
          title: const Row(children: [Icon(Icons.forum_rounded, size: 22), SizedBox(width: 8), Text('JersIRC', style: TextStyle(fontWeight: FontWeight.w700))]),
          actions: [
            Padding(padding: const EdgeInsets.only(right: 8), child: Row(children: [
              Icon(Icons.circle, size: 9, color: connected ? const Color(0xFF8FB59B) : Colors.grey),
              const SizedBox(width: 6),
              SizedBox(width: 170, child: Text(status, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
            ])),
          ],
        ),
        drawer: buildDrawer(),
        body: Column(children: [
          if (rooms.isNotEmpty) buildTabs(),
          Expanded(child: Row(children: [Expanded(child: active == null ? buildWelcome() : buildChat()), if (active != null) buildUsers()])),
          buildComposer(),
        ]),
      );

  Widget buildTabs() {
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        children: rooms.values.map((room) {
          final selected = room.name == active;
          final hasUnread = room.unread > 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: selected ? const Color(0xFF53677D) : (room.privateChat && hasUnread && blink ? const Color(0xFF7A435C) : const Color(0xFF252D36)),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() { active = room.name; room.unread = 0; userHasScrolled = false; _scrollToBottom(force: true); }),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(room.privateChat ? Icons.person_outline : Icons.tag, size: 16),
                    const SizedBox(width: 5),
                    AnimatedOpacity(opacity: room.privateChat && hasUnread ? (blink ? 1 : .35) : 1, duration: const Duration(milliseconds: 120), child: Text(room.name)),
                    if (hasUnread) ...[
                      const SizedBox(width: 6),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.redAccent.withOpacity(.85), borderRadius: BorderRadius.circular(10)), child: Text('${room.unread}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    ],
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: 'Cerrar ${room.name}',
                      onPressed: () => closeRoom(room.name),
                      padding: const EdgeInsets.all(5),
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ]),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget buildDrawer() => Drawer(
        backgroundColor: const Color(0xFF151B22),
        child: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
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
            Expanded(child: TextField(controller: nick, decoration: const InputDecoration(labelText: 'Nickname'))),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('TLS / SSL'), subtitle: Text(secure ? 'Conexión cifrada' : 'Conexión normal'), value: secure, onChanged: connecting ? null : (value) => setState(() => secure = value)),
          const SizedBox(height: 4),
          FilledButton.icon(onPressed: connecting ? null : (connected ? disconnect : connect), icon: Icon(connected ? Icons.link_off : Icons.link), label: Text(connected ? 'Desconectar' : 'Conectar')),
          const Divider(height: 28, color: Colors.white12),
          const Text('UNIRSE A CANAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: TextField(controller: channel, decoration: const InputDecoration(hintText: '#panama'))), const SizedBox(width: 8), IconButton.filled(onPressed: connected ? joinChannel : null, icon: const Icon(Icons.add))]),
          const SizedBox(height: 28),
          Center(child: Text('UTF-8', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(.25), letterSpacing: 2))),
        ])),
      );

  Widget buildWelcome() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.forum_outlined, size: 62, color: Colors.white.withOpacity(.4)),
        const SizedBox(height: 14),
        const Text('Bienvenido a JersIRC', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Canal inicial: #panama', style: TextStyle(color: Colors.white54)),
      ]));

  Widget buildChat() {
    final items = current.messages;
    return Column(children: [
      if (!connected) Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: Colors.orange.withOpacity(.12), child: Text(status, style: const TextStyle(fontSize: 12))),
      Expanded(child: items.isEmpty
          ? Center(child: Text(current.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))
          : ListView.builder(
              controller: chatScroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              itemCount: items.length,
              itemBuilder: (_, index) {
                final item = items[index];
                final user = item.nick ?? 'Sistema';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: RichText(text: TextSpan(children: [
                    TextSpan(text: '$user  ', style: TextStyle(fontWeight: FontWeight.bold, color: nickColor(user))),
                    TextSpan(text: item.trailing, style: const TextStyle(color: Colors.white)),
                  ])),
                );
              },
            )),
    ]);
  }

  Widget buildUsers() {
    final users = current.users.toList()..sort();
    if (!usersVisible) {
      return GestureDetector(
        onHorizontalDragUpdate: (details) { if (details.delta.dx > 3) setState(() => usersVisible = true); },
        onTap: () => setState(() => usersVisible = true),
        child: Container(width: 42, decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(left: BorderSide(color: Colors.white10))), child: const Center(child: Icon(Icons.people_alt_outlined, size: 21))),
      );
    }
    return GestureDetector(
      onHorizontalDragEnd: (details) { if ((details.primaryVelocity ?? 0) < -150) setState(() => usersVisible = false); },
      child: Container(
        width: 155,
        decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(left: BorderSide(color: Colors.white10))),
        child: ListView(padding: const EdgeInsets.all(8), children: [
          Row(children: [const Expanded(child: Text('USUARIOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54))), IconButton(tooltip: 'Ocultar usuarios', onPressed: () => setState(() => usersVisible = false), icon: const Icon(Icons.keyboard_double_arrow_right, size: 20))]),
          const SizedBox(height: 4),
          ...users.map((user) {
            final prefix = current.modes[user] ?? '';
            return ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 2), leading: Text(prefix.isEmpty ? '•' : prefix, style: TextStyle(fontWeight: FontWeight.bold, color: nickColor(user))), title: Text(user, overflow: TextOverflow.ellipsis, style: TextStyle(color: nickColor(user), fontWeight: FontWeight.w600)), onTap: () => showUserActions(user));
          }),
        ]),
      ),
    );
  }

  Widget buildComposer() {
    final suggestions = nickSuggestions;
    return SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (showSuggestions && suggestions.isNotEmpty)
          Align(alignment: Alignment.centerLeft, child: Card(child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 180), child: ListView(shrinkWrap: true, children: suggestions.map((user) => ListTile(dense: true, leading: Text(current.modes[user] ?? '•'), title: Text(user, style: TextStyle(color: nickColor(user))), onTap: () => chooseNick(user))).toList())))),
        Row(children: [
          Expanded(child: TextField(
            controller: message,
            enabled: connected && active != null,
            onTap: () => _scrollToBottom(force: true),
            onSubmitted: (_) => sendMessage(),
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(hintText: connected ? 'Escribe un mensaje o /comando' : 'Reconectando...'),
          )),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: connected && active != null ? sendMessage : null, icon: const Icon(Icons.send_rounded)),
        ]),
      ]),
    ));
  }

  void sendMessage() {
    final text = message.text.trim();
    final target = active;
    if (!connected || target == null || text.isEmpty) return;
    if (text.startsWith('/')) {
      sendCommand(text.substring(1));
    } else {
      client.message(target, text);
      rooms[target]!.messages.add(IrcMessage(':${nick.text}!local@local', nick.text, 'PRIVMSG', [target, text]));
      userHasScrolled = false;
      setState(() {});
      _scrollToBottom(force: true);
    }
    message.clear();
  }

  void sendCommand(String command) {
    final parts = command.split(RegExp(r'\s+'));
    if (parts.isEmpty) return;
    final name = parts.first.toLowerCase();
    if (name == 'join' && parts.length > 1) {
      channel.text = parts[1];
      joinChannel();
    } else if (name == 'part' && active != null) {
      closeRoom(active!);
    } else if (name == 'nick' && parts.length > 1) {
      nick.text = parts[1];
      client.changeNick(parts[1]);
    } else if (name == 'msg' && parts.length > 2) {
      final user = parts[1];
      final text = parts.sublist(2).join(' ');
      openPrivate(user);
      client.message(user, text);
      rooms[user]!.messages.add(IrcMessage(':${nick.text}!local@local', nick.text, 'PRIVMSG', [user, text]));
      setState(() {});
      _scrollToBottom(force: true);
    } else {
      client.send(command);
    }
  }
}
