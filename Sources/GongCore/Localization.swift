import Foundation

/// Localized text from the app bundle's `<lang>.lproj/Localizable.strings`; the English text is the key, so a missing
/// translation (and the test bundle) shows English. With arguments the key is a format (`%d`, `%@`, `%1$@`…).
public func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: .main, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}

/// Upper case in the app's language (Turkish i → İ, not I).
public func upperLocalized(_ s: String) -> String {
    s.uppercased(with: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
}
