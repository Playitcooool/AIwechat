import AppKit
import CoreGraphics

enum ScreenCaptureError: Error, LocalizedError {
    case noDisplayFound
    case captureFailed
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: return "未找到显示器"
        case .captureFailed: return "屏幕截图失败"
        case .imageConversionFailed: return "图片转换失败"
        }
    }
}

struct ScreenCapture {
    /// 截取整个屏幕
    static func captureScreen() throws -> Data {
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)

        guard let cgImage = CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw ScreenCaptureError.captureFailed
        }

        return try imageToData(cgImage)
    }

    /// 截取指定窗口（通过窗口名称）
    static func captureWindow(named name: String) throws -> Data {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        for windowInfo in windowList {
            guard let windowName = windowInfo[kCGWindowName as String] as? String else { continue }

            if windowName.contains(name) {
                guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                      let x = bounds["X"],
                      let y = bounds["Y"],
                      let width = bounds["Width"],
                      let height = bounds["Height"] else { continue }

                let rect = CGRect(x: x, y: y, width: width, height: height)

                guard let cgImage = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
                    throw ScreenCaptureError.captureFailed
                }

                return try imageToData(cgImage)
            }
        }

        // 如果找不到窗口，返回全屏截图
        return try captureScreen()
    }

    /// 将 CGImage 转换为 PNG Data
    private static func imageToData(_ cgImage: CGImage) throws -> Data {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw ScreenCaptureError.imageConversionFailed
        }
        return pngData
    }

    /// 将 Data 转换为 base64 字符串（用于 API 请求）
    static func imageToBase64(_ data: Data) -> String {
        return data.base64EncodedString()
    }

    /// 截取屏幕并返回 base64 字符串
    static func captureScreenBase64() throws -> String {
        let data = try captureScreen()
        return "data:image/png;base64,\(imageToBase64(data))"
    }

    /// 截取窗口并返回 base64 字符串
    static func captureWindowBase64(named name: String) throws -> String {
        let data = try captureWindow(named: name)
        return "data:image/png;base64,\(imageToBase64(data))"
    }
}
