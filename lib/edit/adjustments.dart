import 'dart:math' as math;

/// Immutable set of global photo adjustments.
///
/// Every value is normalized to a friendly UI range and converted to a
/// 4x5 color matrix (the same format accepted by Flutter's
/// `ColorFilter.matrix`) so the live preview is rendered on the GPU.
class Adjustments {
  const Adjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
    this.filter = FilterPreset.original,
    this.smooth = 0,
  });

  /// -1..1
  final double brightness;

  /// -1..1
  final double contrast;

  /// -1..1
  final double saturation;

  /// -1..1 (negative = cooler, positive = warmer)
  final double warmth;

  /// Selected color-grade preset.
  final FilterPreset filter;

  /// 0..1 skin-smoothing amount (applied on pixels, not via the matrix).
  final double smooth;

  Adjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    FilterPreset? filter,
    double? smooth,
  }) {
    return Adjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      warmth: warmth ?? this.warmth,
      filter: filter ?? this.filter,
      smooth: smooth ?? this.smooth,
    );
  }

  bool get isNeutral =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      warmth == 0 &&
      smooth == 0 &&
      filter == FilterPreset.original;

  /// Builds the combined 4x5 color matrix (length 20) for these adjustments,
  /// including the selected [filter] preset.
  List<double> toColorMatrix() {
    var m = _identity();
    m = _multiply(_contrastMatrix(contrast), m);
    m = _multiply(_saturationMatrix(saturation), m);
    m = _multiply(_warmthMatrix(warmth), m);
    m = _multiply(_brightnessMatrix(brightness), m);
    m = _multiply(filter.matrix(), m);
    return m;
  }
}

List<double> _identity() => <double>[
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, 0, //
      0, 0, 0, 1, 0, //
    ];

/// Multiply two 4x5 color matrices (a after b), treating the implicit 5th
/// row as [0,0,0,0,1].
List<double> _multiply(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 5; j++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[i * 5 + k] * b[k * 5 + j];
      }
      if (j == 4) sum += a[i * 5 + 4];
      out[i * 5 + j] = sum;
    }
  }
  return out;
}

List<double> _brightnessMatrix(double v) {
  final o = v * 100.0; // 0..255 channel space
  return <double>[
    1, 0, 0, 0, o, //
    0, 1, 0, 0, o, //
    0, 0, 1, 0, o, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _contrastMatrix(double v) {
  final s = 1.0 + v * 0.6; // scale around mid grey
  final t = 127.5 * (1.0 - s);
  return <double>[
    s, 0, 0, 0, t, //
    0, s, 0, 0, t, //
    0, 0, s, 0, t, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _saturationMatrix(double v) {
  final s = 1.0 + v; // 0..2
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final inv = 1.0 - s;
  return <double>[
    lr * inv + s, lg * inv, lb * inv, 0, 0, //
    lr * inv, lg * inv + s, lb * inv, 0, 0, //
    lr * inv, lg * inv, lb * inv + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _warmthMatrix(double v) {
  final o = v * 30.0;
  return <double>[
    1, 0, 0, 0, o, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, -o, //
    0, 0, 0, 1, 0, //
  ];
}

/// A named color-grade preset expressed as a color matrix.
enum FilterPreset {
  original('Original'),
  radiant('Radiant'),
  warmGold('Warm Gold'),
  cool('Cool'),
  mono('Mono'),
  noir('Noir'),
  fade('Fade'),
  vivid('Vivid');

  const FilterPreset(this.label);

  final String label;

  List<double> matrix() {
    switch (this) {
      case FilterPreset.original:
        return _identity();
      case FilterPreset.radiant:
        return _compose(saturation: 0.18, brightness: 0.05, warmth: 0.15);
      case FilterPreset.warmGold:
        return _compose(warmth: 0.5, saturation: 0.1, contrast: 0.08);
      case FilterPreset.cool:
        return _compose(warmth: -0.45, saturation: 0.05);
      case FilterPreset.mono:
        return _saturationMatrix(-1);
      case FilterPreset.noir:
        return _multiply(_contrastMatrix(0.35), _saturationMatrix(-1));
      case FilterPreset.fade:
        return _compose(contrast: -0.25, brightness: 0.08, saturation: -0.15);
      case FilterPreset.vivid:
        return _compose(saturation: 0.4, contrast: 0.15);
    }
  }
}

List<double> _compose({
  double brightness = 0,
  double contrast = 0,
  double saturation = 0,
  double warmth = 0,
}) {
  var m = _identity();
  m = _multiply(_contrastMatrix(contrast), m);
  m = _multiply(_saturationMatrix(saturation), m);
  m = _multiply(_warmthMatrix(warmth), m);
  m = _multiply(_brightnessMatrix(brightness), m);
  return m;
}

/// Apply a 4x5 color matrix to an 8-bit channel value set. Exposed for the
/// export pipeline, which bakes adjustments into real pixels.
int applyMatrixChannel(
  List<double> m,
  int row,
  num r,
  num g,
  num b,
  num a,
) {
  final o = m[row * 5 + 0] * r +
      m[row * 5 + 1] * g +
      m[row * 5 + 2] * b +
      m[row * 5 + 3] * a +
      m[row * 5 + 4];
  return o.clamp(0, 255).round();
}

double clampUnit(double v) => math.max(-1.0, math.min(1.0, v));
