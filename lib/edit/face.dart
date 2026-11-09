import 'dart:io';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'face_geometry.dart';

/// Detects a face and extracts the contours used for makeup.
///
/// Tries the orientation-baked preview first (coordinates line up with the
/// editing/export pipeline); if that finds nothing, it retries on the original
/// photo. A short diagnostic is attached for the UI when nothing is found.
class FaceService {
  static Future<FaceGeometry> detect(
    Uint8List previewPng,
    int width,
    int height,
    String sourcePath,
  ) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    File? temp;
    try {
      // Attempt 1: the preview (known upright dimensions).
      var n1 = 0;
      if (width > 0 && height > 0) {
        final dir = await getTemporaryDirectory();
        temp = File(
          '${dir.path}/glow_face_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await temp.writeAsBytes(previewPng, flush: true);
        final r1 = await _detectOn(temp.path, width.toDouble(), height.toDouble(), detector);
        n1 = r1.$2;
        if (r1.$1.hasFace) return r1.$1.copyWith(debug: 'preview ok ($n1)');
      }

      // Attempt 2: the original photo, normalized by its oriented size.
      var ow = 0, oh = 0, n2 = 0;
      try {
        final origBytes = await File(sourcePath).readAsBytes();
        final dims = await compute(_orientedDims, origBytes);
        ow = dims['w'] ?? 0;
        oh = dims['h'] ?? 0;
        if (ow > 0 && oh > 0) {
          final r2 = await _detectOn(sourcePath, ow.toDouble(), oh.toDouble(), detector);
          n2 = r2.$2;
          if (r2.$1.hasFace) return r2.$1.copyWith(debug: 'source ok ($n2)');
        }
      } catch (e) {
        return const FaceGeometry.none().copyWith(debug: 'source error: $e');
      }

      return const FaceGeometry.none().copyWith(
        debug: '0 faces | preview ${width}x$height n=$n1 | source ${ow}x$oh n=$n2',
      );
    } catch (e) {
      return const FaceGeometry.none().copyWith(debug: 'error: $e');
    } finally {
      await detector.close();
      if (temp != null && await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  /// Runs detection on [path] and builds normalized geometry. Returns the
  /// geometry and the number of faces found.
  static Future<(FaceGeometry, int)> _detectOn(
    String path,
    double w,
    double h,
    FaceDetector detector,
  ) async {
    final faces = await detector.processImage(InputImage.fromFilePath(path));
    if (faces.isEmpty) return (const FaceGeometry.none(), 0);

    faces.sort((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaB.compareTo(areaA);
    });
    final f = faces.first;

    List<double> flat(List<Point<int>>? pts) {
      if (pts == null) return const [];
      final out = <double>[];
      for (final p in pts) {
        out.add(p.x / w);
        out.add(p.y / h);
      }
      return out;
    }

    List<Point<int>> contour(FaceContourType t) =>
        f.contours[t]?.points ?? const [];

    final upperLipTop = contour(FaceContourType.upperLipTop);
    final lowerLipBottom = contour(FaceContourType.lowerLipBottom);
    final upperLipBottom = contour(FaceContourType.upperLipBottom);
    final lowerLipTop = contour(FaceContourType.lowerLipTop);

    final lipsOuter = <Point<int>>[...upperLipTop, ...lowerLipBottom.reversed];
    final mouthInner = <Point<int>>[...upperLipBottom, ...lowerLipTop.reversed];

    final box = f.boundingBox;
    final lCheek = f.landmarks[FaceLandmarkType.leftCheek]?.position;
    final rCheek = f.landmarks[FaceLandmarkType.rightCheek]?.position;
    final lcx = (lCheek?.x.toDouble() ?? box.left + box.width * 0.28) / w;
    final lcy = (lCheek?.y.toDouble() ?? box.top + box.height * 0.60) / h;
    final rcx = (rCheek?.x.toDouble() ?? box.left + box.width * 0.72) / w;
    final rcy = (rCheek?.y.toDouble() ?? box.top + box.height * 0.60) / h;

    final geom = FaceGeometry(
      hasFace: true,
      lipsOuter: flat(lipsOuter),
      mouthInner: flat(mouthInner),
      leftEye: flat(contour(FaceContourType.leftEye)),
      rightEye: flat(contour(FaceContourType.rightEye)),
      leftCheekX: lcx,
      leftCheekY: lcy,
      rightCheekX: rcx,
      rightCheekY: rcy,
      faceWidth: box.width / w,
    );
    return (geom, faces.length);
  }
}

/// Oriented pixel dimensions of [bytes] (matches the editing pipeline, which
/// bakes EXIF orientation). Returns {'w':0,'h':0} if it cannot be decoded.
Map<String, int> _orientedDims(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return {'w': 0, 'h': 0};
  final oriented = img.bakeOrientation(decoded);
  return {'w': oriented.width, 'h': oriented.height};
}
