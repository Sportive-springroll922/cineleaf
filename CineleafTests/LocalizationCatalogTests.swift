import Foundation
import XCTest

final class LocalizationCatalogTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testEveryStringHasEnglishAndSpanish() throws {
        let strings = try catalogStrings()
        XCTAssertFalse(strings.isEmpty)
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            for language in ["en", "es"] {
                let localization = try XCTUnwrap(localizations[language] as? [String: Any], "\(key): \(language)")
                XCTAssertTrue(hasCompleteTranslation(localization), "Incomplete translation: \(key) [\(language)]")
            }
        }
    }

    func testFormatArgumentsMatchBetweenTranslations() throws {
        for (key, rawEntry) in try catalogStrings() {
            let entry = try XCTUnwrap(rawEntry as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let english = formatSignatures(in: try XCTUnwrap(localizations["en"] as? [String: Any]))
            let spanish = formatSignatures(in: try XCTUnwrap(localizations["es"] as? [String: Any]))
            XCTAssertEqual(english, spanish, "Format mismatch: \(key)")
        }
    }

    func testPluralRulesContainOneAndOther() throws {
        let entry = try XCTUnwrap(try catalogStrings()["timeline.clip_count"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        for language in ["en", "es"] {
            let localization = try XCTUnwrap(localizations[language] as? [String: Any])
            let variations = try XCTUnwrap(localization["variations"] as? [String: Any])
            let plural = try XCTUnwrap(variations["plural"] as? [String: Any])
            XCTAssertNotNil(plural["one"])
            XCTAssertNotNil(plural["other"])
        }
    }

    func testVisibleLiteralKeysExistOrAreTechnicalNames() throws {
        let catalogKeys = Set(try catalogStrings().keys)
        let allowed: Set<String> = ["Cineleaf", "720p", "1080p", "1440p", "4K", "H.264", "HEVC", "MP4", "MOV", "/"]
        let expression = try NSRegularExpression(
            pattern: #"(?:Text|Button|Label|Toggle|Picker|Section|DisclosureGroup|Link|Window)\(\s*\"([^\"]+)\""#
        )
        let sourceRoot = root.appendingPathComponent("Cineleaf")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil))
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in expression.matches(in: source, range: range) {
                guard let matchRange = Range(match.range(at: 1), in: source) else { continue }
                let literal = String(source[matchRange])
                if allowed.contains(literal) { continue }
                if literal.contains(#"\("#) {
                    let prefix = literal.components(separatedBy: #"\("#)[0].trimmingCharacters(in: .whitespaces)
                    XCTAssertTrue(catalogKeys.contains(where: { $0.hasPrefix(prefix) }), "Missing interpolated key: \(literal) in \(file.lastPathComponent)")
                } else {
                    XCTAssertTrue(catalogKeys.contains(literal), "Missing key: \(literal) in \(file.lastPathComponent)")
                }
            }
        }
    }

    private func catalogStrings() throws -> [String: Any] {
        let url = root.appendingPathComponent("Cineleaf/Resources/Localizable.xcstrings")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(object["strings"] as? [String: Any])
    }

    private func hasCompleteTranslation(_ localization: [String: Any]) -> Bool {
        if let unit = localization["stringUnit"] as? [String: Any] {
            return unit["state"] as? String == "translated" && !(unit["value"] as? String ?? "").isEmpty
        }
        guard let variations = localization["variations"] as? [String: Any],
              let plural = variations["plural"] as? [String: Any] else { return false }
        return ["one", "other"].allSatisfy { category in
            guard let value = plural[category] as? [String: Any],
                  let unit = value["stringUnit"] as? [String: Any] else { return false }
            return unit["state"] as? String == "translated" && !(unit["value"] as? String ?? "").isEmpty
        }
    }

    private func formatSignatures(in localization: [String: Any]) -> [String] {
        let values: [String]
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            values = [value]
        } else if let variations = localization["variations"] as? [String: Any],
                  let plural = variations["plural"] as? [String: Any] {
            values = plural.values.compactMap {
                (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            }
        } else {
            values = []
        }
        guard let expression = try? NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|@|d|f)"#) else {
            return []
        }
        return values.flatMap { value in
            expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
                Range(match.range, in: value).map { String(value[$0]).replacingOccurrences(of: #"%\d+\$"#, with: "%", options: .regularExpression) }
            }
        }.sorted()
    }
}
