import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/theme/app_theme.dart';
import 'package:kawankecil/shared/widgets/app_bottom_nav.dart';

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

  // The label reveal is an Align with widthFactor 0..1 inside a ClipRect:
  // 0 = fully tucked behind the icon, 1 = fully slid out.
  double revealOf(WidgetTester tester, String label) => tester
      .widget<Align>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Align))
            .first,
      )
      .widthFactor!;

  testWidgets('only the selected tab shows its label', (tester) async {
    await pumpNav(tester, selectedIndex: 0);

    expect(revealOf(tester, 'Home'), 1);
    expect(revealOf(tester, 'Settings'), 0);
  });

  testWidgets('label slides out after selecting a tab', (tester) async {
    await pumpNav(tester, selectedIndex: 0);
    await pumpNav(tester, selectedIndex: 1);

    // Mid-animation: Settings partly out, Home partly tucked away.
    await tester.pump(const Duration(milliseconds: 100));
    expect(revealOf(tester, 'Settings'), inExclusiveRange(0, 1));
    expect(revealOf(tester, 'Home'), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(revealOf(tester, 'Settings'), 1);
    expect(revealOf(tester, 'Home'), 0);
  });

  testWidgets('5 tabs on a 360px phone never overflow, even mid-animation',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Same tabs as the director shell; "Attendance" is the longest label.
    Future<void> pumpAt(int i) => tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: AppBottomNav(
                selectedIndex: i,
                onDestinationSelected: (_) {},
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.people), label: 'People'),
                  NavigationDestination(icon: Icon(Icons.event), label: 'Schedule'),
                  NavigationDestination(icon: Icon(Icons.book), label: 'Lessons'),
                  NavigationDestination(icon: Icon(Icons.check), label: 'Attendance'),
                  NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
                ],
              ),
            ),
          ),
        );

    await pumpAt(0);
    await pumpAt(3);
    await tester.pump(const Duration(milliseconds: 90));
    // Interrupt the animation with another tap's worth of change.
    await pumpAt(4);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.pumpAndSettle();
    // A RenderFlex overflow would have been reported as an exception.
    expect(tester.takeException(), isNull);
    expect(revealOf(tester, 'Profile'), 1);
  });

  testWidgets('selected tab is wider than an unselected one', (tester) async {
    // Phone width. On the default 800px test screen two tabs already get
    // 390px each, more than either needs, so both would stay equal.
    tester.view.physicalSize = const Size(180, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpNav(tester, selectedIndex: 1);

    final items = find.byType(GestureDetector);
    expect(
      tester.getSize(items.at(1)).width,
      greaterThan(tester.getSize(items.at(0)).width),
    );
  });
}
