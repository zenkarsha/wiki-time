import AppKit
import Foundation
import UserNotifications

@MainActor
final class ArticleStore: ObservableObject {
    @Published private(set) var article: WikiArticle?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pushCountdownText: String?
    @Published private(set) var hasUnreadArticle = false {
        didSet {
            UserDefaults.standard.set(hasUnreadArticle, forKey: DefaultsKey.hasUnreadArticle)
            onUnreadStateChanged?(hasUnreadArticle)
        }
    }

    @Published var selectedInterval: PushInterval {
        didSet {
            UserDefaults.standard.set(selectedInterval.rawValue, forKey: DefaultsKey.selectedInterval)
            restartTimerIfReady()
        }
    }

    @Published var customMinutes: Double {
        didSet {
            UserDefaults.standard.set(customMinutes, forKey: DefaultsKey.customMinutes)
            restartTimerIfReady()
        }
    }

    var onUnreadStateChanged: ((Bool) -> Void)?
    var onOpenArticle: (() -> Void)?

    private let client = WikipediaClient()
    private var articleHistory = ArticleHistory()
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var nextPushDate: Date?
    private var hasBootstrapped = false
    private var pushPauseMode: PushPauseMode
    private var pushPauseUntil: Date?
    private var quietHoursOnly: Bool

    init() {
        let storedInterval = UserDefaults.standard.string(forKey: DefaultsKey.selectedInterval)
        selectedInterval = storedInterval.flatMap(PushInterval.init(rawValue:)) ?? .fiveMinutes

        let storedCustomMinutes = UserDefaults.standard.double(forKey: DefaultsKey.customMinutes)
        customMinutes = storedCustomMinutes > 0 ? storedCustomMinutes : 20

        let storedPauseMode = UserDefaults.standard.string(forKey: DefaultsKey.pushPauseMode)
        pushPauseMode = storedPauseMode.flatMap(PushPauseMode.init(rawValue:)) ?? .none
        pushPauseUntil = UserDefaults.standard.object(forKey: DefaultsKey.pushPauseUntil) as? Date
        quietHoursOnly = UserDefaults.standard.bool(forKey: DefaultsKey.quietHoursOnly)

        article = Self.loadStoredArticle()
        hasUnreadArticle = UserDefaults.standard.bool(forKey: DefaultsKey.hasUnreadArticle)
        normalizePushPauseState()
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        await requestNotificationAuthorization()
        onUnreadStateChanged?(hasUnreadArticle)
        await fetchNextArticle(shouldSendNotification: false, shouldMarkUnread: true)
    }

    func markOpened() {
        guard hasUnreadArticle else { return }
        hasUnreadArticle = false
        scheduleTimer()
    }

