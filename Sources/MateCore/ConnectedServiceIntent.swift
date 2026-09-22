import Foundation

/// Routes only explicit requests naming an already reviewed service. This
/// selects a review screen; neither the phrase nor a model authorizes payment.
public enum ConnectedServiceIntent {
    public static func requestsList(_ text: String) -> Bool {
        let value = normalized(text)
        return ["show services", "show connected services", "open services", "サービス一覧", "接続サービス", "サービスを見せて"].contains(value)
    }
    public static func requestedName(_ text: String, names: [String]) -> String? {
        let value = normalized(text)
        let matches = names.filter { name in
            let n = normalized(name)
            guard !n.isEmpty else { return false }
            return ["use \(n)", "please use \(n)", "can you use \(n)", "open \(n)",
                    "\(n)を使って", "\(n)を使ってください", "\(n)を開いて", "\(n)をお願い"].contains(value)
        }
        return matches.count == 1 ? matches.first : nil
    }
    private static func normalized(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
