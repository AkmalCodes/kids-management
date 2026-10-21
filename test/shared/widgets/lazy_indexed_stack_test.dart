import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/shared/widgets/lazy_indexed_stack.dart';

// A page that counts how often its State is created, to prove pages are
// kept alive instead of rebuilt on every tab switch.
int created = 0;

class _Counted extends StatefulWidget {
  const _Counted(this.label);
  final String label;
  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    created++;
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

Widget _app(int index) => MaterialApp(
      home: LazyIndexedStack(
        index: index,
        children: const [_Counted('A'), _Counted('B'), _Counted('C')],
      ),
    );

void main() {
  setUp(() => created = 0);

  testWidgets('only builds the visible page at first', (tester) async {
    await tester.pumpWidget(_app(0));

    expect(created, 1);
    // skipOffstage: false also finds pages that exist but are hidden.
    expect(find.text('B', skipOffstage: false), findsNothing);
  });

  testWidgets('keeps visited pages alive when switching back', (tester) async {
    await tester.pumpWidget(_app(0));
    await tester.pumpWidget(_app(1));
    await tester.pumpWidget(_app(0));
    await tester.pumpWidget(_app(1));

    // A and B each created once; C never visited, never built.
    expect(created, 2);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing); // hidden, but still alive offstage
    expect(find.text('A', skipOffstage: false), findsOneWidget);
    expect(find.text('C', skipOffstage: false), findsNothing);
  });
}
