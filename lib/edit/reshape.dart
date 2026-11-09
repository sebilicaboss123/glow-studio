/// Landmark-based geometry reshaping (subtle liquify).
class Reshape {
  const Reshape({this.faceSlim = 0, this.eyeSize = 0});

  /// 0..1 — horizontal slimming of the jaw/cheeks.
  final double faceSlim;

  /// 0..1 — enlargement around each eye.
  final double eyeSize;

  bool get isEmpty => faceSlim == 0 && eyeSize == 0;

  Reshape copyWith({double? faceSlim, double? eyeSize}) => Reshape(
        faceSlim: faceSlim ?? this.faceSlim,
        eyeSize: eyeSize ?? this.eyeSize,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'faceSlim': faceSlim,
        'eyeSize': eyeSize,
      };

  factory Reshape.fromMap(Map<String, dynamic> m) => Reshape(
        faceSlim: (m['faceSlim'] as num).toDouble(),
        eyeSize: (m['eyeSize'] as num).toDouble(),
      );
}
