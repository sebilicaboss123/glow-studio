import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FaceVisionPlugin") {
      FaceVisionPlugin.register(with: registrar)
    }
  }
}

/// Native face detection using Apple's Vision framework, exposed to Dart over
/// the `glow_studio/face` method channel. Returns face geometry (lips, eyes,
/// cheeks, face width) normalized to 0..1 of the image with a top-left origin.
public class FaceVisionPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "glow_studio/face", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(FaceVisionPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "detect",
      let args = call.arguments as? [String: Any],
      let path = args["path"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    // Vision work off the platform thread; reply back on the main thread.
    DispatchQueue.global(qos: .userInitiated).async {
      let out = FaceVisionPlugin.detectFace(path: path)
      DispatchQueue.main.async { result(out) }
    }
  }

  private static func detectFace(path: String) -> [String: Any] {
    guard let image = UIImage(contentsOfFile: path) else {
      return ["hasFace": false, "debug": "vision: load failed"]
    }
    guard let cg = uprightCGImage(image) else {
      return ["hasFace": false, "debug": "vision: cgImage nil"]
    }
    let w = cg.width
    let h = cg.height
    if w == 0 || h == 0 {
      return ["hasFace": false, "debug": "vision: zero size"]
    }

    let request = VNDetectFaceLandmarksRequest()
    // The image is already baked upright (Dart bakes the preview; uprightCGImage
    // bakes any EXIF-rotated source), so Vision reads it as .up.
    let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
    do {
      try handler.perform([request])
    } catch {
      return ["hasFace": false, "debug": "vision: perform \(error.localizedDescription)"]
    }

    guard let faces = request.results, !faces.isEmpty else {
      return ["hasFace": false, "debug": "vision: 0 faces | \(w)x\(h)"]
    }

    // Largest face.
    let face = faces.max {
      ($0.boundingBox.width * $0.boundingBox.height)
        < ($1.boundingBox.width * $1.boundingBox.height)
    }!

    let size = CGSize(width: w, height: h)

    // Vision points: pixels, origin bottom-left. Convert to normalized 0..1
    // with a top-left origin (flip y) to match the Dart editing pipeline.
    func flat(_ region: VNFaceLandmarkRegion2D?) -> [Double] {
      guard let region = region, region.pointCount > 0 else { return [] }
      var out: [Double] = []
      out.reserveCapacity(region.pointCount * 2)
      for p in region.pointsInImage(imageSize: size) {
        out.append(Double(p.x) / Double(w))
        out.append(1.0 - Double(p.y) / Double(h))
      }
      return out
    }

    let lm = face.landmarks
    let lipsOuter = flat(lm?.outerLips)
    let mouthInner = flat(lm?.innerLips)
    let leftEye = flat(lm?.leftEye)
    let rightEye = flat(lm?.rightEye)

    // Bounding box: normalized, origin bottom-left → top-left.
    let bb = face.boundingBox
    let faceWidth = Double(bb.width)
    let bx = Double(bb.minX)
    let topY = 1.0 - Double(bb.maxY)
    let bh = Double(bb.height)
    let cheekY = topY + bh * 0.62

    return [
      "hasFace": true,
      "lipsOuter": lipsOuter,
      "mouthInner": mouthInner,
      "leftEye": leftEye,
      "rightEye": rightEye,
      "lcx": bx + faceWidth * 0.25,
      "lcy": cheekY,
      "rcx": bx + faceWidth * 0.75,
      "rcy": cheekY,
      "faceWidth": faceWidth,
      "debug":
        "vision ok faces=\(faces.count) lips=\(lipsOuter.count / 2) eyeL=\(leftEye.count / 2) eyeR=\(rightEye.count / 2)",
    ]
  }

  /// Returns a CGImage with any EXIF/UIImage orientation baked into the pixels,
  /// so callers can always treat it as `.up`.
  private static func uprightCGImage(_ image: UIImage) -> CGImage? {
    if image.imageOrientation == .up {
      return image.cgImage
    }
    let renderer = UIGraphicsImageRenderer(size: image.size)
    let normalized = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    return normalized.cgImage
  }
}
