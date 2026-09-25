# JersIRC

Cliente IRC moderno para Android, construido con Flutter.

## Estado actual

- Cliente IRC TCP/TLS real con registro y PING/PONG.
- Reconexión automática.
- Canales, usuarios, privados, modos e ignorados.
- Perfiles de servidor persistentes con SharedPreferences.
- Parser y modelos separados.
- `IrcController` desacoplado de la interfaz.
- `HomeScreen` separado de `main.dart`.
- Pruebas unitarias del parser y modelos.
- APK generado mediante GitHub Actions.

## Arquitectura

```text
lib/
├── main.dart
├── irc_client.dart
├── models.dart
├── storage.dart
├── controllers/
│   └── irc_controller.dart
├── screens/
│   └── home_screen.dart
├── models/
│   ├── chat_room.dart
│   ├── irc_message.dart
│   ├── irc_server.dart
│   └── irc_user.dart
└── services/
    └── irc_parser.dart
```

`main.dart` ahora solo inicializa la aplicación. La conexión, eventos y estado IRC viven en `IrcController`, mientras que la interfaz vive en `HomeScreen`.

## Próximas mejoras

- Separar componentes de UI en `widgets/`.
- Selector visual de múltiples servidores/perfiles.
- SASL y capacidades IRCv3.
- Historial persistente de mensajes.
- Notificaciones Android.
- Ciclo de vida/background.
- Pruebas de integración contra servidores IRC.
