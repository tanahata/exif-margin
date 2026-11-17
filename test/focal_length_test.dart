import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_frame/src/frame.dart';
import 'package:photo_frame/src/photo_metadata.dart';

void main() {
  const dlux = PhotoMetadata(
    cameraMaker: 'LEICA CAMERA AG',
    cameraModel: 'D-Lux 7',
    focalLength: 15.9,
    focalLength35: 35,
    fNumber: 2.3,
    exposureTime: 1 / 40,
    iso: 3200,
  );

  test('同じ写真で実焦点距離と35mm換算を選べ、F値は変えない', () {
    final actual = dlux.withFocalLengthMode(FocalLengthMode.actual);
    final equivalent = dlux.withFocalLengthMode(FocalLengthMode.equivalent);
    expect(actual.settings, '15.9mm  F2.3  1/40  ISO 3200');
    expect(equivalent.settings, '35mm eq.  F2.3  1/40  ISO 3200');
    expect(
      equivalent.withFocalLengthMode(FocalLengthMode.actual).settings,
      actual.settings,
    );
    expect(dlux.focalLengthMode, FocalLengthMode.automatic);
    expect(
      equivalent.withEquipment(cameraModel: 'D-Lux 7').focalLengthMode,
      FocalLengthMode.equivalent,
    );
  });

  test('35mm換算はCSV未登録機材でも選択でき、自動は機材区分を使う', () {
    expect(
      dlux.withFocalLengthMode(FocalLengthMode.equivalent).usesEquivalent,
      isTrue,
    );
    expect(dlux.usesEquivalent, isFalse);
    final compact = dlux.withEquipment(deviceType: DeviceType.compact);
    expect(compact.usesEquivalent, isTrue);
    expect(
      compact.withFocalLengthMode(FocalLengthMode.actual).usesEquivalent,
      isFalse,
    );
    expect(
      compact
          .withFocalLengthMode(FocalLengthMode.equivalent)
          .withFocalLengthMode(FocalLengthMode.automatic)
          .usesEquivalent,
      isTrue,
    );
  });

  test('JPEG内の実値と換算値をそれぞれ保持する', () {
    final photo = img.Image(width: 100, height: 60);
    photo.exif.exifIfd[0x920a] = img.IfdValueRational(159, 10);
    photo.exif.exifIfd[0xa405] = img.IfdValueShort(35);
    photo.exif.exifIfd[0x829d] = img.IfdValueRational(23, 10);
    final decoded = preparePhoto(img.encodeJpg(photo)).metadata;
    expect(decoded.focalLength, 15.9);
    expect(decoded.focalLength35, 35);
    expect(
      decoded.withFocalLengthMode(FocalLengthMode.equivalent).settings,
      '35mm eq.  F2.3',
    );
  });

  test('換算情報がない場合は値を推定しない', () {
    const photo = PhotoMetadata(focalLength: 12, fNumber: 2);
    expect(
      photo.withFocalLengthMode(FocalLengthMode.equivalent).settings,
      '12mm  F2',
    );
    expect(
      const PhotoMetadata(focalLength35: 35)
          .withFocalLengthMode(FocalLengthMode.actual)
          .settings,
      '',
    );
  });
}
