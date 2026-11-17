import 'package:flutter/services.dart';

import 'photo_metadata.dart';

class NativePhoto {
  const NativePhoto(this.png, this.metadata, this.icc);
  final Uint8List png;
  final PhotoMetadata metadata;
  final Uint8List icc;
  static const channel = MethodChannel('local.photoframe/image');

  static Future<Uint8List> copyExifWithoutGps(
    Uint8List original,
    Uint8List jpeg,
  ) async {
    final result = await channel.invokeMethod<Uint8List>('copyExifWithoutGps', {
      'original': original,
      'jpeg': jpeg,
    });
    if (result == null) throw const FormatException('撮影情報を保存できません。');
    return result;
  }

  static Future<NativePhoto> normalize(Uint8List source) async {
    final result = await channel
        .invokeMapMethod<String, dynamic>('normalize', source)
        .timeout(const Duration(seconds: 60));
    if (result == null ||
        result['png'] is! Uint8List ||
        result['icc'] is! Uint8List) {
      throw const FormatException('写真を読み込めません。');
    }
    final props = Map<String, dynamic>.from(result['metadata'] as Map);
    double? number(String key) {
      final v = props[key];
      return v is num && v.isFinite && v > 0 ? v.toDouble() : null;
    }

    String text(String key) =>
        PhotoMetadata.cleanText(props[key]?.toString() ?? '');
    return NativePhoto(
      result['png'] as Uint8List,
      PhotoMetadata(
        cameraMaker: text('make'),
        cameraModel: text('model'),
        lensMaker: text('lensMake'),
        lensModel: text('lensModel'),
        focalLength: number('focal'),
        focalLength35: number('focal35'),
        fNumber: number('aperture'),
        exposureTime: number('exposure'),
        iso: number('iso'),
      ),
      result['icc'] as Uint8List,
    );
  }
}
