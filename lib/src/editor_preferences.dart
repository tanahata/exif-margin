import 'dart:convert';
import 'dart:io';

import 'frame.dart';
import 'caption_sizes.dart';
export 'caption_sizes.dart';
import 'photo_metadata.dart';

const editorDefaultMargins = FrameMargins();

/// Personal editor choices, separate from the portable equipment dictionary.
class EditorPreferences {
  EditorPreferences(this.file);
  final File file;
  FrameMargins margins = editorDefaultMargins;
  CaptionSizes sizes = const CaptionSizes();
  OutputMode outputMode = OutputMode.hq;
  final Map<String, Map<String, String>> names = {};
  Future<void> _writes = Future.value();

  static String? key(String kind, String maker, String model) {
    if (model.trim().isEmpty) return null;
    String clean(String s) =>
        s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return jsonEncode([kind, clean(maker), clean(model)]);
  }

  Future<void> load() async {
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString());
    if (data is! Map ||
        ![1, 2, 3, 4].contains(data['schemaVersion']) ||
        data['names'] is! Map) {
      throw const FormatException('記憶した設定を読み込めません。');
    }
    final raw = data['margins'];
    if (raw is! List ||
        raw.length != 3 ||
        raw.any((v) => v is! num || !v.isFinite)) {
      throw const FormatException('余白の設定が正しくありません。');
    }
    final parsed = FrameMargins(
      side: (raw[0] as num).toDouble(),
      top: (raw[1] as num).toDouble(),
      bottom: (raw[2] as num).toDouble(),
    );
    parsed.validate();
    final text =
            (data['schemaVersion'] == 4
                ? data['leftScale']
                : data['textScale']) ??
            1,
        logo =
            (data['schemaVersion'] == 4
                ? data['rightScale']
                : data['logoScale']) ??
            1;
    if (text is! num || logo is! num) {
      throw const FormatException('文字・ロゴの設定が正しくありません。');
    }
    final parsedSizes = CaptionSizes(
      left: text.toDouble(),
      right: logo.toDouble(),
    );
    parsedSizes.validate();
    final next = <String, Map<String, String>>{};
    for (final entry in (data['names'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('記憶した名前が正しくありません。');
      }
      final values = Map<String, String>.from(entry.value as Map);
      if (values.keys.any(
            (k) => ![
              'cameraMaker',
              'cameraModel',
              'lensMaker',
              'lensModel',
            ].contains(k),
          ) ||
          values.values.any((v) => v.length > 120)) {
        throw const FormatException('記憶した名前が正しくありません。');
      }
      next[entry.key as String] = values;
    }
    margins =
        data['schemaVersion'] == 1 &&
            parsed.side == .06 &&
            parsed.top == .06 &&
            parsed.bottom == .30
        ? editorDefaultMargins
        : parsed;
    // The new 100% reference is shared by all three text roles.
    sizes = data['schemaVersion'] == 4 ? parsedSizes : const CaptionSizes();
    outputMode = data['outputMode'] == 'sns' ? OutputMode.sns : OutputMode.hq;
    names
      ..clear()
      ..addAll(next);
    if (data['schemaVersion'] != 4) await save();
  }

  Map<String, String> overrides(PhotoMetadata original) => {
    ...?names[key('camera', original.cameraMaker, original.cameraModel)],
    ...?names[key('lens', original.lensMaker, original.lensModel)],
  };

  void remember(PhotoMetadata original, PhotoMetadata edited) {
    for (final camera in [true, false]) {
      final id = key(
        camera ? 'camera' : 'lens',
        camera ? original.cameraMaker : original.lensMaker,
        camera ? original.cameraModel : original.lensModel,
      );
      if (id == null) continue;
      final fields = camera
          ? ['cameraMaker', 'cameraModel']
          : ['lensMaker', 'lensModel'];
      final values = <String, String>{
        for (final field in fields)
          if (edited.overrides.containsKey(field))
            field: PhotoMetadata.cleanText(edited.overrides[field]!),
      };
      if (values.isEmpty) {
        names.remove(id);
      } else {
        names[id] = values;
      }
    }
  }

  Future<void> save() {
    final contents = jsonEncode({
      'schemaVersion': 4,
      'margins': [margins.side, margins.top, margins.bottom],
      'names': names,
      'outputMode': outputMode.name,
      'leftScale': sizes.left,
      'rightScale': sizes.right,
    });
    final next = _writes.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(contents, flush: true);
      await temp.rename(file.path);
    });
    _writes = next;
    return next;
  }
}
