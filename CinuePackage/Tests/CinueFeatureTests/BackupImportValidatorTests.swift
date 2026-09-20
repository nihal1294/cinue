import Foundation
import Testing
@testable import CinueFeature

struct BackupImportValidatorTests {
    @Test(arguments: serializedJSONEncodings)
    func prepareAndValidateSupportedJSONEncodings(_ encoding: SerializedJSONEncoding) throws {
        let validator = BackupImportValidator(policy: validatorTestPolicy(maximumJSONNestingDepth: 2))
        let json = #"{ "items": [1] }"#
        let preparedJSON = try validator.prepareAndValidateSerializedJSON(encoding.data(for: json))

        let object = try #require(preparedJSON.root as? [String: Any])
        #expect((object["items"] as? [Int]) == [1])
        #expect(preparedJSON.foundationData == encoding.foundationData(for: json))
    }

    @Test
    func returnsParsedRootAfterValidation() throws {
        let validator = BackupImportValidator(policy: validatorTestPolicy())
        let preparedJSON = try validator.prepareAndValidateSerializedJSON(
            Data(#"{ "app": "Cinue" }"#.utf8)
        )

        let object = try #require(preparedJSON.root as? [String: Any])
        #expect(object["app"] as? String == "Cinue")
        #expect(preparedJSON.foundationData == Data(#"{ "app": "Cinue" }"#.utf8))
    }

    @Test
    func acceptsJSONAtExactNestingLimit() throws {
        let scanner = JSONNestingScanner(policy: validatorTestPolicy(maximumJSONNestingDepth: 3))

        try scanner.validate(Data(#"[{ "nested": {} }]"#.utf8))
    }

    @Test
    func rejectsJSONAboveNestingLimitBeforeFoundationParsing() throws {
        let scanner = JSONNestingScanner(policy: validatorTestPolicy(maximumJSONNestingDepth: 3))

        do {
            try scanner.validate(Data(#"[{ "nested": { "deeper": {} } }]"#.utf8))
            Issue.record("Expected JSON nested beyond the policy limit to be rejected.")
        } catch let error as BackupImportError {
            #expect(error == .nestingLimitExceeded(actualDepth: 4, maximumDepth: 3))
        }
    }

    @Test
    func validatorRejectsNestingLimitBeforeLaterMalformedJSON() throws {
        let validator = BackupImportValidator(policy: validatorTestPolicy(maximumJSONNestingDepth: 3))

        do {
            _ = try validator.prepareAndValidateSerializedJSON(
                Data(#"[{ "nested": { "deeper": { malformed"#.utf8)
            )
            Issue.record("Expected the nesting limit to take precedence over later malformed JSON.")
        } catch let error as BackupImportError {
            #expect(error == .nestingLimitExceeded(actualDepth: 4, maximumDepth: 3))
        }
    }

    @Test
    func validatorMapsShallowFoundationGrammarFailureToMalformedJSON() {
        let validator = BackupImportValidator(policy: validatorTestPolicy())

        do {
            try validator.validateSerializedJSON(Data(#"{ unquoted: true }"#.utf8))
            Issue.record("Expected Foundation to reject shallow malformed JSON grammar.")
        } catch let error as BackupImportError {
            #expect(error == .malformedJSON)
        } catch {
            Issue.record("Expected BackupImportError.malformedJSON, got \(error).")
        }
    }

    @Test
    func ignoresEscapedQuotesBackslashesAndStructuralCharactersInsideStrings() throws {
        let scanner = JSONNestingScanner(policy: validatorTestPolicy(maximumJSONNestingDepth: 2))
        let json = #"["{ [ ] }", "quote: \"; slash: \\ ", { "nested": 1 }]"#

        try scanner.validate(Data(json.utf8))
    }

    @Test(arguments: malformedLexicalJSON)
    func rejectsMalformedLexicalJSON(_ json: Data) {
        let scanner = JSONNestingScanner(policy: validatorTestPolicy())

        do {
            try scanner.validate(json)
            Issue.record("Expected malformed lexical JSON to be rejected.")
        } catch let error as BackupImportError {
            #expect(error == .malformedJSON)
        } catch {
            Issue.record("Expected BackupImportError.malformedJSON, got \(error).")
        }
    }

    @Test
    func rejectsShortNoBOMUTF16ScalarSafely() {
        let scanner = JSONNestingScanner(policy: validatorTestPolicy())

        do {
            try scanner.validate(Data([0x00, 0x5B]))
            Issue.record("Expected an incomplete short UTF-16 scalar to be rejected.")
        } catch let error as BackupImportError {
            #expect(error == .malformedJSON)
        } catch {
            Issue.record("Expected BackupImportError.malformedJSON, got \(error).")
        }
    }
}

struct SerializedJSONEncoding: Sendable {
    let name: String
    let stringEncoding: String.Encoding
    let bom: Data

    func data(for json: String) -> Data {
        var data = bom
        data.append(foundationData(for: json))
        return data
    }

    func foundationData(for json: String) -> Data {
        json.data(using: stringEncoding)!
    }
}

extension SerializedJSONEncoding: CustomTestStringConvertible {
    var testDescription: String {
        name
    }
}

private let serializedJSONEncodings: [SerializedJSONEncoding] = [
    .init(name: "UTF-8 without BOM", stringEncoding: .utf8, bom: Data()),
    .init(name: "UTF-8 with BOM", stringEncoding: .utf8, bom: Data([0xEF, 0xBB, 0xBF])),
    .init(name: "UTF-16BE without BOM", stringEncoding: .utf16BigEndian, bom: Data()),
    .init(name: "UTF-16BE with BOM", stringEncoding: .utf16BigEndian, bom: Data([0xFE, 0xFF])),
    .init(name: "UTF-16LE without BOM", stringEncoding: .utf16LittleEndian, bom: Data()),
    .init(name: "UTF-16LE with BOM", stringEncoding: .utf16LittleEndian, bom: Data([0xFF, 0xFE])),
    .init(name: "UTF-32BE without BOM", stringEncoding: .utf32BigEndian, bom: Data()),
    .init(name: "UTF-32BE with BOM", stringEncoding: .utf32BigEndian, bom: Data([0x00, 0x00, 0xFE, 0xFF])),
    .init(name: "UTF-32LE without BOM", stringEncoding: .utf32LittleEndian, bom: Data()),
    .init(name: "UTF-32LE with BOM", stringEncoding: .utf32LittleEndian, bom: Data([0xFF, 0xFE, 0x00, 0x00]))
]

private let malformedLexicalJSON: [Data] = [
    Data(#"[}"#.utf8),
    Data(#"["unterminated"#.utf8),
    Data([0x5B, 0x22, 0x76, 0x61, 0x6C, 0x75, 0x65, 0x5C]),
    Data([0x00, 0x00, 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
]

private func validatorTestPolicy(maximumJSONNestingDepth: Int = 10) -> BackupImportPolicy {
    BackupImportPolicy(
        maximumFileBytes: 1_024,
        maximumTopLevelRecords: 10,
        maximumNestedEpisodes: 10,
        maximumAggregateRecords: 10,
        maximumStringUTF8Bytes: 1_024,
        maximumJSONNestingDepth: maximumJSONNestingDepth
    )
}
