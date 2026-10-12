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
    required this.onTemporaryBan,
  });

  final String nickname;
  final bool isIgnored;
  final bool isOperator;
  final VoidCallback onPrivate, onWhois, onIgnore, onMention, onBanNick, onBanHost, onTemporaryBan;
  final void Function(String mode) onMode;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.86),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(nickname, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Text('Acciones IRC', style: TextStyle(fontSize: 11)),
            ),
            ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('Mensaje privado', style: TextStyle(fontSize: 13)), onTap: () { Navigator.pop(context); onPrivate(); }),
            ListTile(leading: const Icon(Icons.alternate_email), title: const Text('Mencionar', style: TextStyle(fontSize: 13)), onTap: () { Navigator.pop(context); onMention(); }),
            ListTile(leading: Icon(isIgnored ? Icons.visibility : Icons.visibility_off), title: Text(isIgnored ? 'Dejar de ignorar' : 'Ignorar', style: const TextStyle(fontSize: 13)), onTap: () { Navigator.pop(context); onIgnore(); }),
            if (isOperator) ...[
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.info_outline), title: const Text('WHOIS', style: TextStyle(fontSize: 13)), onTap: () { Navigator.pop(context); onWhois(); }),
              ListTile(leading: const Icon(Icons.volume_off_outlined), title: const Text('Silenciar (ban temporal)', style: TextStyle(fontSize: 13)), subtitle: const Text('Define la duración en minutos', style: TextStyle(fontSize: 10)), onTap: () { Navigator.pop(context); onTemporaryBan(); }),
              ListTile(leading: const Icon(Icons.gavel_outlined), title: const Text('Kick + Ban por nick', style: TextStyle(fontSize: 13)), subtitle: const Text('Banea y expulsa con motivo editable', style: TextStyle(fontSize: 10)), onTap: () { Navigator.pop(context); onBanNick(); }),
              ListTile(leading: const Icon(Icons.shield_outlined), title: const Text('Kick + Ban por IP virtual', style: TextStyle(fontSize: 13)), subtitle: const Text('Consulta WHOIS y aplica la máscara de host disponible', style: TextStyle(fontSize: 10)), onTap: () { Navigator.pop(context); onBanHost(); }),
              ExpansionTile(
                dense: true,
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Rango y modos', style: TextStyle(fontSize: 13)),
                children: [
                  ListTile(leading: const Icon(Icons.arrow_upward), title: const Text('Dar OP (@)', style: TextStyle(fontSize: 13)), onTap: () { Navigator.pop(context); onMode('+o'); }),
                  ListTile(leading: const Icon(Icons.arrow_downward), title: const Text('Quitar OP (@)', style: TextStyle(fontSize: 13)), onTap: () { Navigator.pop(context); onMode('-o'); }),
                  ListTile(leading: const Icon(Icons.record_voice_over_outlined), title: const Text('Dar voz (+v)', style: TextStyle(fontSize: 13)), onTap: () { Navigator.pop(context); onMode('+v'); }),
                  ListTile(leading: const Icon(Icons.voice_over_off_outlined), title: const Text('Quitar voz (+v)', style: TextStyle(fontSize: 13)), onTap: () { Navigator.pop(context); onMode('-v'); }),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
