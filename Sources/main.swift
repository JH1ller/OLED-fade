import AppKit
import CoreGraphics

final class BlackWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // No screen capture, input capture, focus changes, or sleep assertions.
        contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    #if INTEGRATION_TEST
    private let defaults = UserDefaults(suiteName: "local.oledshade.integration-tests")!
    #else
    private let defaults = UserDefaults.standard
    #endif
    private let enabledKey = "automaticBlackoutEnabled"
    private let delayKey = "blackoutDelayMinutes"
    private var selectedDelay = BlackoutDelay.twoMinutes
    private let anyInput = CGEventType(rawValue: UInt32.max)!
    private var policy = IdlePolicy(now: ProcessInfo.processInfo.systemUptime)
    private var statusItem: NSStatusItem!
    private let toggleItem = NSMenuItem()
    private let delayMenu = NSMenu()
    private let blackNowItem = NSMenuItem()
    private var windows: [BlackWindow] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var suspensionReasons: Set<String> = []
    private var menuIsOpen = false

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !INTEGRATION_TEST
        // Launching twice should reveal the existing menu bar app, not create two overlays.
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if peers.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        #endif

        defaults.register(defaults: [enabledKey: true, delayKey: BlackoutDelay.twoMinutes.rawValue])
        selectedDelay = BlackoutDelay(savedMinutes: defaults.integer(forKey: delayKey))
        policy = IdlePolicy(timeout: selectedDelay.seconds, now: now)
        _ = policy.configure(enabled: defaults.bool(forKey: enabledKey), suspended: false, now: now)
        buildMenu()
        observeEnvironment()
        scheduleTimer()
        #if INTEGRATION_TEST
        DispatchQueue.main.async { self.runIntegrationChecks() }
        #endif
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "OLED Shade", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        toggleItem.action = #selector(toggleEnabled)
        toggleItem.target = self
        menu.addItem(toggleItem)
        let delayItem = NSMenuItem(title: "Blackout Delay", action: nil, keyEquivalent: "")
        delayMenu.autoenablesItems = false
        for delay in BlackoutDelay.allCases {
            let item = NSMenuItem(title: delay.title, action: #selector(selectDelay(_:)), keyEquivalent: "")
            item.tag = delay.rawValue
            item.target = self
            delayMenu.addItem(item)
        }
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)
        let hint = NSMenuItem(title: "Move the mouse or press a key to wake", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        blackNowItem.title = "Black Out Now"
        blackNowItem.action = #selector(blackOutNow)
        blackNowItem.target = self
        menu.addItem(blackNowItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit OLED Shade", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshMenu()
    }

    private func refreshMenu() {
        toggleItem.title = "Black out after \(selectedDelay.title)"
        toggleItem.state = policy.enabled ? .on : .off
        for item in delayMenu.items {
            item.state = item.tag == selectedDelay.rawValue ? .on : .off
        }
        blackNowItem.isEnabled = policy.enabled
        let symbol = policy.enabled ? "moon.fill" : "moon"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "OLED Shade")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = policy.enabled
            ? "OLED Shade — black out after \(selectedDelay.title)"
            : "OLED Shade — paused"
        statusItem.button?.setAccessibilityLabel("OLED Shade")
        statusItem.button?.setAccessibilityValue(policy.enabled ? "Enabled" : "Paused")
    }

    @objc private func toggleEnabled() {
        let enabled = !policy.enabled
        defaults.set(enabled, forKey: enabledKey)
        apply(policy.configure(enabled: enabled, suspended: isSuspended, now: now))
        scheduleTimer()
        refreshMenu()
    }

    @objc private func selectDelay(_ sender: NSMenuItem) {
        guard let delay = BlackoutDelay(rawValue: sender.tag) else { return }
        selectedDelay = delay
        defaults.set(delay.rawValue, forKey: delayKey)
        apply(policy.setTimeout(delay.seconds, now: now))
        scheduleTimer()
        refreshMenu()
    }

    @objc private func blackOutNow() {
        // Menu actions can arrive before or after menuDidClose. Defer independently of it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.menuIsOpen else { return }
            self.apply(self.policy.blackOut(now: self.now, idle: self.idleSeconds()))
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        rearm()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        rearm()
    }

    private var isSuspended: Bool { menuIsOpen || !suspensionReasons.isEmpty }

    private func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func tick() {
        let idle = idleSeconds()
        apply(policy.sample(now: now, idle: idle))
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard policy.enabled, !isSuspended else {
            timer = nil
            return
        }
        // One idle query per quarter-second while working; check for wake input 60 times a second when black.
        let interval = policy.isBlack ? 1.0 / 60.0 : 0.25
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = policy.isBlack ? 0.002 : 0.025
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func apply(_ change: IdlePolicy.Change) {
        switch change {
        case .none: return
        case .show:
            showOverlays()
        case .hide:
            hideOverlays()
        }
        scheduleTimer()
    }

    private func showOverlays() {
        hideOverlays()
        windows = NSScreen.screens.map { BlackWindow(screen: $0) }
        for window in windows { window.orderFrontRegardless() }
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private func hideOverlays() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    private func rearm() {
        apply(policy.configure(enabled: policy.enabled, suspended: isSuspended, now: now))
        scheduleTimer()
    }

    private func suspend(_ reason: String) {
        suspensionReasons.insert(reason)
        rearm()
    }

    private func resume(_ reason: String) {
        suspensionReasons.remove(reason)
        rearm()
    }

    private func observeEnvironment() {
        let center = NSWorkspace.shared.notificationCenter
        for (notification, reason, suspending) in [
            (NSWorkspace.willSleepNotification, "sleep", true),
            (NSWorkspace.didWakeNotification, "sleep", false),
            (NSWorkspace.screensDidSleepNotification, "displaySleep", true),
            (NSWorkspace.screensDidWakeNotification, "displaySleep", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session", false)
        ] {
            workspaceObservers.append(center.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                if suspending { self?.suspend(reason) } else { self?.resume(reason) }
            })
        }
        // These notifications make the overlay yield when macOS locks, including a manual lock.
        let distributed = DistributedNotificationCenter.default()
        for (name, suspending) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                if suspending { self?.suspend("lock") } else { self?.resume("lock") }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.policy.isBlack else { return }
            self.showOverlays()
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.policy.isBlack else { return }
            for window in self.windows { window.orderFrontRegardless() }
        })
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        hideOverlays()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    #if INTEGRATION_TEST
    private func runIntegrationChecks() {
        let previousApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let idle = idleSeconds()
        precondition(idle.isFinite && idle >= 0, "System idle counter must be readable without permission")
        precondition(!NSScreen.screens.isEmpty, "A display is required for this integration check")
        apply(policy.configure(enabled: true, suspended: false, now: now))
        refreshMenu()
        blackOutNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            self.timer?.invalidate()
            precondition(self.policy.isBlack, "Black Out Now must work after the menu closes")
            precondition(self.windows.count == NSScreen.screens.count, "Cover every display")
            for (window, screen) in zip(self.windows, NSScreen.screens) {
                precondition(window.isVisible, "Overlay is visible")
                precondition(window.frame == screen.frame, "Cover the entire display, including menu bar")
                precondition(window.backgroundColor == NSColor.black, "Use pure black")
                precondition(window.isOpaque && !window.hasShadow, "No translucent pixels or shadows")
                precondition(window.ignoresMouseEvents && !window.canBecomeKey, "Preserve input and focus")
                precondition(window.level.rawValue == Int(CGWindowLevelForKey(.screenSaverWindow)), "Cover ordinary app windows")
            }
            precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp,
                         "Showing an overlay must not steal focus")
            self.apply(self.policy.sample(now: self.now + 1, idle: 0))
            precondition(!self.policy.isBlack && self.windows.isEmpty, "Activity clears every overlay")

            self.toggleEnabled()
            precondition(!self.policy.enabled && self.toggleItem.state == .off, "Menu toggle pauses")
            precondition(!self.defaults.bool(forKey: self.enabledKey), "Persist the user's toggle")
            precondition(self.timer == nil, "Paused app has no idle polling timer")
            for item in self.delayMenu.items {
                self.selectDelay(item)
                let restoredDelay = BlackoutDelay(savedMinutes: self.defaults.integer(forKey: self.delayKey))
                let restoredPolicy = IdlePolicy(timeout: restoredDelay.seconds, now: self.now)
                precondition(restoredPolicy.timeout == TimeInterval(item.tag * 60), "Saved delay survives a new policy instance")
                precondition(self.policy.timeout == restoredPolicy.timeout, "Menu selection updates the live delay")
                precondition(!self.policy.enabled && self.timer == nil, "Changing delay preserves pause")
                precondition(item.state == .on && self.delayMenu.items.filter { $0.state == .on }.count == 1,
                             "Exactly one delay is selected")
            }
            self.toggleEnabled()
            precondition(self.policy.enabled && self.toggleItem.state == .on && self.timer != nil, "Menu toggle resumes")
            self.selectDelay(self.delayMenu.items[0])
            precondition(self.policy.timeout == 60 && self.policy.enabled && self.timer != nil,
                         "Changing delay while enabled keeps monitoring active")
            precondition(self.toggleItem.title == "Black out after 1 minute", "Show selected time in the toggle")
            self.apply(self.policy.blackOut(now: self.now, idle: self.idleSeconds()))
            self.suspend("testSleep")
            precondition(!self.policy.isBlack && self.windows.isEmpty && self.timer == nil, "Sleep clears overlays and stops polling")
            self.resume("testSleep")
            precondition(self.timer != nil && !self.policy.isBlack, "Wake restarts monitoring without a blackout")
            self.defaults.removePersistentDomain(forName: "local.oledshade.integration-tests")
            print("Passed native integration checks on \(NSScreen.screens.count) display(s): manual blackout, full coverage, focus, activity wake, toggle/delay persistence, all delay menu choices, pause, sleep, and resume.")
            NSApp.terminate(nil)
        }
    }
    #endif
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
