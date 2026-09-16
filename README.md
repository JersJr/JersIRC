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

🟢 Controlador IRC separado para estado de conexión, salas y eventos

🟢 Persistencia local de perfiles de servidor con `SharedPreferences`

🟢 Parser IRC separado y probado sin red

🟢 Pruebas unitarias del parser y del controlador

🟢 Generación automática de APK mediante GitHub Actions

## Arquitectura

```text
lib/
├── main.dart                    # punto de entrada + UI existente
├── irc_client.dart              # transporte TCP/TLS + eventos IRC
├── models.dart                  # export público de modelos
├── storage.dart                 # persistencia local
├── controllers/
│   └── irc_controller.dart      # estado y lógica IRC independiente de la UI
├── models/
│   ├── chat_room.dart
│   ├── irc_message.dart
│   ├── irc_server.dart
│   └── irc_user.dart
└── services/
    └── irc_parser.dart          # parser independiente y testeable
```

La refactorización se está realizando por etapas para no romper la interfaz existente. `IrcController` ya concentra la lógica de conexión, reconexión, salas, usuarios, mensajes privados, ignorados y modos de usuario; la pantalla actual puede migrarse a este controlador en la siguiente etapa sin cambiar el transporte IRC.

## Próxima etapa

- Conectar `IrcHomePage` directamente a `IrcController`.
- Separar la pantalla principal en `screens/` y componentes reutilizables en `widgets/`.
- Conectar la UI directamente al modelo `IrcServer` y `JersStorage`.
- Soporte para múltiples perfiles/servidores desde la interfaz.
- SASL y capacidades IRCv3.
- Historial persistente de mensajes.
- Notificaciones Android.
- Mejoras de ciclo de vida/background en Android.
- Pruebas de integración de conexión contra servidores IRC de prueba.
