import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'adjustments.dart';
import 'face_geometry.dart';
import 'makeup.dart';

/// Preview bytes plus their pixel dimensions (needed for face detection).
class PreviewData {
  const PreviewData({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Longest edge (px) used for the interactive preview.
const int kPreviewMaxEdge = 1080;

/// Upper bound for the exported image to keep memory bounded on device.
const int kExportMaxEdge = 3000;

/// Decode [bytes], bake orientation, downscale to a preview and report size.
Future<PreviewData> buildPreview(Uint8List bytes) async {
  final map = await compute(_decodeResizeEntry, <String, dynamic>{
    'bytes': bytes,
    'maxEdge': kPreviewMaxEdge,
  });
  return PreviewData(
    bytes: map['bytes'] as Uint8List,
    width: map['w'] as int,
    height: map['h'] as int,
  );
}

/// Apply skin smoothing + makeup to preview-sized [basePng]. Color grading is
/// layered live on top as a GPU color matrix, so it is not baked here.
Future<Uint8List> renderPreview(
  Uint8List basePng,
  double smooth,
  Makeup makeup,
  FaceGeometry geom,
) {
  if (smooth <= 0.001 && makeup.isEmpty) {
    return Future<Uint8List>.value(basePng);
  }
  return compute(_renderEntry, <String, dynamic>{
    'bytes': basePng,
    'smooth': smooth,
    'makeup': makeup.toMap(),
    'geom': geom.toMap(),
  });
}

/// Full export pipeline at full resolution: smoothing, makeup, then the baked
/// color matrix. Returns JPG bytes ready to save.
Future<Uint8List> renderExport(
  Uint8List originalBytes,
  Adjustments adjustments,
  Makeup makeup,
  FaceGeometry geom,
) {
  return compute(_exportEntry, <String, dynamic>{
    'bytes': originalBytes,
    'smooth': adjustments.smooth,
    'matrix': adjustments.toColorMatrix(),
    'makeup': makeup.toMap(),
    'geom': geom.toMap(),
    'maxEdge': kExportMaxEdge,
  });
}

// --- Isolate entry points ---

Map<String, dynamic> _decodeResizeEntry(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final maxEdge = args['maxEdge'] as int;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported or corrupt image.');
  }
  final resized = _fit(img.bakeOrientation(decoded), maxEdge);
  return <String, dynamic>{
    'bytes': img.encodePng(resized),
    'w': resized.width,
    'h': resized.height,
  };
}

Uint8List _renderEntry(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final smooth = (args['smooth'] as num).toDouble();
  final makeup = Makeup.fromMap((args['makeup'] as Map).cast<String, dynamic>());
  final geom = FaceGeometry.fromMap((args['geom'] as Map).cast<String, dynamic>());

  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  var image = _selectiveSmooth(src, smooth);
  _applyMakeup(image, makeup, geom);
  return img.encodePng(image);
}

Uint8List _exportEntry(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final smooth = (args['smooth'] as num).toDouble();
  final matrix = (args['matrix'] as List).cast<double>();
  final makeup = Makeup.fromMap((args['makeup'] as Map).cast<String, dynamic>());
  final geom = FaceGeometry.fromMap((args['geom'] as Map).cast<String, dynamic>());
  final maxEdge = args['maxEdge'] as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported or corrupt image.');
  }
  var image = _fit(img.bakeOrientation(decoded), maxEdge);
  image = _selectiveSmooth(image, smooth);
  _applyMakeup(image, makeup, geom);
  _bakeMatrix(image, matrix);
  return img.encodeJpg(image, quality: 95);
}

// --- Geometry / fit ---

img.Image _fit(img.Image src, int maxEdge) {
  final longest = src.width > src.height ? src.width : src.height;
  if (longest <= maxEdge) return src;
  if (src.width >= src.height) {
    return img.copyResize(src, width: maxEdge, interpolation: img.Interpolation.cubic);
  }
  return img.copyResize(src, height: maxEdge, interpolation: img.Interpolation.cubic);
}

// --- Skin smoothing (edge-preserving) ---

img.Image _selectiveSmooth(img.Image src, double amount) {
  if (amount <= 0.001) return src;
  final longest = src.width > src.height ? src.width : src.height;
  final radius = (longest / 320).clamp(1, 8).round();
  final blurred = img.gaussianBlur(src.clone(), radius: radius);
  const edgeThreshold = 26.0;
  final strength = amount.clamp(0.0, 1.0);

  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final o = src.getPixel(x, y);
      final b = blurred.getPixel(x, y);
      final diff =
          ((o.r - b.r).abs() + (o.g - b.g).abs() + (o.b - b.b).abs()) / 3.0;
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

// --- Makeup ---

void _applyMakeup(img.Image image, Makeup m, FaceGeometry g) {
  if (!g.hasFace || m.isEmpty) return;
  final W = image.width;
  final H = image.height;

  // Bounding box over all makeup geometry, with margin for feathering.
  double minX = 1, minY = 1, maxX = 0, maxY = 0;
  void include(double nx, double ny) {
    if (nx < minX) minX = nx;
    if (ny < minY) minY = ny;
    if (nx > maxX) maxX = nx;
    if (ny > maxY) maxY = ny;
  }

  for (final poly in [g.lipsOuter, g.leftEye, g.rightEye]) {
    for (var i = 0; i + 1 < poly.length; i += 2) {
      include(poly[i], poly[i + 1]);
    }
  }
  final blushR = g.faceWidth * 0.16;
  include(g.leftCheekX - blushR, g.leftCheekY - blushR);
  include(g.leftCheekX + blushR, g.leftCheekY + blushR);
  include(g.rightCheekX - blushR, g.rightCheekY - blushR);
  include(g.rightCheekX + blushR, g.rightCheekY + blushR);
  if (maxX <= minX || maxY <= minY) return;

  const marginN = 0.03;
  final bx = ((minX - marginN) * W).floor().clamp(0, W - 1);
  final by = ((minY - marginN) * H).floor().clamp(0, H - 1);
  final bx2 = ((maxX + marginN) * W).ceil().clamp(0, W - 1);
  final by2 = ((maxY + marginN) * H).ceil().clamp(0, H - 1);
  final bw = bx2 - bx + 1;
  final bh = by2 - by + 1;
  if (bw < 2 || bh < 2) return;

  final feather = (math.max(bw, bh) / 60).clamp(1, 12).round();

  if (m.lipIntensity > 0 && g.lipsOuter.length >= 6) {
    final mask = Uint8List(bw * bh);
    _fillPolygon(mask, bw, bh, bx, by, g.lipsOuter, W, H);
    _boxBlur(mask, bw, bh, feather);
    _blendTint(image, mask, bx, by, bw, bh, m.lipColor, m.lipIntensity * 0.9);
  }

  if (m.teeth > 0 && g.mouthInner.length >= 6) {
    final mask = Uint8List(bw * bh);
    _fillPolygon(mask, bw, bh, bx, by, g.mouthInner, W, H);
    _boxBlur(mask, bw, bh, (feather / 2).clamp(1, 6).round());
    _blendWhiten(image, mask, bx, by, bw, bh, m.teeth);
  }

  if (m.eyeBrighten > 0) {
    final mask = Uint8List(bw * bh);
    if (g.leftEye.length >= 6) {
      _fillPolygon(mask, bw, bh, bx, by, g.leftEye, W, H);
    }
    if (g.rightEye.length >= 6) {
      _fillPolygon(mask, bw, bh, bx, by, g.rightEye, W, H);
    }
    _boxBlur(mask, bw, bh, (feather / 2).clamp(1, 6).round());
    _blendBrighten(image, mask, bx, by, bw, bh, m.eyeBrighten * 0.6);
  }

  if (m.blush > 0) {
    final mask = Uint8List(bw * bh);
    final rPx = (blushR * W).clamp(2, W.toDouble()).toDouble();
    _fillCircle(mask, bw, bh, bx, by, g.leftCheekX * W, g.leftCheekY * H, rPx);
    _fillCircle(mask, bw, bh, bx, by, g.rightCheekX * W, g.rightCheekY * H, rPx);
    _boxBlur(mask, bw, bh, feather * 2);
    _blendTint(image, mask, bx, by, bw, bh, 0xF06292, m.blush * 0.4);
  }
}

/// Even-odd scanline polygon fill into a bbox-local mask.
void _fillPolygon(
  Uint8List mask,
  int bw,
  int bh,
  int bx,
  int by,
  List<double> norm,
  int W,
  int H,
) {
  final n = norm.length ~/ 2;
  if (n < 3) return;
  final xs = List<double>.filled(n, 0);
  final ys = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    xs[i] = norm[i * 2] * W - bx;
    ys[i] = norm[i * 2 + 1] * H - by;
  }
  for (var y = 0; y < bh; y++) {
    final yc = y + 0.5;
    final nodes = <double>[];
    var j = n - 1;
    for (var i = 0; i < n; i++) {
      final yi = ys[i], yj = ys[j];
      if ((yi < yc && yj >= yc) || (yj < yc && yi >= yc)) {
        nodes.add(xs[i] + (yc - yi) / (yj - yi) * (xs[j] - xs[i]));
      }
      j = i;
    }
    nodes.sort();
    for (var k = 0; k + 1 < nodes.length; k += 2) {
      var x0 = nodes[k].floor();
      var x1 = nodes[k + 1].ceil();
      if (x1 < 0 || x0 > bw) continue;
      if (x0 < 0) x0 = 0;
      if (x1 > bw) x1 = bw;
      for (var x = x0; x < x1; x++) {
        mask[y * bw + x] = 255;
      }
    }
  }
}

void _fillCircle(
  Uint8List mask,
  int bw,
  int bh,
  int bx,
  int by,
  double cxImg,
  double cyImg,
  double r,
) {
  final cx = cxImg - bx;
  final cy = cyImg - by;
  final r2 = r * r;
  final x0 = (cx - r).floor().clamp(0, bw);
  final x1 = (cx + r).ceil().clamp(0, bw);
  final y0 = (cy - r).floor().clamp(0, bh);
  final y1 = (cy + r).ceil().clamp(0, bh);
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy <= r2) mask[y * bw + x] = 255;
    }
  }
}

