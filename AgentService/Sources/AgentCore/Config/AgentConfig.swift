import Foundation

public struct AgentConfig: Codable {
    public let backend: String
    public let modelPath: String?
    public let host: String?
    public let port: Int?

    public static func load(from path: String? = nil) throws -> AgentConfig {
        let fm = FileManager.default
        let envPath = ProcessInfo.processInfo.environment["AGENT_CONFIG"]
        let searchPaths = [path, envPath, "agent-config.json"].compactMap { $0 }

        for p in searchPaths {
            if fm.fileExists(atPath: p), let data = fm.contents(atPath: p) {
                return try JSONDecoder().decode(AgentConfig.self, from: data)
            }
        }

        // Default config if none is found
        return AgentConfig(backend: "mock", modelPath: nil, host: "127.0.0.1", port: 8080)
    }
}
