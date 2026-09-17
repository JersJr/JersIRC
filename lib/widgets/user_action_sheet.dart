import 'package:flutter/material.dart';

class UserActionSheet extends StatelessWidget {
  const UserActionSheet({
    super.key,
    required this.nickname,
    required this.isIgnored,
    required this.onPrivate,
    required this.onWhois,
    required this.onIgnore,
    required this.onMode,
  });

  final String nickname;
  final bool isIgnored;
  final VoidCallback onPrivate;
  final VoidCallback onWhois;
  final VoidCallback onIgnore;
  final void Function(String mode) onMode;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(nickname, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Acciones IRC'),
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('Mensaje privado'),
            onTap: () {
              Navigator.pop(context);
              onPrivate();
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('WHOIS'),
            onTap: () {
              Navigator.pop(context);
              onWhois();
            },
          ),
          ListTile(
            leading: Icon(isIgnored ? Icons.visibility : Icons.visibility_off),
            title: Text(isIgnored ? 'Dejar de ignorar' : 'Ignorar usuario'),
            onTap: () {
              Navigator.pop(context);
              onIgnore();
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Dar OP (@)'),
            onTap: () {
              Navigator.pop(context);
              onMode('+o');
            },
          ),
          ListTile(
            leading: const Icon(Icons.remove_moderator_outlined),
            title: const Text('Quitar OP (@)'),
            onTap: () {
              Navigator.pop(context);
              onMode('-o');
            },
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Dar VOICE (+)'),
            onTap: () {
              Navigator.pop(context);
              onMode('+v');
            },
          ),
          ListTile(
            leading: const Icon(Icons.voice_over_off_outlined),
            title: const Text('Quitar VOICE (+)'),
            onTap: () {
              Navigator.pop(context);
              onMode('-v');
            },
          ),
        ],
      ),
    );
  }
}
