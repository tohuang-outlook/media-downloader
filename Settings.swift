import Foundation

/// Persists all user-configurable app settings via UserDefaults.
/// Call `save()` whenever a field changes; call the static properties on launch to restore.
public struct Settings {

    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key: String {
        case outputFolder
        case ffmpegPath
        case ffprobePath
        case whisperPath
        case whisperModel
        case translateProvider
        case translateModel
        case fontPath
        case lastSourceFolder
    }

    // MARK: - Properties

    public static var outputFolder: String {
        get { defaults.string(forKey: Key.outputFolder.rawValue) ?? "\(NSHomeDirectory())/Downloads" }
        set { defaults.set(newValue, forKey: Key.outputFolder.rawValue) }
    }

    public static var ffmpegPath: String {
        get { defaults.string(forKey: Key.ffmpegPath.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.ffmpegPath.rawValue) }
    }

    public static var ffprobePath: String {
        get { defaults.string(forKey: Key.ffprobePath.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.ffprobePath.rawValue) }
    }

    public static var whisperPath: String {
        get { defaults.string(forKey: Key.whisperPath.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.whisperPath.rawValue) }
    }

    public static var whisperModel: String {
        get { defaults.string(forKey: Key.whisperModel.rawValue) ?? "turbo" }
        set { defaults.set(newValue, forKey: Key.whisperModel.rawValue) }
    }

    public static var translateProvider: String {
        get { defaults.string(forKey: Key.translateProvider.rawValue) ?? "OpenAI" }
        set { defaults.set(newValue, forKey: Key.translateProvider.rawValue) }
    }

    public static var translateModel: String {
        get { defaults.string(forKey: Key.translateModel.rawValue) ?? "gpt-4.1-mini" }
        set { defaults.set(newValue, forKey: Key.translateModel.rawValue) }
    }

    /// Path to the CJK font used for subtitle burn-in.
    /// Falls back to the bundled Noto font path if the system STHeiti is absent.
    public static var fontPath: String {
        get {
            if let saved = defaults.string(forKey: Key.fontPath.rawValue), !saved.isEmpty {
                return saved
            }
            return preferredSystemFont()
        }
        set { defaults.set(newValue, forKey: Key.fontPath.rawValue) }
    }

    public static var lastSourceFolder: String {
        get { defaults.string(forKey: Key.lastSourceFolder.rawValue) ?? NSHomeDirectory() }
        set { defaults.set(newValue, forKey: Key.lastSourceFolder.rawValue) }
    }

    // MARK: - Font resolution

    /// Returns the best available CJK font path, preferring the system font,
    /// then a bundled fallback, then an empty string (caller should warn the user).
    public static func preferredSystemFont() -> String {
        let candidates = [
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/Library/Fonts/Arial Unicode MS.ttf",
            // Bundled fallback — place NotoSansCJKtc-Regular.otf in the app bundle
            Bundle.main.path(forResource: "NotoSansCJKtc-Regular", ofType: "otf") ?? ""
        ]
        return candidates.first { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) } ?? ""
    }

    /// Default model name for a given provider.
    public static func defaultModel(for provider: String) -> String {
        switch provider {
        case "DeepSeek":    return "deepseek-chat"
        case "Kimi 2.5":   return "moonshot-v1-8k"
        case "Google Gemini": return "gemini-2.5-flash"
        default:            return "gpt-4.1-mini"
        }
    }
}
