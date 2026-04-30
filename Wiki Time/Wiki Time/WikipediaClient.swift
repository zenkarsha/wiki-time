import Foundation

struct WikipediaClient {
    private let endpoint = URL(string: "https://zh.wikipedia.org/w/api.php?action=query&generator=random&grnnamespace=0&grnlimit=5&grnfilterredir=nonredirects&prop=extracts%7Ccategories&cllimit=max&exintro=1&explaintext=1&format=json&formatversion=2&variant=zh-tw&uselang=zh-tw&converttitles=1")!

    func fetchRandomArticle(excluding excludedPageIDs: Set<Int>) async throws -> WikiArticle {
        for _ in 0..<8 {
            let pages = try await fetchCandidatePages()

            if let article = pages.compactMap({ page -> WikiArticle? in
                guard !excludedPageIDs.contains(page.pageid),
                      !page.hasExcludedCategory
                else {
                    return nil
                }

                let article = WikiArticle(
                    id: page.pageid,
                    title: page.title.convertedToTraditionalChinese(),
                    extract: page.extract.convertedToTraditionalChinese()
                )

                return article.isSuitableForPush ? article : nil
            }).first {
                return article
            }
        }

        throw WikipediaClientError.emptyResponse
    }

    private func fetchCandidatePages() async throws -> [WikipediaRandomResponse.Page] {
        let (data, response) = try await URLSession.shared.data(from: endpoint)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw WikipediaClientError.badResponse
        }

        let decoded = try JSONDecoder().decode(WikipediaRandomResponse.self, from: data)
        return decoded.query.pages
    }
}

private struct WikipediaRandomResponse: Decodable {
    let query: Query

    struct Query: Decodable {
        let pages: [Page]
    }

    struct Page: Decodable {
        let pageid: Int
        let title: String
        let extract: String
        let categories: [Category]?

        var hasExcludedCategory: Bool {
            categories?.contains { category in
                let title = category.title.convertedToTraditionalChinese()
                return Self.excludedCategoryKeywords.contains { title.contains($0) }
            } ?? false
        }

        private static let excludedCategoryKeywords = [
            "人物",
            "年份",
            "年代",
            "日期",
            "各日",
            "各月",
            "各年",
            "生日",
            "逝世",
            "出生",
            "消歧義",
            "列表",
            "模板"
        ]
    }

    struct Category: Decodable {
        let title: String
    }
}

enum WikipediaClientError: LocalizedError {
    case badResponse
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .badResponse:
            "Wikipedia API 回應失敗。"
        case .emptyResponse:
            "Wikipedia API 沒有回傳條目。"
        }
    }
}

private extension String {
    func convertedToTraditionalChinese() -> String {
        applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) ?? self
    }
}
