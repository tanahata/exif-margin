import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS declares Japanese for system file dialogs', () {
    final plist = File('macos/Runner/Info.plist').readAsStringSync();
    final localizations = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>([\s\S]*?)</array>',
    ).firstMatch(plist);

    expect(localizations, isNotNull);
    expect(localizations!.group(1), contains('<string>ja</string>'));
    expect(localizations.group(1), contains('<string>en</string>'));
  });
}
