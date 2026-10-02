import Foundation
class LanguageUtil {

    static let availableLanguages = [
        "auto", "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar",
        "he", "sv", "it", "id", "hi", "fi", "uk", "ml",
    ]

    static let parakeetV2Languages = ["en"]

    static let parakeetV3Languages = [
        "en", "de", "es", "ru", "fr", "pt", "pl", "nl", "sv", "it", "fi",
        "bg", "hr", "cs", "da", "el", "et", "hu", "lv", "lt", "mt", "ro", "sk", "sl", "uk",
    ]

    static let languageNames = [
        "auto": "Auto-detect",
        "en": "English",
        "zh": "Chinese",
        "de": "German",
        "es": "Spanish",
        "ru": "Russian",
        "ko": "Korean",
        "fr": "French",
        "ja": "Japanese",
        "pt": "Portuguese",
        "tr": "Turkish",
        "pl": "Polish",
        "ca": "Catalan",
        "nl": "Dutch",
        "ar": "Arabic",
        "he": "Hebrew",
        "sv": "Swedish",
        "it": "Italian",
        "id": "Indonesian",
        "hi": "Hindi",
        "fi": "Finnish",
        "bg": "Bulgarian",
        "hr": "Croatian",
        "cs": "Czech",
        "da": "Danish",
        "el": "Greek",
        "et": "Estonian",
        "hu": "Hungarian",
        "lv": "Latvian",
        "lt": "Lithuanian",
        "mt": "Maltese",
        "ro": "Romanian",
        "sk": "Slovak",
        "sl": "Slovenian",
        "uk": "Ukrainian",
        "ml": "Malayalam",
    ]

    static func supportedLanguages(engine: String, fluidAudioModelVersion: String) -> [String] {
        if engine == "cloudflare" { return cloudflareLanguages() }
        if engine == "whisper" { return localWhisperLanguages() }
        guard engine == "fluidaudio" else { return availableLanguages }
        return fluidAudioModelVersion == "v2" ? parakeetV2Languages : parakeetV3Languages
    }

    /// whisper.cpp publishes English-only weights beside the multilingual ones,
    /// named `ggml-<size>.en.bin`. Offering 23 languages for those produces
    /// English output whatever is picked, so the list follows the file on disk.
    static func localWhisperLanguages() -> [String] {
        let path = AppPreferences.shared.selectedWhisperModelPath ?? ""
        let name = (path as NSString).lastPathComponent.lowercased()
        return name.contains(".en.") ? ["en"] : availableLanguages
    }

    /// Cloud models disagree about languages: Nova-3 on Cloudflare accepts ten
    /// and hard errors on the rest, whisper-tiny-en is English only, Whisper
    /// base discards the setting entirely, and Hugging Face's speech pipeline
    /// refuses a language parameter outright. Offering one list for all of them
    /// produces failed dictations, so the selected provider's list wins.
    static func cloudflareLanguages() -> [String] {
        CloudProviderSelection.supportedLanguages(available: availableLanguages)
    }

    static func fallbackLanguage(engine: String) -> String {
        engine == "fluidaudio" ? "en" : "auto"
    }

    static func getSystemLanguage() -> String {
        if let preferredLanguage = Locale.preferredLanguages.first {
            let preferredLanguage = preferredLanguage.prefix(2).lowercased()
            return availableLanguages.contains(preferredLanguage) ? preferredLanguage : "en"
        } else {
            return "eng"
        }
    }
}
