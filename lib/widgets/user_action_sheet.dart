import 'package:flutter/material.dart';

class UserActionSheet extends StatelessWidget {
  const UserActionSheet({
    super.key,
    required this.nickname,
    required this.isIgnored,
    required this.isOperator,
    required this.onPrivate,
    required this.onWhois,
    required this.onIgnore,
    required this.onMention,
    required this.onMode,
    required this.onBanNick,
    required this.onBanHost,
  });

  final String nickname;
  final bool isIgnored;
  final bool isOperator;
  final VoidCallback onPrivate, onWhois, onIgnore, onMention, onBanNick, onBanHost;
  final void Function(String mode) onMode;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Wrap(children: [
      ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(nickname, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Acciones IRC'),
      ),
      ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('Mensaje privado'), onTap: () { Navigator.pop(context); onPrivate(); }),
      ListTile(leading: const Icon(Icons.alternate_email), title: const Text('Mencionar'), onTap: () { Navigator.pop(context); onMention(); }),
      ListTile(leading: Icon(isIgnored ? Icons.visibility : Icons.visibility_off), title: Text(isIgnored ? 'Dejar de ignorar' : 'Ignorar'), onTap: () { Navigator.pop(context); onIgnore(); }),
      if (isOperator) ...[
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.info_outline), title: const Text('WHOIS'), onTap: () { Navigator.pop(context); onWhois(); }),
        ListTile(leading: const Icon(Icons.person_off_outlined), title: const Text('Banear nick'), subtitle: const Text('Bloqueo por máscara de nick en esta sala'), onTap: () { Navigator.pop(context); onBanNick(); }),
        ListTile(leading: const Icon(Icons.shield_outlined), title: const Text('Banear IP virtual'), subtitle: const Text('Consulta WHOIS y aplica la máscara de host disponible'), onTap: () { Navigator.pop(context); onBanHost(); }),
        ExpansionTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Rango y modos'),
          children: [
            ListTile(leading: const Icon(Icons.arrow_upward), title: const Text('Dar OP (@)'), onTap: () { Navigator.pop(context); onMode('+o'); }),
            ListTile(leading: const Icon(Icons.arrow_downward), title: const Text('Quitar OP (@)'), onTap: () { Navigator.pop(context); onMode('-o'); }),
            ListTile(leading: const Icon(Icons.record_voice_over_outlined), title: const Text('Dar voz (+v)'), onTap: () { Navigator.pop(context); onMode('+v'); }),
            ListTile(leading: const Icon(Icons.voice_over_off_outlined), title: const Text('Quitar voz (+v)'), onTap: () { Navigator.pop(context); onMode('-v'); }),
          ],
        ),
      ],
    ]),
  );
}
