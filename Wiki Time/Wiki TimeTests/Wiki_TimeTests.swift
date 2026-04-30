//
//  Wiki_TimeTests.swift
//  Wiki TimeTests
//
//  Created by zenkarsha on 2026/4/29.
//

import Foundation
import Testing
@testable import Wiki_Time

struct Wiki_TimeTests {
    @Test func pushIntervalLabelsAndSecondsAreStable() {
        let expectations: [(PushInterval, String, TimeInterval)] = [
            (.oneMinute, "1 分鐘", 60),
            (.fiveMinutes, "5 分鐘", 5 * 60),
            (.tenMinutes, "10 分鐘", 10 * 60),
            (.fifteenMinutes, "15 分鐘", 15 * 60),
            (.thirtyMinutes, "30 分鐘", 30 * 60),
            (.fortyFiveMinutes, "45 分鐘", 45 * 60),
            (.oneHour, "1 小時", 60 * 60),
            (.twoHours, "2 小時", 2 * 60 * 60),
            (.threeHours, "3 小時", 3 * 60 * 60),
            (.fourHours, "4 小時", 4 * 60 * 60),
            (.custom, "自訂", 0)
        ]

        #expect(PushInterval.allCases.count == expectations.count)

        for (interval, label, seconds) in expectations {
            #expect(interval.id == interval.rawValue)
            #expect(interval.label == label)
            #expect(interval.seconds == seconds)
        }
    }

    @Test func wikiArticleBuildsTraditionalChineseUrl() throws {
        let article = WikiArticle(id: 42, title: "測試", extract: "足夠長的摘要內容。")

        let url = try #require(article.url)

        #expect(url.scheme == "https")
        #expect(url.host == "zh.wikipedia.org")
        #expect(url.path == "/w/index.php")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "curid", value: "42"),
            URLQueryItem(name: "variant", value: "zh-tw")
        ])
    }

    @Test func summaryRemovesWikipediaArtifactsAndEmptyLines() {
        let article = WikiArticle(
            id: 1,
            title: "條目",
            extract: """
            <span>應移除標籤</span>第一段摘要。

            {| class="wikitable"
            |-
            | 表格內容
            |}
            \\displaystyle{x+y}
            第二段摘要含有有效文字。
            """
        )

        #expect(article.summary == "應移除標籤第一段摘要。\n\n第二段摘要含有有效文字。")
    }

    @Test func summaryFallsBackWhenCleanedExtractIsEmpty() {
        let article = WikiArticle(id: 1, title: "空摘要", extract: " \n {| class=\"wikitable\" |}")

        #expect(article.summary == "這個條目目前沒有摘要。")
    }

    @Test func notificationSummaryCollapsesNewlinesAndCutsAtSentenceBoundary() {
        let longFirstSentence = String(
            repeating: "這是一段沒有結尾標點的通知摘要內容",
            count: 9
        ) + "。"
        let article = WikiArticle(
            id: 1,
            title: "長摘要",
            extract: """
            \(longFirstSentence)

            第二句不應該出現在通知摘要裡。
            """
        )

        #expect(article.summaryForNotification.contains("\n") == false)
        #expect(article.summaryForNotification.hasSuffix("。"))
        #expect(article.summaryForNotification.count > 140)
        #expect(!article.summaryForNotification.contains("第二句"))
    }

    @Test func suitabilityRejectsShortCoordinateFormulaAndTableHeavyExtracts() {
        let goodExtract = String(repeating: "這是一段適合推送的百科摘要，內容具備足夠長度，描述清楚且沒有雜訊。", count: 4)
        let shortExtract = "太短的摘要。"
        let coordinateExtract = String(repeating: "25°02′N 121°38′E 北緯 東經 座標 ", count: 8)
        let formulaExtract = String(repeating: "x = y + z * (a - b) / c ≤ d ≥ e √ ∑ ∫ ∞ ", count: 8)
        let tableExtract = """
        這段文字本身足夠長，但夾雜太多表格語法，應該被排除避免推送品質很差。
        {| class="wikitable"
        |-
        ! 標題
        | 內容
        |}
        """

        #expect(WikiArticle(id: 1, title: "好條目", extract: goodExtract).isSuitableForPush)
        #expect(!WikiArticle(id: 2, title: "短條目", extract: shortExtract).isSuitableForPush)
        #expect(!WikiArticle(id: 3, title: "座標條目", extract: coordinateExtract).isSuitableForPush)
        #expect(!WikiArticle(id: 4, title: "公式條目", extract: formulaExtract).isSuitableForPush)
        #expect(!WikiArticle(id: 5, title: "表格條目", extract: tableExtract).isSuitableForPush)
    }
}
