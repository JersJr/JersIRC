import 'package:flutter_test/flutter_test.dart';
import 'package:jersirc/main.dart';

void main() {
  testWidgets('Parloteo opens on the redesigned welcome screen', (tester) async {
    await tester.pumpWidget(const JersIrcApp());

    expect(find.text('Bienvenido a Parloteo'), findsOneWidget);
    expect(find.text('Entrar a Parloteo'), findsOneWidget);
    expect(find.text('Servidor'), findsNothing);
    expect(find.text('Puerto'), findsNothing);
    expect(find.text('TLS / SSL'), findsNothing);
  });
}
