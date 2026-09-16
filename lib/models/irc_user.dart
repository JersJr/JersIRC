class IrcUser {
  String nick;
  String prefixes;

  IrcUser(this.nick, {this.prefixes = ''});

  bool get isOwner => prefixes.contains('~');
  bool get isAdmin => prefixes.contains('&');
  bool get isOp => prefixes.contains('@');
  bool get isHalfOp => prefixes.contains('%');
  bool get hasVoice => prefixes.contains('+');

  IrcUser copyWith({String? nick, String? prefixes}) => IrcUser(
        nick ?? this.nick,
        prefixes: prefixes ?? this.prefixes,
      );
}
