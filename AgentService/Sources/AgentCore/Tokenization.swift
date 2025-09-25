import Foundation

public protocol Tokenizer {
    func encode(_ text: String) -> [Int32]
    func decode(_ tokens: [Int32]) -> String
    static var bos: Int32? { get }
    static var eos: Int32? { get }
}

// Minimal placeholder tokenizer for scaffolding purposes only.
public struct BasicWhitespaceTokenizer: Tokenizer {
    public static let bos: Int32? = nil
    public static let eos: Int32? = nil

    public init() {}

    public func encode(_ text: String) -> [Int32] {
        // Extremely naive: 1 token per whitespace-separated word.
        // Maps words to incremental IDs for demo; not stable across runs.
        var map: [String: Int32] = [:]
        var next: Int32 = 1
        return text.split(whereSeparator: { $0.isWhitespace }).map { word in
            let key = String(word)
            if let id = map[key] { return id }
            defer { next += 1 }
            map[key] = next
            return next
        }
    }

    public func decode(_ tokens: [Int32]) -> String {
        // For placeholder purposes, just return a count summary.
        return "<\(tokens.count) tokens>"
    }
}

