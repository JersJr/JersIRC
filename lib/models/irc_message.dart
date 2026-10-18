class IrcMessage {
  final String raw;
  final String? prefix;
  final String command;
  final List<String> params;
  final DateTime? timestamp;

  const IrcMessage(this.raw, this.prefix, this.command, this.params, {this.timestamp});

  String get trailing => params.isEmpty ? '' : params.last;

  String? get nick {
    final value = prefix;
    if (value == null || value.isEmpty) return null;
    // Los controles de formato IRC nunca deben aparecer en el nickname visible.
    return value
        .split('!')
        .first
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();
  }
}
