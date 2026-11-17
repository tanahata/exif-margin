import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class SaveConflict implements Exception {
  const SaveConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

class DestinationState {
  const DestinationState(this.exists, this.modified, this.size);
  final bool exists;
  final DateTime? modified;
  final int? size;
}

Future<DestinationState> inspectDestination(
  String sourcePath,
  String destination,
) async {
  final source = File(sourcePath);
  final target = File(destination);
  final sourceResolved = await source.resolveSymbolicLinks();
  final parentResolved = await target.parent.resolveSymbolicLinks();
  final resolvedDestination = p.join(parentResolved, p.basename(destination));
  if (p.equals(sourceResolved, resolvedDestination)) {
    throw const SaveConflict('元の写真には保存できません。別の名前か場所を選んでください。');
  }
  final type = await FileSystemEntity.type(destination, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.file) {
    throw const SaveConflict('この保存先は使用できません。通常のファイル名を選んでください。');
  }
  if (type == FileSystemEntityType.file) {
    if (await FileSystemEntity.identical(sourcePath, destination)) {
      throw const SaveConflict('元の写真と同じファイルです。別の名前を選んでください。');
    }
    final stat = await target.stat();
    return DestinationState(true, stat.modified, stat.size);
  }
  return const DestinationState(false, null, null);
}

Future<void> saveJpegSafely({
  required String sourcePath,
  required String destination,
  required Uint8List bytes,
  required DestinationState approvedState,
}) async {
  // Recheck after encoding and confirmation, before touching the destination.
  final current = await inspectDestination(sourcePath, destination);
  if (current.exists != approvedState.exists ||
      current.modified != approvedState.modified ||
      current.size != approvedState.size) {
    throw const SaveConflict('保存先が変更されました。もう一度保存先を選んでください。');
  }
  final staging = await Directory(p.dirname(destination))
      .createTemp('.photo_frame-');
  File? reservation;
  try {
    final temporary = File(p.join(staging.path, 'render.jpg'));
    await temporary.writeAsBytes(bytes, flush: true);
    if (!approvedState.exists) {
      // Exclusive creation stops a newly appearing file from being overwritten.
      reservation = await File(destination).create(exclusive: true);
    } else {
      final latest = await inspectDestination(sourcePath, destination);
      if (latest.modified != approvedState.modified ||
          latest.size != approvedState.size ||
          !latest.exists) {
        throw const SaveConflict('保存先が変更されました。もう一度お試しください。');
      }
    }
    // Same-filesystem rename publishes only the fully encoded file.
    await temporary.rename(destination);
    reservation = null;
  } finally {
    if (reservation != null && await reservation.exists()) {
      await reservation.delete();
    }
    await staging.delete(recursive: true);
  }
}
