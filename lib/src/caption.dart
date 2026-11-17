import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'frame.dart';
import 'photo_metadata.dart';
import 'display_settings.dart';
import 'logo_store.dart';
import 'public_edition.dart';

class CaptionPart {
  const CaptionPart(this.text, this.logo, this.bounds, [this.fontSize]);
  final String text;
  final LogoAsset? logo;
  final double? fontSize;
  final ui.Rect bounds;
}

class CaptionLine {
  const CaptionLine(
    this.text,
    this.fontSize,
    this.bounds,
    this.role, [
    this.parts = const [],
  ]);
  final String text, role;
  final double fontSize;
  final ui.Rect bounds;
  final List<CaptionPart> parts;
}

TextPainter _painter(
  String text,
  double size, {
  double maxWidth = double.infinity,
  ui.Color color = const ui.Color(0xff000000),
}) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      fontFamily: 'ShareTech',
      color: color,
      fontSize: size,
      height: 1.2,
    ),
  ),
  textDirection: ui.TextDirection.ltr,
  maxLines: 1,
  ellipsis: '…',
)..layout(maxWidth: maxWidth);

List<CaptionLine> layoutCaption(
  PhotoMetadata metadata,
  FrameGeometry geometry, {
  DisplaySettings settings = const DisplaySettings(),
  Map<String, LogoAsset> logos = const {},
}) {
  final s = math.min(geometry.photoWidth, geometry.photoHeight).toDouble();
  final fontBasis = settings.typographyUsesPhotoWidth
      ? geometry.photoWidth.toDouble()
      : s;
  final gap = s * .006, gutter = s * .04;
  final columnWidth = (geometry.photoWidth - gutter) / 2;
  final bottom = math.max(
    0.0,
    geometry.bottom - s * settings.bottomOffsetScale,
  );
  final result = <CaptionLine>[];
  CaptionLine? text(
    String value,
    String short,
    double fontSize,
    String role, {
    bool omit = false,
  }) {
    if (value.isEmpty) return null;
    var chosen = value;
    var p = _painter(chosen, fontSize);
    if (p.width > columnWidth && short.isNotEmpty) {
      p.dispose();
      chosen = short;
      p = _painter(chosen, fontSize);
    }
    final ratio = math.min(1.0, columnWidth / math.max(1, p.width));
    p.dispose();
    if (omit && ratio < .65) return null;
    final size = fontSize * math.max(.65, ratio);
    p = _painter(chosen, size, maxWidth: columnWidth);
    final line = CaptionLine(
      chosen,
      size,
      ui.Rect.fromLTWH(0, 0, p.width, p.height),
      role,
    );
    p.dispose();
    return line;
  }

  CaptionLine? item(
    String value,
    String short,
    String logoName,
    double size,
    String role, {
    bool omit = false,
    double? targetHeight,
    double logoScale = 1,
  }) {
    final logo = logos[logoName];
    if (logo == null) {
      // The bundled Share Tech's OS/2 cap height is 700 / 1000 em.
      // Use the visible capital height, excluding line spacing, to match the logo.
      final cameraText = role == 'cameraMaker' || role == 'cameraModel';
      final textSize = cameraText
          ? (settings.cameraGlyphHeightScale != null
                    ? fontBasis * settings.cameraGlyphHeightScale!
                    : (targetHeight ?? fontBasis * settings.logoHeightScale)) /
                .7
          : size;
      return text(value, short, textSize, role, omit: omit);
    }
    final ratio = math.min(
      (targetHeight ?? fontBasis * settings.logoHeightScale) *
          logoScale /
          logo.size.height,
      fontBasis * settings.logoMaxWidthScale * logoScale / logo.size.width,
    );
    final width = math.min(columnWidth, logo.size.width * ratio);
    final height = width * logo.size.height / logo.size.width;
    return CaptionLine('', size, ui.Rect.fromLTWH(0, 0, width, height), role, [
      CaptionPart('', logo, ui.Rect.fromLTWH(0, 0, width, height)),
    ]);
  }

  void group(List<CaptionLine?> candidates, bool right) {
    final rows = candidates.whereType<CaptionLine>().toList();
    final total =
        rows.fold<double>(0, (sum, row) => sum + row.bounds.height) +
        math.max(0, rows.length - 1) * gap;
    final scale = total == 0 ? 1.0 : math.min(1.0, bottom / total);
    var y = bottom - total * scale;
    for (final row in rows) {
      final width = row.bounds.width * scale,
          height = row.bounds.height * scale;
      final x = right
          ? geometry.side + geometry.photoWidth - width
          : geometry.side.toDouble();
      result.add(
        CaptionLine(
          row.text,
          row.fontSize * scale,
          ui.Rect.fromLTWH(x, y, width, height),
          row.role,
          row.parts
              .map(
                (part) => CaptionPart(
                  part.text,
                  part.logo,
                  ui.Rect.fromLTWH(
                    part.bounds.left * scale,
                    part.bounds.top * scale,
                    part.bounds.width * scale,
                    part.bounds.height * scale,
                  ),
                  part.fontSize == null ? null : part.fontSize! * scale,
                ),
              )
              .toList(),
        ),
      );
      y += height + gap * scale;
    }
  }

  CaptionLine? camera() {
    if (metadata.overrides.containsKey('camera')) {
      return text(
        metadata.camera,
        metadata.overrides.containsKey('camera')
            ? ''
            : metadata.cameraShortDisplay,
        fontBasis * settings.cameraTextScale * .9,
        'camera',
      );
    }
    final combinedLogo =
        metadata.cameraModelLogoIncludesMaker &&
        !metadata.overrides.containsKey('cameraModel') &&
        logos[metadata.cameraModelLogo] != null;
    final maker = combinedLogo
        ? null
        : item(
            metadata.cameraMakerText,
            '',
            metadata.overrides.containsKey('cameraMaker')
                ? ''
                : metadata.cameraMakerLogo,
            fontBasis * settings.cameraTextScale,
            'cameraMaker',
            logoScale: metadata.cameraMakerLogoScale,
          );
    final customModelText =
        maker != null &&
        maker.parts.isNotEmpty &&
        maker.parts.first.logo != null &&
        !metadata.editedCamera &&
        metadata.cameraModelTextWithLogo.isNotEmpty;
    var model = item(
      customModelText
          ? metadata.cameraModelTextWithLogo
          : metadata.cameraDisplayModel,
      customModelText || metadata.editedCamera
          ? ''
          : PhotoMetadata.withoutMaker(
              metadata.cameraMakerText,
              metadata.cameraShort,
            ),
      metadata.overrides.containsKey('cameraModel')
          ? ''
          : metadata.cameraModelLogo,
      fontBasis * settings.cameraTextScale,
      'cameraModel',
      targetHeight: fontBasis * settings.logoHeightScale,
      logoScale: metadata.cameraModelLogoScale,
    );
    final rows = [maker, model].whereType<CaptionLine>().toList();
    if (rows.length == 2 && rows.every((row) => row.parts.isEmpty)) {
      final commonSize = rows.map((row) => row.fontSize).reduce(math.min);
      for (var i = 0; i < rows.length; i++) {
        rows[i] = text(rows[i].text, '', commonSize, rows[i].role)!;
      }
    }

    if (rows.isEmpty) return null;
    var width =
        rows.fold<double>(0, (sum, row) => sum + row.bounds.width) +
        math.max(0, rows.length - 1) * s * .01;
    final scale = math.min(1.0, columnWidth / width);
    final height =
        rows
            .map(
              (row) =>
                  row.parts.isEmpty ? row.fontSize * .7 : row.bounds.height,
            )
            .reduce(math.max) *
        scale;
    var x = 0.0;
    final parts = <CaptionPart>[];
    for (final row in rows) {
      final logo = row.parts.isEmpty ? null : row.parts.first.logo;
      var visibleBottom = row.bounds.height;
      if (logo == null) {
        final painter = _painter(
          row.text,
          row.fontSize,
          maxWidth: row.bounds.width,
        );
        visibleBottom = painter.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        painter.dispose();
      }
      final w = row.bounds.width * scale, h = visibleBottom * scale;
      parts.add(
        CaptionPart(
          row.text,
          logo,
          ui.Rect.fromLTWH(
            x,
            logo == null
                ? (height + row.fontSize * .7 * scale) / 2 - h
                : (height - h) / 2,
            w,
            h,
          ),
          row.fontSize * scale,
        ),
      );
      x += w + s * .01 * scale;
    }
    return CaptionLine(
      parts.map((part) => part.text).where((text) => text.isNotEmpty).join(' '),
      fontBasis * settings.cameraTextScale * scale,
      ui.Rect.fromLTWH(0, 0, width * scale, height),
      'camera',
      parts,
    );
  }

  group([camera()], false);
  final editedLens = metadata.overrides.containsKey('lens');
  final lensShort =
      metadata.editedLensParts || editedLens || metadata.lensShort.isEmpty
      ? ''
      : [
          metadata.lensMakerText,
          PhotoMetadata.withoutMaker(
            metadata.lensMakerText,
            metadata.lensShort,
          ),
        ].where((v) => v.isNotEmpty).join(' ');
  // Lens names are rendered together, matching the user's text-only lens setup.
  group([
    text(
      metadata.lens,
      lensShort,
      fontBasis * settings.lensTextScale,
      'lensModel',
      omit: true,
    ),
    text(metadata.settings, '', fontBasis * settings.exifTextScale, 'settings'),
  ], true);
  return result;
}