/// Separable box blur (two passes approximate a gaussian), in place.
void _boxBlur(Uint8List mask, int bw, int bh, int radius) {
  if (radius < 1) return;
  final tmp = Uint8List(mask.length);
  for (var pass = 0; pass < 2; pass++) {
    // horizontal
    for (var y = 0; y < bh; y++) {
      var sum = 0;
      final row = y * bw;
      final win = radius * 2 + 1;
      for (var x = -radius; x <= radius; x++) {
        sum += mask[row + x.clamp(0, bw - 1)];
      }
      for (var x = 0; x < bw; x++) {
        tmp[row + x] = (sum ~/ win);
        final out = row + (x - radius).clamp(0, bw - 1);
        final inx = row + (x + radius + 1).clamp(0, bw - 1);
        sum += mask[inx] - mask[out];
      }
    }
    // vertical
    for (var x = 0; x < bw; x++) {
      var sum = 0;
      final win = radius * 2 + 1;
      for (var y = -radius; y <= radius; y++) {
        sum += tmp[y.clamp(0, bh - 1) * bw + x];
      }
      for (var y = 0; y < bh; y++) {
        mask[y * bw + x] = (sum ~/ win);
        final outY = (y - radius).clamp(0, bh - 1);
        final inY = (y + radius + 1).clamp(0, bh - 1);
        sum += tmp[inY * bw + x] - tmp[outY * bw + x];
      }
    }
  }
}

