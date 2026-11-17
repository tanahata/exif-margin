import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/jpeg_profile.dart';

List<(int, Uint8List)> markers(Uint8List bytes) {
  final result = <(int, Uint8List)>[];
  var i = 2;
  while (i + 4 <= bytes.length) {
    expect(bytes[i++], 255);
    final code = bytes[i++];
    if (code == 0xda || code == 0xd9) break;
    final size = bytes[i] * 256 + bytes[i + 1];
    result.add((code, Uint8List.sublistView(bytes, i + 2, i + size)));
    i += size;
  }
  return result;
}

void main() {
  test('実出力のSOFでHQ/SNSとも4:2:0、ICC保持・元EXIF除去を検証', () {
    final source = img.decodePng(
      File('test/fixtures/srgb.png').readAsBytesSync(),
    )!;
    source.exif.imageIfd['Make'] = 'PRIVATE CAMERA';
    final encoded = img.encodeJpg(source);
    final icc = source.iccProfile!.decompressed();
    for (final mode in OutputMode.values) {
      final encodedOutput = renderExport(
        ExportRequest(encoded, mode: mode, iccProfile: icc),
      );
      final bytes = standardizeJpegIcc(encodedOutput, icc);
      final segments = markers(bytes);
      expect(
        img.decodeJpg(bytes)!.getPixel(2, 2).toString(),
        img.decodeJpg(encodedOutput)!.getPixel(2, 2).toString(),
      );
      expect(
        segments.where((s) => s.$1 != 0xe2).map((s) => s.$2.toList()).toList(),
        markers(encodedOutput)
            .where((s) => s.$1 != 0xe2)
            .map((s) => s.$2.toList())
            .toList(),
      );
      final sof = segments.singleWhere((s) => s.$1 == 0xc0).$2;
      final reference = img.encodeJpg(
        source,
        quality: mode == OutputMode.hq ? 95 : 90,
        chroma: img.JpegChroma.yuv420,
      );
      expect(
        segments.where((s) => s.$1 == 0xdb).map((s) => s.$2.toList()).toList(),
        markers(reference)
            .where((s) => s.$1 == 0xdb)
            .map((s) => s.$2.toList())
            .toList(),
      );
      expect(sof[5], 3);
      expect([sof[7], sof[10], sof[13]], [0x22, 0x11, 0x11]);
      expect(segments.where((s) => s.$1 == 0xe1), isEmpty);
      final profiles = segments
          .where((s) => s.$1 == 0xe2)
          .map((s) => s.$2)
          .toList();
      expect(profiles, hasLength(1));
      expect(profiles.first.sublist(12, 14), [1, 1]);
      expect(profiles.first.sublist(14), icc);
      expect(String.fromCharCodes(profiles.first.sublist(30, 34)), 'RGB ');
      expect(String.fromCharCodes(profiles.first.take(11)), 'ICC_PROFILE');
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.exif.imageIfd['Make'], isNull);
    }
  });
}
