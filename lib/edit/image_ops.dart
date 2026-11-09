import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'adjustments.dart';

/// Result of preparing a freshly imported photo.
class PreparedImage {
  const PreparedImage({required this.preview, required this.sourcePath});

  /// Downscaled RGBA PNG bytes used for the live editing preview.
  final Uint8List preview;

  /// Original file path, re-processed at full resolution on export.
  final String sourcePath;
}

/// Longest edge (px) used for the interactive preview. Keeps slider feedback
/// smooth even on large photos; export always uses full resolution.
const int kPreviewMaxEdge = 1080;

/// Upper bound for the exported image to keep memory bounded on device.
const int kExportMaxEdge = 3000;

/// Decode [bytes] and return a preview-sized PNG for editing.
Future<Uint8List> buildPreview(Uint8List bytes) {
  return compute(_decodeResizeEntry, <String, dynamic>{
    'bytes': bytes,
    'maxEdge': kPreviewMaxEdge,
  });
}

/// Apply skin smoothing to preview-sized [pngBytes] at [amount] (0..1).
/// Returns PNG bytes. Runs off the UI thread.
Future<Uint8List> smoothPreview(Uint8List pngBytes, double amount) {
  return compute(_smoothEntry, <String, dynamic>{
    'bytes': pngBytes,
    'amount': amount,
  });
}

/// Full export pipeline: decode [originalBytes] at full resolution, apply skin
/// smoothing, then bake the color matrix for [adjustments] into the pixels.
/// Returns encoded JPG bytes ready to save to the gallery.
Future<Uint8List> renderExport(
  Uint8List originalBytes,
  Adjustments adjustments,
) {
  return compute(_exportEntry, <String, dynamic>{
    'bytes': originalBytes,
    'smooth': adjustments.smooth,
    'matrix': adjustments.toColorMatrix(),
    'maxEdge': kExportMaxEdge,
  });
}

// --- Isolate entry points (top-level, primitive args only) ---

Uint8List _decodeResizeEntry(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final maxEdge = args['maxEdge'] as int;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported or corrupt image.');
  }
  final oriented = img.bakeOrientation(decoded);
  final resized = _fit(oriented, maxEdge);
  return img.encodePng(resized);
}

Uint8List _smoothEntry(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final amount = (args['amount'] as num).toDouble();
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  final out = _selectiveSmooth(src, amount);
  return img.encodePng(out);
}

Uint8List _exportEntry(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final amount = (args['smooth'] as num).toDouble();
  final matrix = (args['matrix'] as List).cast<double>();
  final maxEdge = args['maxEdge'] as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported or corrupt image.');
  }
  var image = img.bakeOrientation(decoded);
  image = _fit(image, maxEdge);
  image = _selectiveSmooth(image, amount);
  _bakeMatrix(image, matrix);
  return img.encodeJpg(image, quality: 95);
}

// --- Processing primitives ---

img.Image _fit(img.Image src, int maxEdge) {
  final longest = src.width > src.height ? src.width : src.height;
  if (longest <= maxEdge) return src;
  if (src.width >= src.height) {
    return img.copyResize(src, width: maxEdge, interpolation: img.Interpolation.cubic);
  }
  return img.copyResize(src, height: maxEdge, interpolation: img.Interpolation.cubic);
}

/// Edge-preserving "surface blur" style smoothing: blends a blurred copy into
/// the original only where local detail is low (skin), protecting edges such
/// as eyes, brows and lips. [amount] is 0..1.
img.Image _selectiveSmooth(img.Image src, double amount) {
  if (amount <= 0.001) return src;

  final longest = src.width > src.height ? src.width : src.height;
  final radius = (longest / 320).clamp(1, 8).round();
  final blurred = img.gaussianBlur(src.clone(), radius: radius);

  // Detail above this 0..255 difference is treated as an edge and preserved.
  const edgeThreshold = 26.0;
  final strength = amount.clamp(0.0, 1.0);

  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final o = src.getPixel(x, y);
      final b = blurred.getPixel(x, y);

      final diff = ((o.r - b.r).abs() +
              (o.g - b.g).abs() +
              (o.b - b.b).abs()) /
          3.0;
      // 1.0 on flat skin -> 0.0 on strong edges.
      final edgeWeight = (1.0 - (diff / edgeThreshold)).clamp(0.0, 1.0);
      final w = strength * edgeWeight;

      src.setPixelRgba(
        x,
        y,
        _mix(o.r, b.r, w),
        _mix(o.g, b.g, w),
        _mix(o.b, b.b, w),
        o.a.toInt(),
      );
    }
  }
  return src;
}

void _bakeMatrix(img.Image image, List<double> m) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final r = applyMatrixChannel(m, 0, p.r, p.g, p.b, p.a);
      final g = applyMatrixChannel(m, 1, p.r, p.g, p.b, p.a);
      final b = applyMatrixChannel(m, 2, p.r, p.g, p.b, p.a);
      image.setPixelRgba(x, y, r, g, b, p.a.toInt());
    }
  }
}

int _mix(num a, num b, double t) => (a + (b - a) * t).clamp(0, 255).round();
