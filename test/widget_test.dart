import 'package:flutter_test/flutter_test.dart';
import 'package:jersirc/main.dart';

void main() {
  testWidgets('JersIRC opens', (tester) async {
    await tester.pumpWidget(const JersIrcApp());
    expect(find.text('JersIRC'), findsWidgets);
    expect(find.text('Bienvenido a JersIRC'), findsOneWidget);
  });
}
