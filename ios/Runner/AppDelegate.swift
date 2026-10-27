import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "baji/video",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "load":
          guard let args = call.arguments as? [String: Any],
                let path = args["path"] as? String else {
            result(FlutterError(code: "bad_args", message: "path is required", details: nil))
            return
          }
          let maxSize = args["maxSize"] as? Int ?? 720
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              let value = try VideoFrames.load(path: path, maxSize: maxSize)
              DispatchQueue.main.async { result(value) }
            } catch {
              DispatchQueue.main.async {
                result(FlutterError(code: "video_error", message: error.localizedDescription, details: nil))
              }
            }
          }
        case "extract":
          guard let args = call.arguments as? [String: Any],
                let path = args["path"] as? String else {
            result(FlutterError(code: "bad_args", message: "path is required", details: nil))
            return
          }
          let intervalMs = args["intervalMs"] as? Int ?? 100
          let maxFrames = args["maxFrames"] as? Int ?? 30
          let maxDurationMs = args["maxDurationMs"] as? Int ?? 3000
          let size = args["size"] as? Int ?? 368
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              let frames = try VideoFrames.extract(
                path: path,
                intervalMs: intervalMs,
                maxFrames: maxFrames,
                maxDurationMs: maxDurationMs,
                size: size
              )
              DispatchQueue.main.async { result(frames) }
            } catch {
              DispatchQueue.main.async {
                result(FlutterError(code: "video_error", message: error.localizedDescription, details: nil))
              }
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return launched
  }
}

private enum VideoFrames {
  static func load(path: String, maxSize: Int) throws -> [String: Any] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let durationMs = Int64(max(0, CMTimeGetSeconds(asset.duration)) * 1000)
    let generator = makeGenerator(asset: asset)
    let time = CMTime(seconds: 0, preferredTimescale: 600)
    var result: [String: Any] = ["durationMs": durationMs]
    if let image = try? generator.copyCGImage(at: time, actualTime: nil),
       let preview = try? scalePreview(image, maxSize: maxSize) {
      result["preview"] = FlutterStandardTypedData(bytes: preview)
    }
    return result
  }

  static func extract(
    path: String,
    intervalMs: Int,
    maxFrames: Int,
    maxDurationMs: Int,
    size: Int
  ) throws -> [FlutterStandardTypedData] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let durationMs = Int64(max(0, CMTimeGetSeconds(asset.duration)) * 1000)
    let effective = min(durationMs, Int64(maxDurationMs))
    let count = effective > 0
      ? min(maxFrames, max(1, Int(effective) / max(1, intervalMs)))
      : 1
    let generator = makeGenerator(asset: asset)
    var output: [FlutterStandardTypedData] = []
    output.reserveCapacity(count)
    for index in 0 ..< count {
      let time = CMTime(value: Int64(index * intervalMs), timescale: 1000)
      guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil),
            let jpeg = squareJpeg(cgImage, size: size) else { continue }
      output.append(FlutterStandardTypedData(bytes: jpeg))
    }
    return output
  }

  private static func makeGenerator(asset: AVAsset) -> AVAssetImageGenerator {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return generator
  }

  private static func squareJpeg(_ image: CGImage, size: Int) -> Data? {
    let side = min(image.width, image.height)
    guard side > 0 else { return nil }
    let rect = CGRect(
      x: (image.width - side) / 2,
      y: (image.height - side) / 2,
      width: side,
      height: side
    )
    guard let cropped = image.cropping(to: rect) else { return nil }
    let target = max(1, size)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target))
    let output = renderer.image { _ in
      UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: target, height: target))
    }
    return output.jpegData(compressionQuality: 0.9)
  }

  private static func scalePreview(_ image: CGImage, maxSize: Int) throws -> Data {
    let width = image.width
    let height = image.height
    let scale = min(1.0, Double(maxSize) / Double(max(width, height)))
    let target = CGSize(
      width: max(1, Int(Double(width) * scale)),
      height: max(1, Int(Double(height) * scale))
    )
    let renderer = UIGraphicsImageRenderer(size: target)
    let output = renderer.image { _ in
      UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: target))
    }
    guard let data = output.jpegData(compressionQuality: 0.9) else {
      throw NSError(
        domain: "baji.video",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "无法编码视频预览"]
      )
    }
    return data
  }
}
