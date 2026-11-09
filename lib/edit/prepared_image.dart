import 'dart:typed_data';

/// A photo ready to edit: a downscaled preview (with known pixel size) plus the
/// original file path, which is re-processed at full resolution on export.
class PreparedImage {
  const PreparedImage({
    required this.preview,
    required this.width,
    required this.height,
    required this.sourcePath,
  });

  final Uint8List preview;
  final int width;
  final int height;
  final String sourcePath;
}
