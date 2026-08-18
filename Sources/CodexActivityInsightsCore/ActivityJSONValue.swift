import CoreFoundation
import Foundation

public enum ActivityJSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ActivityJSONValue])
    case object([String: ActivityJSONValue])

    public var objectValue: [String: ActivityJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    public var arrayValue: [ActivityJSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    public var doubleValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard let doubleValue, doubleValue.isFinite,
              doubleValue >= Double(Int.min), doubleValue <= Double(Int.max)
        else {
            return nil
        }
        return Int(doubleValue)
    }

    public subscript(key: String) -> ActivityJSONValue? {
        objectValue?[key]
    }

    public static func parse(data: Data) throws -> ActivityJSONValue {
        do {
            return try fromAny(JSONSerialization.jsonObject(with: data))
        } catch let error as ActivityInsightsError {
            throw error
        } catch {
            throw ActivityInsightsError.invalidJSON(error.localizedDescription)
        }
    }

    public static func fromAny(_ value: Any) throws -> ActivityJSONValue {
        switch value {
        case _ as NSNull:
            return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        case let string as String:
            return .string(string)
        case let values as [Any]:
            return .array(try values.map(fromAny))
        case let values as [String: Any]:
            return .object(try values.mapValues(fromAny))
        default:
            throw ActivityInsightsError.invalidJSON("Unsupported JSON value \(type(of: value)).")
        }
    }

    public func anyValue() -> Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .number(value):
            return value
        case let .string(value):
            return value
        case let .array(values):
            return values.map { $0.anyValue() }
        case let .object(values):
            return values.mapValues { $0.anyValue() }
        }
    }
}

struct ActivityJSONLineDecoder: Sendable {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [Result<ActivityJSONValue, ActivityInsightsError>] {
        buffer.append(data)
        var results: [Result<ActivityJSONValue, ActivityInsightsError>] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }

            do {
                results.append(.success(try ActivityJSONValue.parse(data: line)))
            } catch let error as ActivityInsightsError {
                results.append(.failure(error))
            } catch {
                results.append(.failure(.invalidJSON(error.localizedDescription)))
            }
        }

        return results
    }
}