/// Recolor pixels toward [rgb] while preserving each pixel's luminance.
void _blendTint(
  img.Image image,
  Uint8List mask,
  int bx,
  int by,
  int bw,
  int bh,
  int rgb,
  double intensity,
) {
  final cr = (rgb >> 16) & 0xFF;
  final cg = (rgb >> 8) & 0xFF;
  final cb = rgb & 0xFF;
  final colorLum = math.max(1.0, 0.299 * cr + 0.587 * cg + 0.114 * cb);
  for (var y = 0; y < bh; y++) {
    for (var x = 0; x < bw; x++) {
      final cov = mask[y * bw + x] / 255.0 * intensity;
      if (cov <= 0.003) continue;
      final p = image.getPixel(bx + x, by + y);
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      final f = lum / colorLum;
      final tr = (cr * f);
      final tg = (cg * f);
      final tb = (cb * f);
      image.setPixelRgba(
        bx + x,
        by + y,
        (p.r + (tr - p.r) * cov).clamp(0, 255).round(),
        (p.g + (tg - p.g) * cov).clamp(0, 255).round(),
        (p.b + (tb - p.b) * cov).clamp(0, 255).round(),
        p.a.toInt(),
      );
    }
  }
}

/// Whiten + brighten (teeth).
void _blendWhiten(
  img.Image image,
  Uint8List mask,
  int bx,
  int by,
  int bw,
  int bh,
  double intensity,
) {
  for (var y = 0; y < bh; y++) {
    for (var x = 0; x < bw; x++) {
      final cov = mask[y * bw + x] / 255.0 * intensity;
      if (cov <= 0.003) continue;
      final p = image.getPixel(bx + x, by + y);
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      double ch(num c) {
        final desat = c + (lum - c) * 0.35; // reduce yellow tint
        final bright = desat + (255 - desat) * 0.25;
        return (c + (bright - c) * cov).clamp(0, 255);
      }

      image.setPixelRgba(
        bx + x,
        by + y,
        ch(p.r).round(),
        ch(p.g).round(),
        ch(p.b).round(),
        p.a.toInt(),
      );
    }
  }
}

/// Lift brightness toward white (eye area).
void _blendBrighten(
  img.Image image,
  Uint8List mask,
  int bx,
  int by,
  int bw,
  int bh,
  double intensity,
) {
  for (var y = 0; y < bh; y++) {
    for (var x = 0; x < bw; x++) {
      final cov = mask[y * bw + x] / 255.0 * intensity;
      if (cov <= 0.003) continue;
      final p = image.getPixel(bx + x, by + y);
      image.setPixelRgba(
        bx + x,
        by + y,
        (p.r + (255 - p.r) * 0.35 * cov).clamp(0, 255).round(),
        (p.g + (255 - p.g) * 0.35 * cov).clamp(0, 255).round(),
        (p.b + (255 - p.b) * 0.35 * cov).clamp(0, 255).round(),
        p.a.toInt(),
      );
    }
  }
}

void _bakeMatrix(img.Image image, List<double> m) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      image.setPixelRgba(
        x,
        y,
        applyMatrixChannel(m, 0, p.r, p.g, p.b, p.a),
        applyMatrixChannel(m, 1, p.r, p.g, p.b, p.a),
        applyMatrixChannel(m, 2, p.r, p.g, p.b, p.a),
        p.a.toInt(),
      );
    }
  }
}

int _mix(num a, num b, double t) => (a + (b - a) * t).clamp(0, 255).round();
