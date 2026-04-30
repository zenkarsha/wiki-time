//
//  ContentView.swift
//  Wiki Time
//
//  Created by zenkarsha on 2026/4/29.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ArticleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            articleBody
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider()

            settings
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(store.article?.title ?? "Wiki Time")
                .font(.title2.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if store.hasUnreadArticle {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
            }

            Button {
                Task {
                    await store.refreshNow()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .help("重新取得條目")
        }
        .padding(14)
    }

    @ViewBuilder
    private var articleBody: some View {
        if store.isLoading, store.article == nil {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(32)
        } else if let article = store.article {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(article.summary)
                        .font(.system(size: 16))
                        .lineSpacing(5)
                        .textSelection(.enabled)

                    if article.url != nil {
                        Button {
                            store.openCurrentArticle()
                        } label: {
                            Text("繼續閱讀")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.link)
                        }
                        .buttonStyle(.plain)
                    }

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: 560)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)

                Text(store.errorMessage ?? "尚未取得條目")
                    .multilineTextAlignment(.center)

                Button("再試一次") {
                    Task {
                        await store.refreshNow()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("推送間隔", selection: $store.selectedInterval) {
                    ForEach(PushInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .frame(width: 150)

                if let countdown = store.pushCountdownText {
                    Text(countdown)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                
                Spacer()

                Button {
                    store.quitApp()
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("關閉 app")
            }

            if store.selectedInterval == .custom {
                HStack {
                    Text("自訂")
                        .foregroundStyle(.secondary)

                    Stepper(
                        value: $store.customMinutes,
                        in: 1...1440,
                        step: 1
                    ) {
                        Text("\(Int(store.customMinutes)) 分鐘")
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(14)
    }
}
