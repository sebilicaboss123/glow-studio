import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'face_geometry.dart';

/// Face detection backed by Apple's native **Vision** framework, reached through
/// a method channel to the iOS host (see `AppDelegate.swift`).
///
/// Vision needs no bundled model, handles image orientation itself, and is far
/// more reliable on a sideloaded device than the previous ML Kit path (which
/// returned zero faces even on a clear, full-screen face). Geometry comes back
/// normalized to 0..1 of the image with a top-left origin, matching the editing
/// pipeline, so it scales to both the preview and the full-resolution export.
class FaceService {
  static const MethodChannel _channel = MethodChannel('glow_studio/face');

  static Future<FaceGeometry> detect(
    Uint8List previewPng,
    int width,
    int height,
    String sourcePath,
  ) async {
    File? temp;
    try {
      // Prefer the upright, preview-sized PNG we already generated (small and
      // fast); fall back to the original photo path if we have no preview.
      String primary = sourcePath;
      if (width > 0 && height > 0 && previewPng.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        temp = File(
          '${dir.path}/glow_face_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await temp.writeAsBytes(previewPng, flush: true);
        primary = temp.path;
      }

      final first = await _invoke(primary);
      if (first.hasFace) return first;

      // Nothing on the preview → retry on the full-resolution source photo.
      if (primary != sourcePath) {
        final second = await _invoke(sourcePath);
        if (second.hasFace) return second;
        return const FaceGeometry.none().copyWith(
          debug: 'preview[${first.debug}] / source[${second.debug}]',
        );
      }
      return first;
    } catch (e) {
      return const FaceGeometry.none().copyWith(debug: 'error: $e');
    } finally {
      if (temp != null && await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  static Future<FaceGeometry> _invoke(String path) async {
    final res = await _channel
        .invokeMapMethod<String, dynamic>('detect', <String, String>{'path': path});
    if (res == null) {
      return const FaceGeometry.none().copyWith(debug: 'vision: null result');
    }
    return _fromMap(res);
  }

  static FaceGeometry _fromMap(Map<String, dynamic> m) {
    final debug = (m['debug'] as String?) ?? '';
    if (m['hasFace'] != true) {
      return const FaceGeometry.none().copyWith(debug: debug);
    }
    List<double> dl(dynamic v) =>
        (v as List?)?.map((e) => (e as num).toDouble()).toList() ?? const <double>[];
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    return FaceGeometry(
      hasFace: true,
      lipsOuter: dl(m['lipsOuter']),
      mouthInner: dl(m['mouthInner']),
      leftEye: dl(m['leftEye']),
      rightEye: dl(m['rightEye']),
      leftCheekX: d(m['lcx']),
      leftCheekY: d(m['lcy']),
      rightCheekX: d(m['rcx']),
      rightCheekY: d(m['rcy']),
      faceWidth: d(m['faceWidth']),
      debug: debug,
    );
  }
}
