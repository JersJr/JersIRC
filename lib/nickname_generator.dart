import 'dart:math';

class NicknameGenerator {
  static final Random _random = Random.secure();

  static String generate() {
    final prefix = _random.nextBool() ? 'LC' : 'CFS';
    final number = _random.nextInt(10000).toString().padLeft(4, '0');
    return '$prefix-$number';
  }
}
