class IrcMessage {
  final String raw;
  final String? prefix;
  final String command;
  final List<String> params;

  const IrcMessage(this.raw, this.prefix, this.command, this.params);

  String get trailing => params.isEmpty ? '' : params.last;

  String? get nick {
    final value = prefix;
    if (value == null || value.isEmpty) return null;
    return value.split('!').first;
  }
}
