import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

class LogoAsset {
  LogoAsset.image(ui.Image value)
    : image = value,
      picture = null,
      size = ui.Size(value.width.toDouble(), value.height.toDouble());
  LogoAsset.vector(PictureInfo value)
    : picture = value,
      image = null,
      size = value.size;
  final ui.Image? image;
  final PictureInfo? picture;
  final ui.Size size;

  void paint(ui.Canvas canvas, ui.Rect destination) {
    canvas.save();
    canvas.clipRect(destination);
    if (image != null) {
      canvas.drawImageRect(
        image!,
        ui.Offset.zero & size,
        destination,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
    } else {
      canvas.translate(destination.left, destination.top);
      canvas.scale(
        destination.width / size.width,
        destination.height / size.height,
      );
      canvas.drawPicture(picture!.picture);
    }
    canvas.restore();
  }

  void dispose() {
    image?.dispose();
    picture?.picture.dispose();
  }
}

class LogoStore {
  LogoStore(this.folder);
  final Directory folder;
  final Map<String, LogoAsset?> _cache = {};
  final Set<String> warnings = {};
  bool _disposed = false;

  Future<LogoAsset?> load(String name) async {
    if (name.isEmpty || _disposed) return null;
    if (_cache.containsKey(name)) return _cache[name];
    LogoAsset? asset;
    try {
      if (p.basename(name) != name || name.contains('\\')) {
        throw const FormatException();
      }
      final path = await File(p.join(folder.path, name)).resolveSymbolicLinks();
      if (!p.isWithin(await folder.resolveSymbolicLinks(), path)) {
        throw const FormatException();
      }
      if (p.extension(name).toLowerCase() == '.png') {
        final codec = await ui.instantiateImageCodec(
          await File(path).readAsBytes(),
        );
        try {
          asset = LogoAsset.image((await codec.getNextFrame()).image);
        } finally {
          codec.dispose();
        }
      } else if (p.extension(name).toLowerCase() == '.svg') {
        final source = await File(path).readAsString();
        // Self-contained files only; never fetch an external resource from a logo.
        for (final match in RegExp(
          r'''(?:href|xlink:href)\s*=\s*["']([^"']*)["']''',
          caseSensitive: false,
        ).allMatches(source)) {
          final ref = match.group(1)!.trim();
          if (!ref.startsWith('#') && !ref.startsWith('data:image/')) {
            throw const FormatException();
          }
        }
        if (RegExp(
          r'''url\(\s*["']?(?:https?:|file:|//)|@import''',
          caseSensitive: false,
        ).hasMatch(source)) {
          throw const FormatException();
        }
        asset = LogoAsset.vector(
          await vg.loadPicture(SvgStringLoader(source), null),
        );
      } else {
        throw const FormatException();
      }
      if (asset.size.isEmpty ||
          !asset.size.width.isFinite ||
          !asset.size.height.isFinite) {
        throw const FormatException();
      }
    } catch (_) {
      asset?.dispose();
      asset = null;
      warnings.add('$name を表示できないため、文字で表示します。');
    }
    if (_disposed) {
      asset?.dispose();
      return null;
    }
    _cache[name] = asset;
    return asset;
  }

  void dispose() {
    _disposed = true;
    for (final asset in _cache.values) {
      asset?.dispose();
    }
    _cache.clear();
  }
}
