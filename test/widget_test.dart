import 'package:flutter_test/flutter_test.dart';
import 'package:tsuki_player/main.dart';

void main() {
  testWidgets('Tsuki Player renders', (tester) async {
    await tester.pumpWidget(const TsukiPlayerApp());

    expect(find.text('TSUKI PLAYER'), findsOneWidget);
  });
}
