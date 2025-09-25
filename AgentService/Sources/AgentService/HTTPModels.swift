import Foundation

// Generic JSON value to carry OpenAI-like JSON schema and arguments blobs.
public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .number(let n):
            try container.encode(n)
        case .string(let s):
            try container.encode(s)
        case .array(let a):
            try container.encode(a)
        case .object(let o):
            try container.encode(o)
        }
    }
}

// OpenAI-style chat message
public struct ChatMessage: Codable, Equatable {
    public let role: String
    public let content: String?
    public let name: String?

    public init(role: String, content: String?, name: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
    }
}

// Function definition compatible with OpenAI function calling
public struct FunctionDefinition: Codable, Equatable {
    public struct ParameterSchema: Codable, Equatable {
        public let type: String
        public let properties: [String: JSONValue]?
        public let required: [String]?
        public init(type: String, properties: [String: JSONValue]? = nil, required: [String]? = nil) {
            self.type = type
            self.properties = properties
            self.required = required
        }
    }
    public let name: String
    public let description: String?
    public let parameters: ParameterSchema?
}

// function_call directive sent with the request
public enum FunctionCallOption: Codable, Equatable {
    case auto
    case none
    case force(name: String)

    private enum CodingKeys: String, CodingKey { case name }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            switch s.lowercased() {
            case "auto": self = .auto
            case "none": self = .none
            default: self = .force(name: s)
            }
        } else if let o = try? decoder.decode([String: String].self), let name = o[CodingKeys.name.rawValue] {
            self = .force(name: name)
        } else {
            self = .auto
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .none: try container.encode("none")
        case .force(let name): try container.encode([CodingKeys.name.rawValue: name])
        }
    }
}

// Chat request body (OpenAI compatible subset)
public struct ChatRequest: Codable, Equatable {
    public let model: String?
    public let messages: [ChatMessage]
    public let functions: [FunctionDefinition]?
    public let function_call: FunctionCallOption?

    public init(model: String? = nil,
                messages: [ChatMessage],
                functions: [FunctionDefinition]? = nil,
                function_call: FunctionCallOption? = nil) {
        self.model = model
        self.messages = messages
        self.functions = functions
        self.function_call = function_call
    }
}

// Assistant function call output
public struct FunctionCall: Codable, Equatable {
    public let name: String
    public let arguments: String // as JSON string per OpenAI schema
}

// Assistant message in response
public struct AssistantMessage: Codable, Equatable {
    public let role: String
    public let content: String?
    public let function_call: FunctionCall?
}

public struct ChatChoice: Codable, Equatable {
    public let index: Int
    public let message: AssistantMessage
    public let finish_reason: String
}

public struct ChatResponse: Codable, Equatable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String?
    public let choices: [ChatChoice]
}

