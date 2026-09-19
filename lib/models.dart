export 'models/chat_room.dart';
export 'models/irc_message.dart';
export 'models/irc_server.dart';
export 'models/irc_user.dart';

/// Persisted server profile used by the storage layer.
class SavedServer {
  final String name;
  final String host;
  final int port;
  final String nickname;
  final bool tls;
  final List<String> channels;

  const SavedServer({
    required this.name,
    required this.host,
    required this.port,
    required this.nickname,
    this.tls = true,
    this.channels = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'nickname': nickname,
        'tls': tls,
        'channels': channels,
      };

  factory SavedServer.fromJson(Map<String, dynamic> json) => SavedServer(
        name: json['name'] as String? ?? 'Servidor',
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 6697,
        nickname: json['nickname'] as String? ?? 'JersIRC_User',
        tls: json['tls'] as bool? ?? true,
        channels: (json['channels'] as List?)
                ?.map((item) => item.toString())
                .toList() ??
            const [],
      );
}
