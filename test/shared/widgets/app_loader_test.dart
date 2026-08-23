import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/shared/widgets/app_loader.dart';

void main() {
  Future<void> pumpLoader(WidgetTester tester, {bool delayed = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: AppLoader(delayed: delayed))),
        ),
      );

  testWidgets('delayed loader stays invisible immediately after mounting',
      (tester) async {
    await pumpLoader(tester);

    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 0.0);

    // Flush the pending debounce timer so it doesn't leak past teardown.
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('delayed loader becomes visible after the debounce window',
      (tester) async {
    await pumpLoader(tester);

    // Just under the 250ms debounce: still hidden.
    await tester.pump(const Duration(milliseconds: 200));
    var opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 0.0);

    // Past the debounce: now visible.
    await tester.pump(const Duration(milliseconds: 100));
    opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 1.0);
  });

  testWidgets('delayed: false skips the debounce and shows immediately',
      (tester) async {
    await pumpLoader(tester, delayed: false);

    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 1.0);
  });

  testWidgets('renders a themed CircularProgressIndicator sized to widget.size',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: AppLoader(delayed: false, size: 20)),
        ),
      ),
    );

    final sizedBox = tester.widget<SizedBox>(
      find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(SizedBox),
      ).first,
    );
    expect(sizedBox.width, 20);
    expect(sizedBox.height, 20);
  });
}
