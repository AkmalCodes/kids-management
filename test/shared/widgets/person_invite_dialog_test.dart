import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/shared/widgets/person_invite_dialog.dart';

// A button that opens the dialog and stashes the result, so tests can pump
// a real widget tree (showDialog needs a Navigator/MaterialApp context).
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  PersonInviteResult? result;
  bool opened = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              final r = await showPersonInviteDialog(context, title: 'Invite a teacher');
              setState(() {
                result = r;
                opened = true;
              });
            },
            child: const Text('Open'),
          ),
          Text(!opened ? 'no result' : (result == null ? 'null result' : 'has result')),
          if (result != null) ...[
            Text('name:${result!.name}'),
            Text('email:${result!.email}'),
            Text('phone:${result!.phone}'),
          ],
        ],
      ),
    );
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: _Harness()));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the given title and empty fields', (tester) async {
    await _open(tester);

    expect(find.text('Invite a teacher'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Phone (optional)'), findsOneWidget);
  });

  testWidgets('blocks submit when name or email is missing', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a name'), findsOneWidget);
    expect(find.text('Please enter an email'), findsOneWidget);
    expect(find.text('no result'), findsOneWidget);
  });

  testWidgets('blocks submit when email has no @', (tester) async {
    await _open(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Jane Doe');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  testWidgets('returns the entered values on submit', (tester) async {
    await _open(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Jane Doe');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'jane@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone (optional)'), '555-1234');
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();

    expect(find.text('name:Jane Doe'), findsOneWidget);
    expect(find.text('email:jane@example.com'), findsOneWidget);
    expect(find.text('phone:555-1234'), findsOneWidget);
  });

  testWidgets('returns null on cancel', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('null result'), findsOneWidget);
  });
}
