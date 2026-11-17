import 'display_settings.dart';

class CaptionSizes {
  const CaptionSizes({this.left = 1, this.right = 1});
  final double left, right;

  DisplaySettings applyTo(DisplaySettings base) => DisplaySettings(
    cameraTextScale: .024 * left,
    lensTextScale: .024 * right,
    exifTextScale: .024 * right,
    cameraGlyphHeightScale: .024 * .7 * left,
    logoHeightScale: .024 * .7 * left,
    logoMaxWidthScale: base.logoMaxWidthScale * left,
    typographyUsesPhotoWidth: true,
    bottomOffsetScale: base.bottomOffsetScale,
    logoScales: base.logoScales,
  );
  void validate() {
    if (!left.isFinite ||
        !right.isFinite ||
        left < .5 ||
        left > 2 ||
        right < .5 ||
        right > 2) {
      throw const FormatException('文字とロゴのサイズは50〜200%にしてください。');
    }
  }
}
