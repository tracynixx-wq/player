import 'package:flutter_test/flutter_test.dart';
import 'package:player/main.dart';

void main() {
  testWidgets('PLAYER home screen renders', (tester) async {
    await tester.pumpWidget(const PlayerApp());
    expect(find.text('PLAYER'), findsOneWidget);
    expect(find.text('Слушай то,'), findsOneWidget);
  });
}
