import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'src/gear_dictionary.dart';
import 'src/public_edition.dart';
import 'src/app_theme.dart';
import 'src/android/android_frame_page.dart';
import 'src/macos/mac_frame_page.dart';

// Preserve the public entry point used by existing tests and integrations.
export 'src/macos/mac_frame_page.dart' show PhotoFrameApp, FramePage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Share Tech Mono',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Share Tech',
    ], await rootBundle.loadString('assets/fonts/ShareTech-OFL.txt'));
  });
  if (Platform.isAndroid) {
    runApp(
      MaterialApp(
        title: 'EXIF Margin',
        debugShowCheckedModeBanner: false,
        // The original personal APK retains its previous platform theme.
        theme: kPublicTextOnly ? yamabukiAppTheme(Brightness.light) : null,
        darkTheme: kPublicTextOnly ? yamabukiAppTheme(Brightness.dark) : null,
        themeMode: kPublicTextOnly ? ThemeMode.system : ThemeMode.light,
        home: const AndroidFramePage(),
      ),
    );
    return;
  }
  GearConfiguration? configuration;
  String? warning;
  try {
    final profile = Platform.environment['HOME'];
    if (profile == null) throw const FileSystemException('ホームフォルダを確認できません。');
    configuration = await GearConfiguration.load(
      Directory(
        p.join(
          profile,
          'Library',
          'Application Support',
          kPublicTextOnly ? 'EXIFMargin' : 'PhotoFrame',
        ),
      ),
    );
  } catch (_) {
    warning = '設定フォルダを読み込めません。EXIFと標準設定を使用します。';
  }
  runApp(
    PhotoFrameApp(configuration: configuration, configurationWarning: warning),
  );
}