Future<Uint8List?> renderCaption(
  PhotoMetadata metadata,
  FrameGeometry geometry, {
  int? maxWidth,
  DisplaySettings settings = const DisplaySettings(),
  LogoStore? logoStore,
}) async {
  if (metadata.isEmpty &&
      [
        metadata.overrides.containsKey('cameraMaker')
            ? ''
            : metadata.cameraMakerLogo,
        metadata.overrides.containsKey('cameraModel')
            ? ''
            : metadata.cameraModelLogo,
      ].every((s) => s.isEmpty)) {
    return null;
  }
  if (geometry.bottom == 0) return null;
  final logos = <String, LogoAsset>{};
  if (!kPublicTextOnly && logoStore != null) {
    for (final name in {
      metadata.overrides.containsKey('cameraMaker')
          ? ''
          : metadata.cameraMakerLogo,
      metadata.overrides.containsKey('cameraModel')
          ? ''
          : metadata.cameraModelLogo,
    }) {
      final asset = await logoStore.load(name);
      if (asset != null) logos[name] = asset;
    }
  }
  final scale = maxWidth == null
      ? 1.0
      : math.min(1.0, maxWidth / geometry.width);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(scale);
  for (final line in layoutCaption(
    metadata,
    geometry,
    settings: settings,
    logos: logos,
  )) {
    final color = line.role == 'camera'
        ? const ui.Color(0xff000000)
        : const ui.Color(0xff444844);
    if (line.parts.isEmpty) {
      final p = _painter(
        line.text,
        line.fontSize,
        maxWidth: line.bounds.width,
        color: color,
      );
      p.paint(canvas, line.bounds.topLeft);
      p.dispose();
    } else {
      for (final part in line.parts) {
        final rect = part.bounds.shift(line.bounds.topLeft);
        if (part.logo != null) {
          part.logo!.paint(canvas, rect);
        } else {
          final p = _painter(
            part.text,
            part.fontSize ?? line.fontSize,
            maxWidth: rect.width,
            color: color,
          );
          p.paint(canvas, rect.topLeft);
          p.dispose();
        }
      }
    }
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      math.max(1, (geometry.width * scale).round()),
      math.max(1, (geometry.bottom * scale).round()),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('撮影情報の描画に失敗しました。');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
