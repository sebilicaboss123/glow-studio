/// Face-only "glow" retouch effects, all driven by landmarks.
class Glow {
  const Glow({this.radiance = 0, this.underEye = 0, this.lipGloss = 0});

  /// 0..1 — warm highlight on the cheekbones and nose bridge.
  final double radiance;

  /// 0..1 — brightens and evens the under-eye area (dark circles).
  final double underEye;

  /// 0..1 — glossy highlight on the lower lip.
  final double lipGloss;

  bool get isEmpty => radiance == 0 && underEye == 0 && lipGloss == 0;

  Glow copyWith({double? radiance, double? underEye, double? lipGloss}) => Glow(
        radiance: radiance ?? this.radiance,
        underEye: underEye ?? this.underEye,
        lipGloss: lipGloss ?? this.lipGloss,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'radiance': radiance,
        'underEye': underEye,
        'lipGloss': lipGloss,
      };

  factory Glow.fromMap(Map<String, dynamic> m) => Glow(
        radiance: (m['radiance'] as num).toDouble(),
        underEye: (m['underEye'] as num).toDouble(),
        lipGloss: (m['lipGloss'] as num).toDouble(),
      );
}
