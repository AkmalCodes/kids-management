import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/shared/widgets/app_icon.dart';

void main() {
  SvgPicture svgOf(WidgetTester tester) =>
      tester.widget<SvgPicture>(find.byType(SvgPicture));
  String assetOf(WidgetTester tester) =>
      (svgOf(tester).bytesLoader as SvgAssetLoader).assetName;

  testWidgets('picks the outline file by default, filled when asked',
      (tester) async {
    await tester.pumpWidget(const Center(child: AppIcon(AppIcons.schedule)));
    expect(assetOf(tester), 'assets/icons/schedule_outline.svg');

    await tester.pumpWidget(
        const Center(child: AppIcon(AppIcons.schedule, filled: true)));
    expect(assetOf(tester), 'assets/icons/schedule_filled.svg');
  });

  testWidgets('takes size and colour from the surrounding IconTheme, like Icon',
      (tester) async {
    await tester.pumpWidget(
      const Center(
        child: IconTheme(
          data: IconThemeData(size: 20, color: Color(0xFF123456)),
          child: AppIcon(AppIcons.people),
        ),
      ),
    );

    final svg = svgOf(tester);
    expect(svg.width, 20);
    expect(svg.height, 20);
    expect(
      svg.colorFilter,
      const ColorFilter.mode(Color(0xFF123456), BlendMode.srcIn),
    );
  });

  test('every icon has both files on disk', () {
    // Guards against a typo'd or missing export from Figma.
    for (final icon in AppIcons.values) {
      for (final style in ['outline', 'filled']) {
        expect(
          File('assets/icons/${icon.name}_$style.svg').existsSync(),
          isTrue,
          reason: '${icon.name}_$style.svg',
        );
      }
    }
  });
}
