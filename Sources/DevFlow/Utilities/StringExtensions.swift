import Foundation

extension String {
    /// Returns the string with any leading URL scheme (e.g. "https://", "http://") removed,
    /// plus leading/trailing slashes and spaces stripped.
    var strippingURLScheme: String {
        var result = self
        for scheme in ["https://", "http://"] {
            if result.lowercased().hasPrefix(scheme) {
                result = String(result.dropFirst(scheme.count))
                break
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }
}