    func openCurrentArticle() {
        guard let url = article?.url else { return }
        NSWorkspace.shared.open(url)
        onOpenArticle?()
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    func refreshNow() async {
        await fetchNextArticle(shouldSendNotification: false, shouldMarkUnread: false, respectPushControls: false)
    }

    func refreshPushControlState() {
        normalizePushPauseState()
    }

    var pushToggleTitle: String {
        hasActivePushControl ? "開啟推送" : "暫停推送"
    }

    var isOneHourPauseChecked: Bool {
        pushPauseMode == .oneHour && pushPauseUntil.map { $0 > Date() } == true
    }

    var isTodayPauseChecked: Bool {
        pushPauseMode == .today && pushPauseUntil.map { $0 > Date() } == true
    }

    var isQuietHoursOnlyChecked: Bool {
        quietHoursOnly
    }

    func togglePushEnabled() {
        normalizePushPauseState()

        if hasActivePushControl {
            pushPauseMode = .none
            pushPauseUntil = nil
            quietHoursOnly = false
        } else {
            pushPauseMode = .manual
            pushPauseUntil = nil
        }

        persistPushControlState()
        scheduleTimer()
    }

    func toggleOneHourPause() {
        normalizePushPauseState()

        if isOneHourPauseChecked {
            pushPauseMode = .none
            pushPauseUntil = nil
        } else {
            pushPauseMode = .oneHour
            pushPauseUntil = Date().addingTimeInterval(60 * 60)
        }

        persistPushControlState()
        scheduleTimer()
    }

    func toggleTodayPause() {
        normalizePushPauseState()

        if isTodayPauseChecked {
            pushPauseMode = .none
            pushPauseUntil = nil
        } else {
            pushPauseMode = .today
            pushPauseUntil = Calendar.current.startOfDay(for: Date().addingTimeInterval(24 * 60 * 60))
        }

        persistPushControlState()
        scheduleTimer()
    }

    func toggleQuietHoursOnly() {
        quietHoursOnly.toggle()
        persistPushControlState()
        scheduleTimer()
    }

    var effectiveIntervalSeconds: TimeInterval {
        if selectedInterval == .custom {
            return max(customMinutes, 1) * 60
        }

        return selectedInterval.seconds
    }

    private func fetchNextArticle(
        shouldSendNotification: Bool,
        shouldMarkUnread: Bool,
        respectPushControls: Bool = false
    ) async {
        stopPushTimer()

        guard !respectPushControls || canPushNow else {
            scheduleTimer()
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetchedArticle = try await client.fetchRandomArticle(excluding: articleHistory.pageIDs)
            articleHistory.record(fetchedArticle.id)
            article = fetchedArticle
            storeArticle(fetchedArticle)
            hasUnreadArticle = shouldMarkUnread

            if shouldSendNotification {
                await sendNotification(for: fetchedArticle)
            }
        } catch {
            errorMessage = error.localizedDescription
            scheduleTimer()
        }

        isLoading = false
    }

    private func restartTimerIfReady() {
        guard hasBootstrapped, !hasUnreadArticle else { return }
        scheduleTimer()
    }

    private func scheduleTimer() {
        stopPushTimer()
        normalizePushPauseState()
        guard hasBootstrapped, !hasUnreadArticle else { return }
        guard pushPauseMode != .manual else { return }

        let delay = nextPushDelay()
        nextPushDate = Date().addingTimeInterval(delay)
        updatePushCountdownText()
        startCountdownTimer()

        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                await self.fetchNextArticle(
                    shouldSendNotification: true,
                    shouldMarkUnread: true,
                    respectPushControls: true
                )
            }
        }
    }

    private func stopPushTimer() {
        timer?.invalidate()
        countdownTimer?.invalidate()
        timer = nil
        countdownTimer = nil
        nextPushDate = nil
        pushCountdownText = nil
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePushCountdownText()
            }
        }
    }

    private func updatePushCountdownText() {
        guard let nextPushDate else {
            pushCountdownText = nil
            return
        }

        let remainingSeconds = max(Int(ceil(nextPushDate.timeIntervalSinceNow)), 0)
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        if hours > 0 {
            pushCountdownText = String(format: "剩 %02d:%02d:%02d", hours, minutes, seconds)
        } else {
            pushCountdownText = String(format: "剩 %02d:%02d", minutes, seconds)
        }
    }

    private func requestNotificationAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendNotification(for article: WikiArticle) async {
        let content = UNMutableNotificationContent()
        content.title = article.title
        content.body = article.summaryForNotification
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "wiki-time-\(article.id)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func loadStoredArticle() -> WikiArticle? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.lastArticle) else { return nil }
        return try? JSONDecoder().decode(WikiArticle.self, from: data)
    }

    private func storeArticle(_ article: WikiArticle) {
        guard let data = try? JSONEncoder().encode(article) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.lastArticle)
    }

    private var hasActivePushControl: Bool {
        pushPauseMode != .none || quietHoursOnly
    }

    private var canPushNow: Bool {
        normalizePushPauseState()

        if pushPauseMode != .none {
            return false
        }

        guard quietHoursOnly else { return true }
        let hour = Calendar.current.component(.hour, from: Date())
        return (9..<22).contains(hour)
    }

    private func nextPushDelay() -> TimeInterval {
        if let pauseUntil = pushPauseUntil, pauseUntil > Date() {
            return max(pauseUntil.timeIntervalSinceNow, 1)
        }

        guard quietHoursOnly else {
            return effectiveIntervalSeconds
        }

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)

        if (9..<22).contains(hour) {
            let nextInterval = now.addingTimeInterval(effectiveIntervalSeconds)
            let endOfWindow = calendar.date(
                bySettingHour: 22,
                minute: 0,
                second: 0,
                of: now
            ) ?? nextInterval

            return max(min(nextInterval, endOfWindow).timeIntervalSinceNow, 1)
        }

        let nextStart: Date
        if hour < 9 {
            nextStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        } else {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            nextStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }

        return max(nextStart.timeIntervalSinceNow, 1)
    }

    private func normalizePushPauseState() {
        guard let pushPauseUntil, pushPauseUntil <= Date() else { return }

        pushPauseMode = .none
        self.pushPauseUntil = nil
        persistPushControlState()
    }

    private func persistPushControlState() {
        UserDefaults.standard.set(pushPauseMode.rawValue, forKey: DefaultsKey.pushPauseMode)
        UserDefaults.standard.set(pushPauseUntil, forKey: DefaultsKey.pushPauseUntil)
        UserDefaults.standard.set(quietHoursOnly, forKey: DefaultsKey.quietHoursOnly)
    }
}

private enum DefaultsKey {
    static let selectedInterval = "selectedInterval"
    static let customMinutes = "customMinutes"
    static let recentArticleIDs = "recentArticleIDs"
    static let lastArticle = "lastArticle"
    static let hasUnreadArticle = "hasUnreadArticle"
    static let pushPauseMode = "pushPauseMode"
    static let pushPauseUntil = "pushPauseUntil"
    static let quietHoursOnly = "quietHoursOnly"
}

private enum PushPauseMode: String {
    case none
    case manual
    case oneHour
    case today
}

private struct ArticleHistory {
    private(set) var pageIDs: Set<Int>
    private var orderedPageIDs: [Int]
    private let limit = 500

    init() {
        orderedPageIDs = UserDefaults.standard.array(forKey: DefaultsKey.recentArticleIDs) as? [Int] ?? []
        orderedPageIDs = Array(orderedPageIDs.suffix(limit))
        pageIDs = Set(orderedPageIDs)
    }

    mutating func record(_ pageID: Int) {
        if pageIDs.contains(pageID) {
            orderedPageIDs.removeAll { $0 == pageID }
        }

        orderedPageIDs.append(pageID)
        orderedPageIDs = Array(orderedPageIDs.suffix(limit))
        pageIDs = Set(orderedPageIDs)

        UserDefaults.standard.set(orderedPageIDs, forKey: DefaultsKey.recentArticleIDs)
    }
}
