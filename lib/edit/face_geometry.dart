/// Face contours needed for makeup, expressed as flat point lists
/// `[x0,y0,x1,y1,...]` normalized to 0..1 of the source image so they scale to
/// any target resolution (preview or export). Serializable for isolate use.
class FaceGeometry {
  const FaceGeometry({
    required this.hasFace,
    this.lipsOuter = const [],
    this.mouthInner = const [],
    this.leftEye = const [],
    this.rightEye = const [],
    this.leftCheekX = 0,
    this.leftCheekY = 0,
    this.rightCheekX = 0,
    this.rightCheekY = 0,
    this.faceWidth = 0,
  });

  const FaceGeometry.none() : this(hasFace: false);

  final bool hasFace;
  final List<double> lipsOuter;
  final List<double> mouthInner;
  final List<double> leftEye;
  final List<double> rightEye;
  final double leftCheekX;
  final double leftCheekY;
  final double rightCheekX;
  final double rightCheekY;

  /// Normalized face width (0..1), used to size blush.
  final double faceWidth;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'hasFace': hasFace,
        'lipsOuter': lipsOuter,
        'mouthInner': mouthInner,
        'leftEye': leftEye,
        'rightEye': rightEye,
        'lcx': leftCheekX,
        'lcy': leftCheekY,
        'rcx': rightCheekX,
        'rcy': rightCheekY,
        'faceWidth': faceWidth,
      };

  factory FaceGeometry.fromMap(Map<String, dynamic> m) => FaceGeometry(
        hasFace: m['hasFace'] as bool,
        lipsOuter: (m['lipsOuter'] as List).cast<double>(),
        mouthInner: (m['mouthInner'] as List).cast<double>(),
        leftEye: (m['leftEye'] as List).cast<double>(),
        rightEye: (m['rightEye'] as List).cast<double>(),
        leftCheekX: (m['lcx'] as num).toDouble(),
        leftCheekY: (m['lcy'] as num).toDouble(),
        rightCheekX: (m['rcx'] as num).toDouble(),
        rightCheekY: (m['rcy'] as num).toDouble(),
        faceWidth: (m['faceWidth'] as num).toDouble(),
      );
}
