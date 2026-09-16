# JersIRC

Cliente IRC moderno para Android, construido con Flutter.

## Objetivo

JersIRC busca ofrecer una experiencia IRC moderna con soporte para múltiples servidores, canales, mensajes privados, SSL/TLS, historial y notificaciones.

## Estado actual

🟢 Interfaz Flutter funcional

🟢 Cliente IRC TCP/TLS real

🟢 Registro IRC y espera de `001 Welcome`

🟢 Respuesta automática a `PING/PONG`

🟢 Reconexión automática desde la interfaz

🟢 Canales y lista de usuarios

🟢 Mensajes privados

🟢 Autocompletado de usuarios

🟢 Ignorar usuarios

🟢 Modelos separados para servidores, usuarios, salas y mensajes

🟢 Persistencia local de perfiles de servidor con `SharedPreferences`

🟢 Parser IRC separado y probado sin red

🟢 Generación automática de APK mediante GitHub Actions

## Arquitectura

```text
lib/
├── main.dart                    # UI actual
├── irc_client.dart              # transporte TCP/TLS + eventos IRC
├── models.dart                  # export público de modelos
├── storage.dart                 # persistencia local
├── models/
│   ├── chat_room.dart
│   ├── irc_message.dart
│   ├── irc_server.dart
│   └── irc_user.dart
└── services/
    └── irc_parser.dart          # parser independiente y testeable
```

La refactorización mantiene la compatibilidad con la UI existente: `IrcMessage` sigue disponible desde `irc_client.dart`, mientras que su implementación vive ahora en la capa de modelos.

## Próxima etapa

- Conectar la UI directamente al modelo `IrcServer` y `JersStorage`.
- Separar el controlador de estado de la pantalla principal.
- Soporte para múltiples perfiles/servidores desde la interfaz.
- SASL y capacidades IRCv3.
- Historial persistente de mensajes.
- Notificaciones Android.
- Mejoras de ciclo de vida/background en Android.
- Pruebas de integración de conexión contra servidores IRC de prueba.
