import 'dart:io';

import 'package:flutter/services.dart';

import '../photo_metadata.dart';

class ImportedFile {
  const ImportedFile(this.path, this.name);
  final String path, name;
  factory ImportedFile.fromMap(Map<Object?, Object?> value) =>
      ImportedFile(value['path'] as String, value['name'] as String);
}

class AndroidNormalizedPhoto {
  const AndroidNormalizedPhoto(this.file, this.metadata, this.icc);
  final File file;
  final PhotoMetadata metadata;
  final Uint8List icc;
}

class AndroidPlatform {
  static const channel = MethodChannel('local.photoframe/android');

  Future<Map<String, String>> paths() async =>
      Map<String, String>.from((await channel.invokeMethod<Map>('paths'))!);

  Future<ImportedFile?> pickPhoto() => _pick('pickPhoto');
  Future<ImportedFile?> pickZip() => _pick('pickZip');
  Future<ImportedFile?> _pick(String method) async {
    final value = await channel.invokeMethod<Map>(method);
    return value == null ? null : ImportedFile.fromMap(value);
  }

  Future<AndroidNormalizedPhoto> normalize(String path) async {
    final result = (await channel.invokeMethod<Map>('normalizeFile', {
      'path': path,
    }))!;
    final props = Map<String, dynamic>.from(result['metadata'] as Map);
    String text(String key) =>
        PhotoMetadata.cleanText(props[key]?.toString() ?? '');
    double? number(String key) {
      final value = props[key];
      return value is num && value.isFinite && value > 0
          ? value.toDouble()
          : null;
    }

    return AndroidNormalizedPhoto(
      File(result['path'] as String),
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

  Future<Map?> nextIncoming() => channel.invokeMethod<Map>('nextIncoming');
  Future<Map<String, String>> save(File file, String name) async =>
      Map<String, String>.from(
        (await channel.invokeMethod<Map>('save', {
          'path': file.path,
          'name': name,
        }))!,
      );
  Future<void> share(File file, String name) =>
      channel.invokeMethod<void>('share', {'path': file.path, 'name': name});
  Future<void> copyExif(File original, File jpeg) => channel.invokeMethod<void>(
    'copyExif',
    {'original': original.path, 'jpeg': jpeg.path},
  );
  Future<void> open(String uri) =>
      channel.invokeMethod<void>('open', {'uri': uri});
}
