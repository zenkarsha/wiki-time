import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private enum StatusIconMetrics {
        static let itemWidth: CGFloat = 18
        static let symbolSize: CGFloat = 22
        static let symbolX: CGFloat = -2
        static let symbolY: CGFloat = 0
        static let badgeSize: CGFloat = 7
        static let badgeX: CGFloat = 15
        static let badgeY: CGFloat = 13
    }

    private let articleStore = ArticleStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: StatusIconMetrics.itemWidth)
    private let popover = NSPopover()
    private let statusIconView = NSImageView()
    private let unreadBadgeView = NSView()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        configureStatusItem()
        configurePopover()

        Task {
            await articleStore.bootstrap()
        }
    }

    private func configureStatusItem() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.imagePosition = .imageOnly
        configureStatusIcon()
        renderStatusIcon(hasUnreadArticle: false)

        articleStore.onUnreadStateChanged = { [weak self] hasUnreadArticle in
            self?.renderStatusIcon(hasUnreadArticle: hasUnreadArticle)
        }

        articleStore.onOpenArticle = { [weak self] in
            self?.popover.performClose(nil)
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self

        let hostingController = NSHostingController(rootView: ContentView(store: articleStore))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        articleStore.markOpened()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }

        popover.performClose(nil)
        articleStore.refreshPushControlState()

        let menu = NSMenu()
        menu.addItem(makeMenuItem(
            title: articleStore.pushToggleTitle,
            action: #selector(togglePushEnabled)
        ))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "暫停推送 1 小時",
            action: #selector(toggleOneHourPause),
            isChecked: articleStore.isOneHourPauseChecked
        ))
        menu.addItem(makeMenuItem(
            title: "今天不再推送",
            action: #selector(toggleTodayPause),
            isChecked: articleStore.isTodayPauseChecked
        ))
        menu.addItem(makeMenuItem(
            title: "只在 09:00–22:00 推送",
            action: #selector(toggleQuietHoursOnly),
            isChecked: articleStore.isQuietHoursOnlyChecked
        ))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "關閉 Wiki Time",
            action: #selector(quitApp)
        ))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        isChecked: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isChecked ? .on : .off
        return item
    }

    @objc private func togglePushEnabled() {
        articleStore.togglePushEnabled()
    }

    @objc private func toggleOneHourPause() {
        articleStore.toggleOneHourPause()
    }

    @objc private func toggleTodayPause() {
        articleStore.toggleTodayPause()
    }

    @objc private func toggleQuietHoursOnly() {
        articleStore.toggleQuietHoursOnly()
    }

    @objc private func quitApp() {
        articleStore.quitApp()
    }

    private func renderStatusIcon(hasUnreadArticle: Bool) {
        statusIconView.frame = CGRect(
            x: StatusIconMetrics.symbolX,
            y: StatusIconMetrics.symbolY,
            width: StatusIconMetrics.symbolSize,
            height: StatusIconMetrics.symbolSize
        )

        unreadBadgeView.isHidden = !hasUnreadArticle
        unreadBadgeView.frame = CGRect(
            x: StatusIconMetrics.badgeX,
            y: StatusIconMetrics.badgeY,
            width: StatusIconMetrics.badgeSize,
            height: StatusIconMetrics.badgeSize
        )
    }

    private func makeStatusIconImage() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: StatusIconMetrics.symbolSize,
            weight: .regular
        )
        let image = NSImage(
            systemSymbolName: "w.square.fill",
            accessibilityDescription: "Wiki Time"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func configureStatusIcon() {
        guard let button = statusItem.button else { return }

        button.wantsLayer = true
        button.layer?.masksToBounds = false

        statusIconView.image = makeStatusIconImage()
        statusIconView.contentTintColor = .labelColor
        statusIconView.imageScaling = .scaleProportionallyUpOrDown
        statusIconView.frame = CGRect(
            x: StatusIconMetrics.symbolX,
            y: StatusIconMetrics.symbolY,
            width: StatusIconMetrics.symbolSize,
            height: StatusIconMetrics.symbolSize
        )
        button.addSubview(statusIconView)

        unreadBadgeView.wantsLayer = true
        unreadBadgeView.layer?.backgroundColor = NSColor.systemRed.cgColor
        unreadBadgeView.layer?.cornerRadius = StatusIconMetrics.badgeSize / 2
        unreadBadgeView.isHidden = true
        button.addSubview(unreadBadgeView, positioned: .above, relativeTo: statusIconView)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
