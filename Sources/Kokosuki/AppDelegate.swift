import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    let core = PetCore()
    let brain = Brain()
    private(set) var engine: PetEngine!

    private var petPanel: PetPanel!
    private var containerView: PetContainerView!
    private var bubbleController: BubbleWindowController!
    private var chatController: ChatWindowController!
    private var settingsController: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if DebugLog.enabled {
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown]) { ev in
                DebugLog.write("local monitor: type=\(ev.type.rawValue) win=\(ev.window.map { String(describing: type(of: $0)) } ?? "nil") loc=\(ev.locationInWindow)")
                return ev
            }
        }

        if var saved = Persistence.loadStats() {
            Persistence.applyOfflineDecay(&saved)
            core.stats = saved
        }

        engine = PetEngine(core: core, brain: brain)
        bubbleController = BubbleWindowController()
        engine.bubble = bubbleController

        // pet window
        let side = PetLayout.windowSize(scale: AppSettings.shared.petScale)
        petPanel = PetPanel(size: side)
        containerView = PetContainerView(core: core, petScale: AppSettings.shared.petScale)
        containerView.engine = engine
        containerView.menuProvider = { [weak self] in self?.buildMenu() ?? NSMenu() }
        containerView.openChat = { [weak self] in self?.toggleChat() }
        petPanel.contentView = containerView

        engine.moveWindow = { [weak self] center in
            guard let self else { return }
            let s = PetLayout.windowSize(scale: AppSettings.shared.petScale)
            self.petPanel.setFrameOrigin(NSPoint(x: center.x - s / 2, y: center.y - s / 2))
        }

        // chat + settings
        settingsController = SettingsWindowController(onResetStats: { [weak self] in
            guard let self else { return }
            self.core.stats = PetStats()
            Persistence.saveStats(self.core.stats)
        })
        chatController = ChatWindowController(
            core: core, engine: engine, brain: brain,
            openSettings: { [weak self] in self?.settingsController.show() })
        chatController.onVisibilityChange = { [weak self] visible in
            visible == true ? self?.engine.chatOpened() : self?.engine.chatClosed()
        }
        engine.chatMirror = { [weak self] text, done in
            self?.chatController.model.updateStream(text, done: done)
        }

        // status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusIcon.make()
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // brain
        brain.onStateChange = { [weak self] state in
            self?.core.brainState = state
        }
        core.brainState = .loading
        brain.load()

        // start behavior
        let savedX = UserDefaults.standard.object(forKey: "petX") as? Double
        let start: CGPoint? = savedX.map { CGPoint(x: $0, y: 0) }
        petPanel.orderFrontRegardless()
        engine.start(at: start.map { p in
            let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            let x = min(max(p.x, f.minX + 60), f.maxX - 60)
            return CGPoint(x: x, y: f.minY + PetLayout.feetDrop(scale: AppSettings.shared.petScale))
        })

        // settings reactions. @Published emits on willSet — the stored property still
        // holds the OLD value at that instant — so hop the runloop before applying.
        AppSettings.shared.$petScale
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applyScale() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: .kokosukiLangChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.languageChanged() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(engine.petCenter.x, forKey: "petX")
        engine.shutdown()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu: menu)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu: menu)
        return menu
    }

    private func populate(menu: NSMenu) {
        func item(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.target = self
            return it
        }

        menu.addItem(item(L10n.t("menu.chat"), #selector(menuChat)))
        menu.addItem(.separator())
        menu.addItem(item(L10n.t("menu.feedFish"), #selector(menuFeedFish)))
        menu.addItem(item(L10n.t("menu.feedCookie"), #selector(menuFeedCookie)))
        menu.addItem(item(L10n.t("menu.play"), #selector(menuPlay)))
        menu.addItem(item(
            core.isSleeping ? L10n.t("menu.wake") : L10n.t("menu.sleep"),
            #selector(menuSleep)))
        menu.addItem(item(L10n.t("menu.callOver"), #selector(menuCallOver)))
        menu.addItem(.separator())

        let stats = NSMenuItem(
            title: "🐟 \(Int(core.stats.fullness))   ⚡️ \(Int(core.stats.energy))   💗 \(Int(core.stats.happiness))",
            action: nil, keyEquivalent: "")
        stats.isEnabled = false
        menu.addItem(stats)

        let brainTitle: String
        switch core.brainState {
        case .loading: brainTitle = L10n.t("menu.brainLoading")
        case .ready, .generating: brainTitle = L10n.t("menu.brainReady")
        case .failed: brainTitle = L10n.t("menu.brainFailed")
        }
        let brainItem = NSMenuItem(title: brainTitle, action: nil, keyEquivalent: "")
        brainItem.isEnabled = false
        menu.addItem(brainItem)
        menu.addItem(.separator())

        menu.addItem(item(L10n.t("menu.settings"), #selector(menuSettings)))
        menu.addItem(item(L10n.t("menu.quit"), #selector(menuQuit), key: "q"))
    }

    @objc private func menuChat() { toggleChat() }
    @objc private func menuFeedFish() { engine.feed(fish: true) }
    @objc private func menuFeedCookie() { engine.feed(fish: false) }
    @objc private func menuPlay() { engine.play() }
    @objc private func menuSleep() {
        core.isSleeping ? engine.wake(grumpy: false) : engine.fallAsleep(commanded: true)
    }
    @objc private func menuCallOver() { engine.callOver() }
    @objc private func menuSettings() { settingsController.show() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func toggleChat() {
        chatController.refreshView(
            core: core, engine: engine, brain: brain,
            openSettings: { [weak self] in self?.settingsController.show() })
        chatController.toggle(near: engine.petCenter, history: brain.history)
    }

    // MARK: - Settings reactions

    private func applyScale() {
        let scale = AppSettings.shared.petScale
        let s = PetLayout.windowSize(scale: scale)
        petPanel.setContentSize(NSSize(width: s, height: s))
        containerView.updateScale(core: core, petScale: scale)
        engine.rescaled()
    }

    private func languageChanged() {
        chatController.refreshView(
            core: core, engine: engine, brain: brain,
            openSettings: { [weak self] in self?.settingsController.show() })
        settingsController.rebuild()
    }
}
