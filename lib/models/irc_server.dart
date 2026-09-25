class IrcServer {
  final String name;
  final String host;
  final int port;
  final String nickname;
  final String? username;
  final bool tls;
  final List<String> channels;

  const IrcServer({
    required this.name,
    required this.host,
    required this.port,
    required this.nickname,
    this.username,
    this.tls = true,
    this.channels = const [],
  });

  IrcServer copyWith({
    String? name,
    String? host,
    int? port,
    String? nickname,
    String? username,
    bool? tls,
    List<String>? channels,
  }) => IrcServer(
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        nickname: nickname ?? this.nickname,
        username: username ?? this.username,
        tls: tls ?? this.tls,
        channels: channels ?? this.channels,
      );
}
