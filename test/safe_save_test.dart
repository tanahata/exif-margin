import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_frame/src/safe_save.dart';

void main() {
  late Directory directory;
  late File source;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('photo_frame_test-');
    source = await File(p.join(directory.path, 'original.jpg'))
        .writeAsBytes([1, 2, 3]);
  });
  tearDown(() => directory.delete(recursive: true));

  test('元の写真への直接保存を拒否する', () async {
    await expectLater(
      inspectDestination(source.path, source.path),
      throwsA(isA<SaveConflict>()),
    );
    expect(await source.readAsBytes(), [1, 2, 3]);
  });

  test('元の写真へのシンボリックリンクも拒否する', () async {
    final alias = await Link(p.join(directory.path, 'alias.jpg'))
        .create(source.path);
    await expectLater(
      inspectDestination(source.path, alias.path),
      throwsA(isA<SaveConflict>()),
    );
  });

  test('新規JPEGを保存し、元写真を変更しない', () async {
    final target = p.join(directory.path, 'framed.jpg');
    final state = await inspectDestination(source.path, target);
    await saveJpegSafely(
      sourcePath: source.path,
      destination: target,
      bytes: Uint8List.fromList([4, 5, 6]),
      approvedState: state,
    );
    expect(await File(target).readAsBytes(), [4, 5, 6]);
    expect(await source.readAsBytes(), [1, 2, 3]);
    expect((await directory.list().toList()).length, 2);
  });

  test('確認済みの既存ファイルを置換できる', () async {
    final target = await File(p.join(directory.path, 'framed.jpg'))
        .writeAsBytes([9]);
    final state = await inspectDestination(source.path, target.path);
    await saveJpegSafely(
      sourcePath: source.path,
      destination: target.path,
      bytes: Uint8List.fromList([4, 5]),
      approvedState: state,
    );
    expect(await target.readAsBytes(), [4, 5]);
  });

  test('保存先が確認後に作られた場合は上書きしない', () async {
    final target = File(p.join(directory.path, 'framed.jpg'));
    final state = await inspectDestination(source.path, target.path);
    await target.writeAsBytes([9]);
    await expectLater(
      saveJpegSafely(
        sourcePath: source.path,
        destination: target.path,
        bytes: Uint8List.fromList([4, 5]),
        approvedState: state,
      ),
      throwsA(isA<SaveConflict>()),
    );
    expect(await target.readAsBytes(), [9]);
  });

  test('確認後に変更された既存ファイルを保護する', () async {
    final target = await File(p.join(directory.path, 'framed.jpg'))
        .writeAsBytes([9]);
    final state = await inspectDestination(source.path, target.path);
    await target.writeAsBytes([8, 8]);
    await expectLater(
      saveJpegSafely(
        sourcePath: source.path,
        destination: target.path,
        bytes: Uint8List.fromList([4, 5]),
        approvedState: state,
      ),
      throwsA(isA<SaveConflict>()),
    );
    expect(await target.readAsBytes(), [8, 8]);
  });
}
