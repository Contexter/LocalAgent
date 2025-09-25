import Foundation

public struct SamplerOptions: Sendable {
    public var topK: Int?
    public var topP: Double?
    public var temperature: Double
    public init(topK: Int? = nil, topP: Double? = nil, temperature: Double = 1.0) {
        self.topK = topK
        self.topP = topP
        self.temperature = max(1e-6, temperature)
    }
}

public enum Sampling {
    public static func sample(from logits: [Float], options: SamplerOptions) -> Int {
        // Convert logits to probabilities with temperature
        let scaled = logits.map { Double($0) / options.temperature }
        let maxLogit = scaled.max() ?? 0
        var exps = scaled.map { exp($0 - maxLogit) }
        // Top-k
        if let k = options.topK, k > 0, k < exps.count {
            let sorted = exps.enumerated().sorted { $0.element > $1.element }
            let keep = Set(sorted.prefix(k).map { $0.offset })
            for i in exps.indices where !keep.contains(i) { exps[i] = 0 }
        }
        // Normalize
        var sum = exps.reduce(0, +)
        if sum == 0 { return exps.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0 }
        var probs = exps.map { $0 / sum }
        // Top-p (nucleus)
        if let p = options.topP, p > 0, p < 1 {
            let sorted = probs.enumerated().sorted { $0.element > $1.element }
            var accum = 0.0
            var cutoffIndex = sorted.count
            for (idx, entry) in sorted.enumerated() {
                accum += entry.element
                if accum >= p { cutoffIndex = idx + 1; break }
            }
            let keep = Set(sorted.prefix(cutoffIndex).map { $0.offset })
            for i in probs.indices where !keep.contains(i) { probs[i] = 0 }
            sum = probs.reduce(0, +)
            if sum > 0 { probs = probs.map { $0 / sum } }
        }
        // Draw
        let r = Double.random(in: 0..<1)
        var c = 0.0
        for (i, p) in probs.enumerated() {
            c += p
            if r <= c { return i }
        }
        return probs.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
    }
}

