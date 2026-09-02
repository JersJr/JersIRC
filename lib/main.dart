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
  final channel = TextEditingController(text: '#chateamos');
  final message = TextEditingController();
  final rooms = <String, ChatRoom>{};
  StreamSubscription<IrcMessage>? subscription;
  String? active;
  bool connected = false;
  bool connecting = false;
  bool secure = false;
  String status = 'Desconectado';

  ChatRoom get current => rooms[active] ?? ChatRoom(active ?? 'JersIRC');

  @override
  void initState() {
    super.initState();
    subscription = client.messages.listen(handleMessage);
  }

  String friendlyError(IrcMessage m) {
    switch (m.command) {
      case '431': return 'Falta nickname';
      case '432': return 'Nickname no válido: ${m.trailing}';
      case '433': return 'Nickname en uso: ${m.trailing}';
      case '436': return 'Nickname en conflicto: ${m.trailing}';
      case '437': return 'Nickname/recurso no disponible: ${m.trailing}';
      case '464': return 'Contraseña incorrecta o requerida';
      case '465': return 'Conexión rechazada/bloqueada: ${m.trailing}';
      case '451': return 'El servidor aún no considera registrada la conexión';
      default: return 'IRC ${m.command}: ${m.trailing}';
    }
  }

  void handleMessage(IrcMessage m) {
    if (!mounted) return;
    setState(() {
      if (m.command == 'DISCONNECTED') {
        connected = false;
        if (!connecting) status = 'Desconectado';
        return;
      }
      if (m.command == 'ERROR') {
        connected = false;
        connecting = false;
        status = m.trailing.isEmpty ? 'Error de conexión' : 'Error: ${m.trailing}';
        return;
      }
      if (m.command == '001') status = 'Conectado';

      final numeric = int.tryParse(m.command);
      if (numeric != null && numeric >= 400) {
        status = friendlyError(m);
        if ({431, 432, 433, 436, 437, 451, 464, 465}.contains(numeric)) {
          connected = false;
          connecting = false;
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
        if (room != null && m.nick != null) room.users.remove(m.nick);
      }
      if (m.command == 'QUIT' && m.nick != null) {
        for (final room in rooms.values) room.users.remove(m.nick);
      }
      if (m.command == 'NICK' && m.nick != null && m.params.isNotEmpty) {
        final oldNick = m.nick!;
        final newNick = m.params.last;
        for (final room in rooms.values) {
          if (room.users.remove(oldNick)) room.users.add(newNick);
        }
      }
      if (m.command == 'KICK' && m.params.length >= 2) {
        rooms[m.params.first]?.users.remove(m.params[1]);
      }
      if ((m.command == 'PRIVMSG' || m.command == 'NOTICE') && m.params.isNotEmpty) {
        final target = m.params.first;
        final isChannel = target.startsWith('#') || target.startsWith('&') || target.startsWith('+') || target.startsWith('!');
        final name = isChannel ? target : (m.nick ?? target);
        final room = rooms.putIfAbsent(name, () => ChatRoom(name, privateChat: !isChannel));
        room.messages.add(m);
        if (active != name) room.unread++;
        active ??= name;
      }
      if (m.command == '353' && m.params.length >= 3) {
        final room = rooms.putIfAbsent(m.params[2], () => ChatRoom(m.params[2]));
        for (final user in m.trailing.split(RegExp(r'\s+'))) {
          if (user.isNotEmpty) room.users.add(user.replaceFirst(RegExp(r'^[~&@%+]+'), ''));
        }
      }
      if (m.command == '366' && m.params.isNotEmpty) {
        final roomName = m.params.length > 1 ? m.params[1] : m.params.first;
        if (rooms.containsKey(roomName)) active ??= roomName;
      }
    });
  }

  Future<void> connect() async {
    if (connecting) return;
    final server = host.text.trim();
    final nickname = nick.text.trim();
    final selectedPort = int.tryParse(port.text.trim()) ?? (secure ? 6697 : 6667);
    if (server.isEmpty || nickname.isEmpty) {
      setState(() => status = 'Servidor y nickname son obligatorios');
      return;
    }
    setState(() {
      connecting = true;
      connected = false;
      status = 'Conectando...';
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
        var text = e.toString().replaceFirst('StateError: ', '').replaceFirst('Exception: ', '');
        setState(() {
          connected = false;
          connecting = false;
          status = text;
        });
      }
    }
  }

  Future<void> disconnect() async {
    await client.disconnect();
    if (mounted) setState(() {
      connected = false;
      connecting = false;
      status = 'Desconectado';
    });
  }

  void joinChannel() {
    final name = channel.text.trim();
    if (!connected || name.isEmpty) return;
    rooms.putIfAbsent(name, () => ChatRoom(name));
    setState(() => active = name);
    client.join(name);
  }

  void openPrivate(String user) {
    if (!connected || user.isEmpty) return;
    setState(() {
      rooms.putIfAbsent(user, () => ChatRoom(user, privateChat: true));
      active = user;
      rooms[user]!.unread = 0;
    });
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
      setState(() {});
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
      client.part(active!);
    } else if (name == 'nick' && parts.length > 1) {
      nick.text = parts[1];
      client.changeNick(parts[1]);
    } else if (name == 'msg' && parts.length > 2) {
      final user = parts[1];
      final text = parts.sublist(2).join(' ');
      openPrivate(user);
      client.message(user, text);
    } else {
      client.send(command);
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
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
          actions: [Padding(padding: const EdgeInsets.only(right: 14), child: Row(children: [Icon(Icons.circle, size: 9, color: connected ? const Color(0xFF8FB59B) : Colors.grey), const SizedBox(width: 6), SizedBox(width: 190, child: Text(status, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))]))],
        ),
        drawer: buildDrawer(),
        body: Column(children: [
          if (rooms.isNotEmpty) buildTabs(),
          Expanded(child: Row(children: [Expanded(child: active == null ? buildWelcome() : buildChat()), if (active != null) buildUsers()])),
          buildComposer(),
        ]),
      );

  Widget buildTabs() => SizedBox(height: 56, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7), children: rooms.values.map((room) => Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(room.privateChat ? Icons.person_outline : Icons.tag, size: 16), const SizedBox(width: 5), Text(room.name), if (room.unread > 0) ...[const SizedBox(width: 5), Text('${room.unread}')]]), selected: room.name == active, onSelected: (_) => setState(() { active = room.name; room.unread = 0; }))).toList()));

  Widget buildDrawer() => Drawer(backgroundColor: const Color(0xFF151B22), child: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
    const Center(child: Text('JersIRC', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
    const Center(child: Text('IRC, simple y claro', style: TextStyle(color: Colors.white54))),
    const SizedBox(height: 22),
    const Text('CONEXIÓN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
    const SizedBox(height: 10),
    TextField(controller: host, decoration: const InputDecoration(labelText: 'Servidor')),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puerto'))), const SizedBox(width: 8), Expanded(child: TextField(controller: nick, decoration: const InputDecoration(labelText: 'Nickname')))]),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('TLS / SSL'), subtitle: Text(secure ? 'Conexión cifrada' : 'Conexión normal'), value: secure, onChanged: connecting ? null : (value) => setState(() => secure = value)),
    const SizedBox(height: 4),
    FilledButton.icon(onPressed: connecting ? null : (connected ? disconnect : connect), icon: Icon(connected ? Icons.link_off : Icons.link), label: Text(connected ? 'Desconectar' : 'Conectar')),
    const Divider(height: 28, color: Colors.white12),
    const Text('UNIRSE A CANAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white54)),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: TextField(controller: channel, decoration: const InputDecoration(hintText: '#canal'))), const SizedBox(width: 8), IconButton.filled(onPressed: connected ? joinChannel : null, icon: const Icon(Icons.add))]),
    const SizedBox(height: 28),
    Center(child: Text('UTF-8', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(.25), letterSpacing: 2))),
  ])));

  Widget buildWelcome() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.forum_outlined, size: 62, color: Colors.white.withOpacity(.4)), const SizedBox(height: 14), const Text('Bienvenido a JersIRC', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 8), const Text('Configura servidor, puerto, TLS y nickname', style: TextStyle(color: Colors.white54))]));

  Widget buildChat() {
    final items = current.messages;
    if (items.isEmpty) return Center(child: Text(current.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)));
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (_, index) { final item = items[index]; return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: RichText(text: TextSpan(children: [TextSpan(text: '${item.nick ?? 'Sistema'}  ', style: const TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: item.trailing, style: const TextStyle(color: Colors.white))]))); });
  }

  Widget buildUsers() { final users = current.users.toList()..sort(); return Container(width: 135, decoration: const BoxDecoration(color: Color(0xFF151B22), border: Border(left: BorderSide(color: Colors.white10))), child: ListView(padding: const EdgeInsets.all(10), children: [const Text('USUARIOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54)), const SizedBox(height: 8), ...users.map((user) => ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_outline, size: 16), title: Text(user, overflow: TextOverflow.ellipsis), onTap: () => openPrivate(user))) ]); }

  Widget buildComposer() => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 10), child: Row(children: [Expanded(child: TextField(controller: message, enabled: connected && active != null, onSubmitted: (_) => sendMessage(), decoration: InputDecoration(hintText: connected ? 'Escribe un mensaje o /comando' : 'Conecta un servidor para chatear', prefixIcon: const Icon(Icons.chat_bubble_outline, size: 19), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18))))), const SizedBox(width: 8), IconButton.filled(onPressed: connected && active != null ? sendMessage : null, icon: const Icon(Icons.send_rounded))])));
}
