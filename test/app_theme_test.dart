import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_frame/src/app_theme.dart';
import 'package:photo_frame/src/public_edition.dart';
import 'package:photo_frame/src/macos/mac_frame_page.dart';

/// WCAG 2.2 contrast calculation for fully opaque UI colors.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  test('ブランド山吹色の白文字は使わず濃色文字を使う', () {
    expect(contrastRatio(YamabukiColors.brand, Colors.white), lessThan(4.5));
    expect(
      contrastRatio(YamabukiColors.brand, YamabukiColors.lightOnSurface),
      greaterThanOrEqualTo(4.5),
    );
  });

  for (final brightness in Brightness.values) {
    test('山吹色テーマの文字・UI境界はAA相当を確保: $brightness', () {
      final theme = yamabukiAppTheme(brightness);
      final colors = theme.colorScheme;
      final textPairs = <(String, Color, Color)>[
        ('primary button', colors.onPrimary, colors.primary),
        ('primary text', colors.primary, colors.surface),
        ('secondary button', colors.onSecondary, colors.secondary),
        (
          'primary container',
          colors.onPrimaryContainer,
          colors.primaryContainer,
        ),
        (
          'secondary container',
          colors.onSecondaryContainer,
          colors.secondaryContainer,
        ),
        ('body text', colors.onSurface, colors.surface),
      ];
      for (final (name, text, background) in textPairs) {
        expect(
          contrastRatio(text, background),
          greaterThanOrEqualTo(4.5),
          reason: '$name: $brightness',
        );
      }
      // Controls, outlines and focus indicators must not rely on color alone.
      expect(
        contrastRatio(colors.outline, colors.surface),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contrastRatio(colors.outlineVariant, colors.surface),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        colors.error,
        isNot(colors.primary),
        reason: 'Error is a semantic color, not a brand accent',
      );
      expect(theme.scaffoldBackgroundColor, colors.surface);
      expect(theme.brightness, brightness);
    });
  }

  testWidgets('公開版だけ山吹色、個人用Photo Frameは従来テーマ', (tester) async {
    await tester.pumpWidget(const PhotoFrameApp());
    final context = tester.element(find.byType(FramePage));
    final primary = Theme.of(context).colorScheme.primary;
    if (kPublicTextOnly) {
      expect(primary, YamabukiColors.lightPrimary);
    } else {
      expect(primary, isNot(YamabukiColors.lightPrimary));
    }
  });
}
