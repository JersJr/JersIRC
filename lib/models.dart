class SavedServer {
  final String name;
  final String host;
  final int port;
  final String nickname;
  final bool tls;
  final List<String> channels;

  const SavedServer({required this.name, required this.host, required this.port, required this.nickname, this.tls = true, this.channels = const []});

  Map<String, dynamic> toJson() => {'name': name, 'host': host, 'port': port, 'nickname': nickname, 'tls': tls, 'channels': channels};
  factory SavedServer.fromJson(Map<String, dynamic> j) => SavedServer(
    name: j['name'] as String? ?? 'Servidor', host: j['host'] as String? ?? '',
    port: (j['port'] as num?)?.toInt() ?? 6697, nickname: j['nickname'] as String? ?? 'JersIRC_User',
    tls: j['tls'] as bool? ?? true, channels: (j['channels'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );
}
