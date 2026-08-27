import 'package:flutter/material.dart';

void main() {
  runApp(const JersIrcApp());
}

class JersIrcApp extends StatelessWidget {
  const JersIrcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JersIRC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JersIRC'),
        actions: [
          IconButton(
            tooltip: 'Agregar servidor',
            onPressed: () => _showAddServer(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.public)),
              title: const Text('Servidores IRC'),
              subtitle: const Text('Todavía no hay servidores configurados'),
              trailing: FilledButton(
                onPressed: () => _showAddServer(context),
                child: const Text('Agregar'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'JersIRC',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cliente IRC moderno para Android. Esta primera versión prepara la interfaz para conectar servidores, canales y mensajes privados.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }

  void _showAddServer(BuildContext context) {
    final host = TextEditingController(text: 'irc.libera.chat');
    final port = TextEditingController(text: '6697');
    final nick = TextEditingController(text: 'JersIRC_User');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Agregar servidor', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: host, decoration: const InputDecoration(labelText: 'Servidor', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puerto', border: OutlineInputBorder()))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: nick, decoration: const InputDecoration(labelText: 'Nickname', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Servidor ${host.text}:${port.text} preparado para ${nick.text}')),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Guardar servidor'),
            ),
          ],
        ),
      ),
    );
  }
}
