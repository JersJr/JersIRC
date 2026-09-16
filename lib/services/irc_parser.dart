import '../irc_client.dart';

/// Parser for one IRC protocol line.
///
/// Kept independent from sockets so it can be unit-tested without a network
/// connection and reused by the connection layer later.
class IrcParser {
  const IrcParser();

  IrcMessage parse(String raw) {
    var line = raw;
    String? prefix;

    if (line.startsWith(':')) {
      final space = line.indexOf(' ');
      if (space > 0) {
        prefix = line.substring(1, space);
        line = line.substring(space + 1);
      }
    }

    final parts = <String>[];
    while (line.isNotEmpty) {
      line = line.trimLeft();
      if (line.isEmpty) break;

      if (line.startsWith(':')) {
        parts.add(line.substring(1));
        break;
      }

      final space = line.indexOf(' ');
      if (space < 0) {
        parts.add(line);
        break;
      }

      parts.add(line.substring(0, space));
      line = line.substring(space + 1);
    }

    final command = parts.isEmpty ? '' : parts.removeAt(0).toUpperCase();
    return IrcMessage(raw, prefix, command, parts);
  }
}
