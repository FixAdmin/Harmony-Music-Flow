import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/player_control.dart';

void main() {
  Widget controls(double width) {
    const button = SizedBox.square(dimension: 48);
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const ResponsivePlayerTransportControls(
              flowButton: button,
              dislikeButton: button,
              shuffleButton: button,
              previousButton: button,
              playButton: SizedBox.square(dimension: 70),
              nextButton: button,
              loopButton: button,
            ),
          ),
        ),
      ),
    );
  }

  for (final width in [310.0, 287.0]) {
    testWidgets('transport controls do not overflow at width $width',
        (tester) async {
      await tester.pumpWidget(controls(width));

      expect(tester.takeException(), isNull);
      expect(find.byType(Column), findsOneWidget);
    });
  }

  testWidgets('wide transport controls stay in one row', (tester) async {
    await tester.pumpWidget(controls(500));

    expect(tester.takeException(), isNull);
    expect(find.byType(Column), findsNothing);
  });
}
