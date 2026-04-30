import Foundation

struct WikiArticle: Codable, Equatable, Identifiable {
    let id: Int
    let title: String
    let extract: String

    var url: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "zh.wikipedia.org"
        components.path = "/w/index.php"
        components.queryItems = [
            URLQueryItem(name: "curid", value: "\(id)"),
            URLQueryItem(name: "variant", value: "zh-tw")
        ]
        return components.url
    }

    var summary: String {
        cleanedSummary.isEmpty ? "這個條目目前沒有摘要。" : cleanedSummary
    }

    var summaryForNotification: String {
        let oneLineSummary = summary.replacingOccurrences(of: "\n", with: " ")
        guard oneLineSummary.count > 140 else { return oneLineSummary }
        return oneLineSummary.truncatedAtSentenceBoundary()
    }

    var isSuitableForPush: Bool {
        cleanedSummary.count >= 80
            && !extract.hasHeavyCoordinateFragments
            && !extract.hasHeavyFormulaFragments
            && !extract.hasHeavyTableFragments
    }

    private var cleanedSummary: String {
        extract
            .removingWikipediaArtifacts()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    func removingWikipediaArtifacts() -> String {
        let withoutDisplayStyle = replacingOccurrences(
            of: #"\{\\displaystyle[^}]*\}"#,
            with: "",
            options: .regularExpression
        )
        let withoutTexEscapes = withoutDisplayStyle
            .replacingOccurrences(of: #"\\[a-zA-Z]+(?:\s*\{[^}]*\})?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\[,;!]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\{\|[\s\S]*?\|\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        let cleanedLines = withoutTexEscapes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                guard !line.looksLikeTableFragment else { return false }
                guard !line.looksLikeCoordinateFragment else { return false }
                guard !line.looksLikeFormulaFragment else { return false }
                guard line.count <= 3 else { return true }
                return line.range(of: #"[一-龥A-Za-z]{2,}"#, options: .regularExpression) != nil
            }

        return cleanedLines.joined(separator: "\n\n")
    }

    func truncatedAtSentenceBoundary() -> String {
        let maxLength = 140
        let preferredMinimumLength = 60
        let sentenceEndings = CharacterSet(charactersIn: "。！？!?")
        let scalars = Array(unicodeScalars)

        if let boundary = scalars.prefix(maxLength).lastIndex(where: { sentenceEndings.contains($0) }),
           boundary + 1 >= preferredMinimumLength {
            return String(String.UnicodeScalarView(scalars[...boundary]))
        }

        if let boundary = scalars.dropFirst(maxLength).firstIndex(where: { sentenceEndings.contains($0) }),
           boundary < scalars.count {
            return String(String.UnicodeScalarView(scalars[...boundary]))
        }

        return self
    }

    var hasHeavyCoordinateFragments: Bool {
        coordinateFragmentScore >= 3 || coordinateCharacterRatio > 0.12
    }

    var hasHeavyFormulaFragments: Bool {
        formulaCharacterRatio > 0.18
    }

    var hasHeavyTableFragments: Bool {
        tableFragmentScore >= 3
    }

    var looksLikeCoordinateFragment: Bool {
        coordinateFragmentScore >= 2 || coordinateCharacterRatio > 0.24
    }

    var looksLikeFormulaFragment: Bool {
        formulaCharacterRatio > 0.35
    }

    var looksLikeTableFragment: Bool {
        tableFragmentScore >= 1
    }

    var coordinateFragmentScore: Int {
        matchingCount(#"\d+(?:\.\d+)?[°º]\s*\d*(?:[′'’]\s*\d*(?:[″"])?\s*)?[NSEW東西南北]?"#)
            + matchingCount(#"[北南]緯|[東西]經|坐標|座標|經緯度|纬度|经度"#)
    }

    var coordinateCharacterRatio: Double {
        characterRatio(matching: CharacterSet(charactersIn: "°º′″'\"NSEW東西南北0123456789.,"))
    }

    var formulaCharacterRatio: Double {
        characterRatio(matching: CharacterSet(charactersIn: #"=+\-−*/÷^_{}[]()<>≤≥≈≠√∑∫∞→←↔∂∆πλμσΩ"#))
    }

    var tableFragmentScore: Int {
        matchingCount(#"\{\||\|\}|\|-"#)
            + matchingCount(#"\b(rowspan|colspan|style|class|scope|align|bgcolor|sortable|wikitable)\b"#)
            + matchingCount(#"^\s*[!|]\s*[^。！？\n]+$"#)
    }

    func matchingCount(_ pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }

        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.numberOfMatches(in: self, range: range)
    }

    func characterRatio(matching characterSet: CharacterSet) -> Double {
        guard !isEmpty else { return 0 }
        let matchedCount = unicodeScalars.filter { characterSet.contains($0) }.count
        return Double(matchedCount) / Double(unicodeScalars.count)
    }
}
