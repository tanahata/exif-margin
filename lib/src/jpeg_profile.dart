import 'dart:typed_data';

/// image 4.12.0 omits the two ICC APP2 sequence bytes. Replace only that
/// metadata envelope; quantization tables and compressed image data are untouched.
/// https://archive.color.org/files/technotes/ICC-Technote-ProfileEmbedding.pdf
Uint8List standardizeJpegIcc(Uint8List jpeg, Uint8List profile) {
  if (jpeg.length < 4 ||
      jpeg[0] != 255 ||
      jpeg[1] != 216 ||
      profile.length < 128 ||
      ByteData.sublistView(profile).getUint32(0) != profile.length ||
      String.fromCharCodes(profile.sublist(36, 40)) != 'acsp' ||
      String.fromCharCodes(profile.sublist(16, 20)) != 'RGB ') {
    throw const FormatException('JPEGまたはsRGBプロファイルが正しくありません。');
  }
  final output = BytesBuilder(copy: false)..add(jpeg.sublist(0, 2));
  const chunkSize = 65519;
  final count = (profile.length + chunkSize - 1) ~/ chunkSize;
  if (count > 255) throw const FormatException('色プロファイルが大きすぎます。');
  for (var chunk = 0; chunk < count; chunk++) {
    final start = chunk * chunkSize;
    final end = (start + chunkSize).clamp(0, profile.length);
    final length = end - start + 16;
    output.add([255, 226, length >> 8, length & 255]);
    output.add('ICC_PROFILE\x00'.codeUnits);
    output.add([chunk + 1, count]);
    output.add(Uint8List.sublistView(profile, start, end));
  }
  var offset = 2;
  while (offset + 4 <= jpeg.length) {
    if (jpeg[offset] != 255) throw const FormatException('JPEGのマーカーが不正です。');
    final marker = jpeg[offset + 1];
    if (marker == 218 || marker == 217) {
      output.add(Uint8List.sublistView(jpeg, offset));
      return output.takeBytes();
    }
    final length = jpeg[offset + 2] * 256 + jpeg[offset + 3];
    if (length < 2 || offset + 2 + length > jpeg.length) {
      throw const FormatException('JPEGが破損しています。');
    }
    final payload = offset + 4;
    final icc =
        marker == 226 &&
        length >= 14 &&
        String.fromCharCodes(jpeg.sublist(payload, payload + 12)) ==
            'ICC_PROFILE\x00';
    if (!icc) {
      output.add(Uint8List.sublistView(jpeg, offset, offset + length + 2));
    }
    offset += length + 2;
  }
  throw const FormatException('JPEGが途中で終了しています。');
}
