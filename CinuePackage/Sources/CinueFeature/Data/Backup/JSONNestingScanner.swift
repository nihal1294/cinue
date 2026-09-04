import Foundation

struct JSONNestingScanner {
    private let maximumNestingDepth: Int

    init(policy: BackupImportPolicy) {
        maximumNestingDepth = policy.maximumJSONNestingDepth
    }

    func validate(_ data: Data) throws {
        _ = try foundationCompatibleData(from: data)
    }

    func foundationCompatibleData(from data: Data) throws -> Data {
        let encoding = JSONTextEncoding.detect(in: data)
        let payload = Data(data.dropFirst(encoding.bomByteCount))

        guard let text = String(data: payload, encoding: encoding.stringEncoding) else {
            throw BackupImportError.malformedJSON
        }

        var expectedClosers: [Unicode.Scalar] = []
        var isInsideString = false
        var isEscaped = false

        for scalar in text.unicodeScalars {
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if scalar.value == 0x5C {
                    isEscaped = true
                } else if scalar.value == 0x22 {
                    isInsideString = false
                }
                continue
            }

            switch scalar.value {
            case 0x22:
                isInsideString = true
            case 0x7B:
                try appendExpectedCloser(0x7D, to: &expectedClosers)
            case 0x5B:
                try appendExpectedCloser(0x5D, to: &expectedClosers)
            case 0x7D, 0x5D:
                guard expectedClosers.last?.value == scalar.value else {
                    throw BackupImportError.malformedJSON
                }
                expectedClosers.removeLast()
            default:
                break
            }
        }

        guard isInsideString == false, expectedClosers.isEmpty else {
            throw BackupImportError.malformedJSON
        }

        return payload
    }

    private func appendExpectedCloser(
        _ closer: UInt32,
        to expectedClosers: inout [Unicode.Scalar]
    ) throws {
        let depth = expectedClosers.count + 1
        guard depth <= maximumNestingDepth else {
            throw BackupImportError.nestingLimitExceeded(
                actualDepth: depth,
                maximumDepth: maximumNestingDepth
            )
        }

        expectedClosers.append(Unicode.Scalar(closer)!)
    }
}

private enum JSONTextEncoding {
    case utf8(bomByteCount: Int)
    case utf16BigEndian(bomByteCount: Int)
    case utf16LittleEndian(bomByteCount: Int)
    case utf32BigEndian(bomByteCount: Int)
    case utf32LittleEndian(bomByteCount: Int)

    var bomByteCount: Int {
        switch self {
        case let .utf8(bomByteCount),
             let .utf16BigEndian(bomByteCount),
             let .utf16LittleEndian(bomByteCount),
             let .utf32BigEndian(bomByteCount),
             let .utf32LittleEndian(bomByteCount):
            bomByteCount
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8:
            .utf8
        case .utf16BigEndian:
            .utf16BigEndian
        case .utf16LittleEndian:
            .utf16LittleEndian
        case .utf32BigEndian:
            .utf32BigEndian
        case .utf32LittleEndian:
            .utf32LittleEndian
        }
    }

    static func detect(in data: Data) -> Self {
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return .utf32BigEndian(bomByteCount: 4)
        }
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return .utf32LittleEndian(bomByteCount: 4)
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return .utf8(bomByteCount: 3)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return .utf16BigEndian(bomByteCount: 2)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return .utf16LittleEndian(bomByteCount: 2)
        }

        guard data.count >= 4 else {
            return .utf8(bomByteCount: 0)
        }

        let prefix = Array(data.prefix(4))
        if prefix[0] == 0x00, prefix[1] == 0x00, prefix[2] == 0x00 {
            return .utf32BigEndian(bomByteCount: 0)
        }
        if prefix[1] == 0x00, prefix[2] == 0x00, prefix[3] == 0x00 {
            return .utf32LittleEndian(bomByteCount: 0)
        }
        if prefix[0] == 0x00, prefix[2] == 0x00 {
            return .utf16BigEndian(bomByteCount: 0)
        }
        if prefix[1] == 0x00, prefix[3] == 0x00 {
            return .utf16LittleEndian(bomByteCount: 0)
        }

        return .utf8(bomByteCount: 0)
    }
}
