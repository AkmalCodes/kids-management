import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/theme/app_theme.dart';
import 'package:kids_management/shared/widgets/app_bottom_nav.dart';

void main() {
  Future<void> pumpNav(WidgetTester tester, {int selectedIndex = 0}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: AppBottomNav(
              selectedIndex: selectedIndex,
              onDestinationSelected: (_) {},
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      );

  testWidgets('bar Material colour is AppTheme.barTint',
      (tester) async {
    await pumpNav(tester);

    // Find the Material inside ClipRRect (the nav's main Material)
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(ClipRRect),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, AppTheme.barTint);
  });

  testWidgets('sliding highlight DecoratedBox colour is scheme.primary',
      (tester) async {
    await pumpNav(tester);

    // Find the inner DecoratedBox (the animated highlight pill)
    // within AnimatedPositioned for the highlight
    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(AnimatedPositioned),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.color, AppTheme.seed);
  });


  testWidgets('tapping an item fires onDestinationSelected callback',
      (tester) async {
    int? tappedIndex;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: AppBottomNav(
            selectedIndex: 0,
            onDestinationSelected: (index) => tappedIndex = index,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );

    // Tap the second item
    await tester.tap(find.byType(GestureDetector).at(1));
    await tester.pumpAndSettle();

    expect(tappedIndex, 1);
  });

  testWidgets('highlight animates when selectedIndex changes',
      (tester) async {
    await pumpNav(tester, selectedIndex: 0);

    // Get initial position of highlight
    var positioned = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    var initialLeft = positioned.left;

    // Update to second item
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: AppBottomNav(
            selectedIndex: 1,
            onDestinationSelected: (_) {},
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );

    // Verify position changed
    positioned = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    expect(positioned.left, isNot(initialLeft));
  });

  testWidgets('selected item label is onAccent, unselected is onSurfaceVariant',
      (tester) async {
    await pumpNav(tester, selectedIndex: 0);

    // AppBottomNav renders its own _NavItem widgets (not NavigationDestination);
    // each label's colour lives on the AnimatedDefaultTextStyle wrapping the Text.
    // .first = the closest ancestor (Material also wraps content in one).
    TextStyle styleFor(String label) => tester
        .widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        )
        .style;

    expect(styleFor('Home').color, AppTheme.onAccent); // selected
    expect(styleFor('Settings').color, AppTheme.light.colorScheme.onSurfaceVariant);
  });
}
