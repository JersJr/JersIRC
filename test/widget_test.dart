import 'package:flutter_test/flutter_test.dart';
import 'package:jersirc/main.dart';

void main() {
  testWidgets('JersIRC opens in WebChat mode', (tester) async {
    await tester.pumpWidget(const JersIrcApp());

    expect(find.text('Escoja su Nick'), findsOneWidget);
    expect(find.text('Entrar al chat'), findsOneWidget);
    expect(find.text('Servidor'), findsNothing);
    expect(find.text('Puerto'), findsNothing);
    expect(find.text('TLS / SSL'), findsNothing);
  });
}
