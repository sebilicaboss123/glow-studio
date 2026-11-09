import 'dart:io';
import 'dart:math' show Point;
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

import 'face_geometry.dart';

/// Detects a face and extracts the contours used for makeup.
///
/// Detection runs on the orientation-baked preview bytes, so the returned
/// normalized coordinates line up with the editing/export pipeline.
class FaceService {
  static Future<FaceGeometry> detect(
    Uint8List previewPng,
    int width,
    int height,
  ) async {
    if (width <= 0 || height <= 0) return const FaceGeometry.none();

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/glow_face_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    try {
      await file.writeAsBytes(previewPng, flush: true);
      final faces = await detector.processImage(
        InputImage.fromFilePath(file.path),
      );
      if (faces.isEmpty) return const FaceGeometry.none();

      faces.sort((a, b) {
        final areaA = a.boundingBox.width * a.boundingBox.height;
        final areaB = b.boundingBox.width * b.boundingBox.height;
        return areaB.compareTo(areaA);
      });
      final f = faces.first;
      final w = width.toDouble();
      final h = height.toDouble();

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

      // Outer lip boundary: top of upper lip, then bottom of lower lip reversed.
      final lipsOuter = <Point<int>>[
        ...upperLipTop,
        ...lowerLipBottom.reversed,
      ];
      // Inner mouth (teeth): bottom of upper lip, then top of lower lip reversed.
      final mouthInner = <Point<int>>[
        ...upperLipBottom,
        ...lowerLipTop.reversed,
      ];

      // Cheek centers from landmarks, with a bounding-box fallback.
      final box = f.boundingBox;
      final lCheek = f.landmarks[FaceLandmarkType.leftCheek]?.position;
      final rCheek = f.landmarks[FaceLandmarkType.rightCheek]?.position;
      final lcx = (lCheek?.x.toDouble() ?? box.left + box.width * 0.28) / w;
      final lcy = (lCheek?.y.toDouble() ?? box.top + box.height * 0.60) / h;
      final rcx = (rCheek?.x.toDouble() ?? box.left + box.width * 0.72) / w;
      final rcy = (rCheek?.y.toDouble() ?? box.top + box.height * 0.60) / h;

      return FaceGeometry(
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
    } catch (_) {
      return const FaceGeometry.none();
    } finally {
      await detector.close();
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }
}
