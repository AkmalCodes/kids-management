import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/features/teacher/widgets/grid_person_tile.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String name,
  Widget? badge,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 84,
            height: 117,
            child: GridPersonTile(
              avatar: const ColoredBox(color: Colors.blue),
              name: name,
              badge: badge,
              onTap: onTap ?? () {},
              onLongPress: onLongPress,
            ),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('renders the shortened one-line name label', (tester) async {
    await _pump(tester, name: 'Ammar Ali Hassan');
    expect(find.text('Ammar H.'), findsOneWidget);
    expect(find.text('Ammar Ali Hassan'), findsNothing);
  });

  testWidgets('avatar slot is the same size for a short and a long name',
      (tester) async {
    await _pump(tester, name: 'Al');
    final short = tester.getSize(find.byType(AspectRatio));
    await _pump(tester, name: 'Muhammad Aariz Danish bin Abdul Rahman');
    final long = tester.getSize(find.byType(AspectRatio));
    expect(long, short);
  });

  testWidgets('renders the badge when given, omits it when null', (tester) async {
    await _pump(tester, name: 'Al', badge: const Icon(Icons.star, key: Key('b')));
    expect(find.byKey(const Key('b')), findsOneWidget);
    await _pump(tester, name: 'Al');
    expect(find.byKey(const Key('b')), findsNothing);
  });

  testWidgets('tap and long-press fire their callbacks', (tester) async {
    var taps = 0;
    var longs = 0;
    await _pump(tester, name: 'Al', onTap: () => taps++, onLongPress: () => longs++);
    await tester.tap(find.byType(GridPersonTile));
    await tester.pump();
    await tester.longPress(find.byType(GridPersonTile));
    await tester.pump();
    expect(taps, 1);
    expect(longs, 1);
  });
}
