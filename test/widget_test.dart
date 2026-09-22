import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tsuki_player/main.dart';
import 'package:tsuki_player/widgets/retro_marquee.dart';

void main() {
  testWidgets('Tsuki Player renders', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    await tester.pumpWidget(const TsukiPlayerApp());

    expect(find.text('TSUKI PLAYER'), findsOneWidget);
  });

  testWidgets('RetroMarquee animates long text sem exceção', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            child: RetroMarquee(
              text: 'Summer Jam 2003 (DJ F.R.A.N.K.\'s Summermix Short)',
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}