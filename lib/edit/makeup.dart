/// Landmark-based makeup parameters. Colors are 0xRRGGBB.
class Makeup {
  const Makeup({
    this.lipColor = 0xC2185B,
    this.lipIntensity = 0,
    this.blush = 0,
    this.teeth = 0,
    this.eyeBrighten = 0,
  });

  /// Lipstick color, 0xRRGGBB.
  final int lipColor;

  /// 0..1
  final double lipIntensity;

  /// 0..1
  final double blush;

  /// 0..1
  final double teeth;

  /// 0..1
  final double eyeBrighten;

  bool get isEmpty =>
      lipIntensity == 0 && blush == 0 && teeth == 0 && eyeBrighten == 0;

  Makeup copyWith({
    int? lipColor,
    double? lipIntensity,
    double? blush,
    double? teeth,
    double? eyeBrighten,
  }) {
    return Makeup(
      lipColor: lipColor ?? this.lipColor,
      lipIntensity: lipIntensity ?? this.lipIntensity,
      blush: blush ?? this.blush,
      teeth: teeth ?? this.teeth,
      eyeBrighten: eyeBrighten ?? this.eyeBrighten,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'lipColor': lipColor,
        'lipIntensity': lipIntensity,
        'blush': blush,
        'teeth': teeth,
        'eyeBrighten': eyeBrighten,
      };

  factory Makeup.fromMap(Map<String, dynamic> m) => Makeup(
        lipColor: m['lipColor'] as int,
        lipIntensity: (m['lipIntensity'] as num).toDouble(),
        blush: (m['blush'] as num).toDouble(),
        teeth: (m['teeth'] as num).toDouble(),
        eyeBrighten: (m['eyeBrighten'] as num).toDouble(),
      );
}

/// A small, flattering lipstick palette (0xRRGGBB).
const List<int> kLipPalette = <int>[
  0xC2185B, // classic rose
  0xB00020, // true red
  0x8E2D52, // berry
  0xD56A7A, // soft pink
  0xA0522D, // nude terracotta
  0x6D213C, // deep plum
];
