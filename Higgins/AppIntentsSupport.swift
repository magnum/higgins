#if canImport(AppIntents)
import AppIntents

@available(macOS 13.0, *)
enum AppIntentsSupport {
    static func register() {}
}
#endif
