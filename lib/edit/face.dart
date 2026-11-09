import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'face_geometry.dart';

/// Detects a face and extracts the geometry used for makeup / reshape / glow.
///
/// Two-stage: first a contour detector (richest geometry); if that finds
/// nothing, a plain landmark detector (far more robust on sideloaded iOS
/// builds), with geometry approximated from landmarks or the face box. A short
/// diagnostic is attached for the UI when nothing is found.
class FaceService {
  static Future<FaceGeometry> detect(
    Uint8List previewPng,
    int width,
    int height,
    String sourcePath,
  ) async {
    final contourDet = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.04,
      ),
    );
    final basicDet = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.04,
      ),
    );
    File? temp;
    try {
      // Preview temp file (upright, known dimensions).
      String? previewPath;
      if (width > 0 && height > 0) {
        final dir = await getTemporaryDirectory();
        temp = File(
          '${dir.path}/glow_face_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await temp.writeAsBytes(previewPng, flush: true);
        previewPath = temp.path;
      }

      // Original oriented dimensions (for normalizing source-image detection).
      var ow = 0, oh = 0;
      try {
        final origBytes = await File(sourcePath).readAsBytes();
        final dims = await compute(_orientedDims, origBytes);
        ow = dims['w'] ?? 0;
        oh = dims['h'] ?? 0;
      } catch (_) {}

      var cp = 0, cs = 0, lp = 0, ls = 0;

      // Stage 1: contour detector.
      if (previewPath != null) {
        final r = await _detect(previewPath, width.toDouble(), height.toDouble(),
            contourDet, contours: true);
        cp = r.$2;
        if (r.$1.hasFace) return r.$1.copyWith(debug: 'contours/preview ($cp)');
      }
      if (ow > 0 && oh > 0) {
        final r = await _detect(sourcePath, ow.toDouble(), oh.toDouble(),
            contourDet, contours: true);
        cs = r.$2;
        if (r.$1.hasFace) return r.$1.copyWith(debug: 'contours/source ($cs)');
      }

      // Stage 2: basic landmark detector.
      if (previewPath != null) {
        final r = await _detect(previewPath, width.toDouble(), height.toDouble(),
            basicDet, contours: false);
        lp = r.$2;
        if (r.$1.hasFace) return r.$1.copyWith(debug: 'basic/preview ($lp)');
      }
      if (ow > 0 && oh > 0) {
        final r = await _detect(sourcePath, ow.toDouble(), oh.toDouble(),
            basicDet, contours: false);
        ls = r.$2;
        if (r.$1.hasFace) return r.$1.copyWith(debug: 'basic/source ($ls)');
      }

      return const FaceGeometry.none().copyWith(
        debug: 'contour p=$cp s=$cs | basic p=$lp s=$ls | ${width}x$height / ${ow}x$oh',
      );
    } catch (e) {
      return const FaceGeometry.none().copyWith(debug: 'error: $e');
    } finally {
      await contourDet.close();
      await basicDet.close();
      if (temp != null && await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  /// Runs detection and builds geometry. When [contours] is true the richer
  /// contour geometry is used; otherwise geometry is approximated from
  /// landmarks / the face box.
  static Future<(FaceGeometry, int)> _detect(
    String path,
    double w,
    double h,
    FaceDetector detector, {
    required bool contours,
  }) async {
    final faces = await detector.processImage(InputImage.fromFilePath(path));
    if (faces.isEmpty) return (const FaceGeometry.none(), 0);

    faces.sort((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaB.compareTo(areaA);
    });
    final f = faces.first;
    final geom = contours ? _fromContours(f, w, h) : _fromLandmarks(f, w, h);
    if (!geom.hasFace) return (const FaceGeometry.none(), faces.length);
    return (geom, faces.length);
  }

  // --- Contour geometry (best quality) ---

  static FaceGeometry _fromContours(Face f, double w, double h) {
    List<double> flat(List<math.Point<int>>? pts) {
      if (pts == null) return const [];
      final out = <double>[];
      for (final p in pts) {
        out.add(p.x / w);
        out.add(p.y / h);
      }
      return out;
    }

    List<math.Point<int>> contour(FaceContourType t) =>
        f.contours[t]?.points ?? const [];

    final upperLipTop = contour(FaceContourType.upperLipTop);
    final lowerLipBottom = contour(FaceContourType.lowerLipBottom);
    final upperLipBottom = contour(FaceContourType.upperLipBottom);
    final lowerLipTop = contour(FaceContourType.lowerLipTop);
    final leftEye = contour(FaceContourType.leftEye);
    final rightEye = contour(FaceContourType.rightEye);

    // If this face has no usable contours (some devices return none), bail so
    // the caller falls through to landmark detection.
    if (leftEye.isEmpty && rightEye.isEmpty && upperLipTop.isEmpty) {
      return const FaceGeometry.none();
    }

    final lipsOuter = <math.Point<int>>[...upperLipTop, ...lowerLipBottom.reversed];
    final mouthInner = <math.Point<int>>[...upperLipBottom, ...lowerLipTop.reversed];

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
      leftEye: flat(leftEye),
      rightEye: flat(rightEye),
      leftCheekX: lcx,
      leftCheekY: lcy,
      rightCheekX: rcx,
      rightCheekY: rcy,
      faceWidth: box.width / w,
    );
  }

  // --- Landmark / bounding-box geometry (robust fallback) ---

  static FaceGeometry _fromLandmarks(Face f, double w, double h) {
    final box = f.boundingBox;
    final fw = box.width;

    math.Point<int>? lm(FaceLandmarkType t) => f.landmarks[t]?.position;

    // Points, preferring real landmarks, falling back to box proportions.
    double px(math.Point<int>? p, double fx) =>
        (p?.x.toDouble() ?? box.left + box.width * fx);
    double py(math.Point<int>? p, double fy) =>
        (p?.y.toDouble() ?? box.top + box.height * fy);

    final leX = px(lm(FaceLandmarkType.leftEye), 0.32);
    final leY = py(lm(FaceLandmarkType.leftEye), 0.42);
    final reX = px(lm(FaceLandmarkType.rightEye), 0.68);
    final reY = py(lm(FaceLandmarkType.rightEye), 0.42);

    final lmoX = px(lm(FaceLandmarkType.leftMouth), 0.36);
    final lmoY = py(lm(FaceLandmarkType.leftMouth), 0.74);
    final rmoX = px(lm(FaceLandmarkType.rightMouth), 0.64);
    final rmoY = py(lm(FaceLandmarkType.rightMouth), 0.74);
    final bmoY = py(lm(FaceLandmarkType.bottomMouth), 0.82);

    final lcX = px(lm(FaceLandmarkType.leftCheek), 0.27);
    final lcY = py(lm(FaceLandmarkType.leftCheek), 0.62);
    final rcX = px(lm(FaceLandmarkType.rightCheek), 0.73);
    final rcY = py(lm(FaceLandmarkType.rightCheek), 0.62);

    // Eye ellipse polygon.
    List<double> eye(double cx, double cy) {
      final rx = fw * 0.085, ry = fw * 0.05;
      final out = <double>[];
      for (var i = 0; i < 12; i++) {
        final a = 2 * math.pi * i / 12;
        out.add((cx + rx * math.cos(a)) / w);
        out.add((cy + ry * math.sin(a)) / h);
      }
      return out;
    }

    // Lips hexagon from the mouth points.
    final mcx = (lmoX + rmoX) / 2;
    final mcy = (lmoY + rmoY) / 2;
    final mouthW = (rmoX - lmoX).abs();
    final topY = mcy - (bmoY - mcy).abs() * 0.85;
    final lips = <double>[
      lmoX / w, lmoY / h,
      (mcx - mouthW * 0.28) / w, topY / h,
      (mcx + mouthW * 0.28) / w, topY / h,
      rmoX / w, rmoY / h,
      (mcx + mouthW * 0.22) / w, bmoY / h,
      (mcx - mouthW * 0.22) / w, bmoY / h,
    ];

    return FaceGeometry(
      hasFace: true,
      lipsOuter: lips,
      mouthInner: const [],
      leftEye: eye(leX, leY),
      rightEye: eye(reX, reY),
      leftCheekX: lcX / w,
      leftCheekY: lcY / h,
      rightCheekX: rcX / w,
      rightCheekY: rcY / h,
      faceWidth: fw / w,
    );
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
