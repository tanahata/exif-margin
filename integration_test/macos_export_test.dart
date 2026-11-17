import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photo_frame/main.dart';
import 'package:photo_frame/src/gear_dictionary.dart';
import 'package:photo_frame/src/photo_metadata.dart';

class _Picker extends FileSelectorPlatform {
  _Picker(this.source);
  final String source;
  FileSaveLocation? destination;
  SaveDialogOptions? lastOptions;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile(source);

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    lastOptions = options;
    return destination;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Macで換算値を補って保存しても撮影EXIFと元写真を保持する', (tester) async {
    final folder = await Directory.systemTemp.createTemp('exif-margin-mac-');
    addTearDown(() => folder.delete(recursive: true));
    final config = await GearConfiguration.load(
      Directory('${folder.path}/config'),
    );
    final image = img.Image(width: 2200, height: 1100);
    image.exif.imageIfd['Make'] = 'SHARP';
    image.exif.imageIfd['Model'] = 'A504SH';
    image.exif.exifIfd['FocalLength'] = img.IfdValueRational(1538, 100);
    image.exif.gpsIfd['GPSLatitudeRef'] = 'N';
    image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational.list([
      img.IfdValueRational(35, 1).toRational(),
      img.IfdValueRational(0, 1).toRational(),
      img.IfdValueRational(0, 1).toRational(),
    ]);
    final original = img.encodeJpg(image);
    final source = File('${folder.path}/sample.jpg');
    await source.writeAsBytes(original);
    final picker = _Picker(source.path);
    final previous = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = previous);

    await tester.pumpWidget(PhotoFrameApp(configuration: config));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写真を選ぶ'));
    await tester.pumpAndSettle();
    final mode = find.byKey(const ValueKey('focal_mode'));
    await tester.ensureVisible(mode);
    await tester.tap(find.text('35mm換算').last);
    await tester.pumpAndSettle();
    final input = find.byKey(const Key('manual_equivalent'));
    expect(input, findsOneWidget);
    await tester.enterText(input, '65');
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('edit_focal')))
          .controller!
          .text,
      '65mm eq.',
    );

    await tester.tap(find.byKey(const ValueKey('save_hq')));
    await tester.pumpAndSettle();
    expect(picker.lastOptions!.initialDirectory, folder.path);
    expect(picker.lastOptions!.suggestedName, 'sample_frame_HQ.jpg');

    final output = File('${folder.path}/result.jpg');
    picker.destination = FileSaveLocation(output.path);
    await tester.tap(find.byKey(const ValueKey('save_sns')));
    await tester.pumpAndSettle();
    expect(picker.lastOptions!.suggestedName, 'sample_frame_SNS.jpg');
    final exported = img.decodeJpg(await output.readAsBytes())!;
    final metadata = PhotoMetadata.fromExif(exported.exif);
    expect(exported.width, 2048);
    expect(exported.exif.gpsIfd.isEmpty, isTrue);
    expect(metadata.focalLength, closeTo(15.38, 0.001));
    expect(metadata.focalLength35, isNull);
    expect(await source.readAsBytes(), orderedEquals(original));
  });
}
