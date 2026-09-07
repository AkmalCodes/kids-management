import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/theme/app_theme.dart';

void main() {
  testWidgets('white is the base surface', (tester) async {
    final t = AppTheme.light;
    expect(t.scaffoldBackgroundColor, Colors.white);
    expect(t.colorScheme.surface, Colors.white);
  });

  testWidgets('soft pink is the primary accent', (tester) async {
    final t = AppTheme.light;
    expect(t.colorScheme.primary, AppTheme.seed);
    expect(t.colorScheme.onPrimary, AppTheme.onAccent);
  });

  testWidgets('the bars carry the faint pink wash, not a filled pink', (tester) async {
    final t = AppTheme.light;
    expect(t.appBarTheme.backgroundColor, AppTheme.barTint);
    expect(t.navigationBarTheme.backgroundColor, AppTheme.barTint);
  });

  testWidgets('the selected nav indicator is the pink accent', (tester) async {
    final t = AppTheme.light;
    expect(t.navigationBarTheme.indicatorColor, AppTheme.seed);
  });
}
