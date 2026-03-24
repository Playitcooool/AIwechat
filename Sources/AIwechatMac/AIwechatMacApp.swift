import SwiftUI
import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    var statusViewModel: AssistantViewModel?
    private var appViewModel: AssistantViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsManager.shared.settings
        if settings.menuBarMode {
            setupMenuBarMode()
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        registerGlobalHotKey()
    }

    func setAppViewModel(_ vm: AssistantViewModel) {
        self.appViewModel = vm
    }

    private func setupMenuBarMode() {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "AI"
        item.button?.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: "AI 回复助手")

        let vm = AssistantViewModel()
        vm.refreshHistory()
        vm.startMonitoring()
        self.statusViewModel = vm

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: ContentView(viewModel: vm))

        item.button?.action = #selector(togglePopover)
        item.button?.target = self

        self.popover = popover
        self.statusItem = item
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    nonisolated private func registerGlobalHotKey() {
        var hotKeyRef: EventHotKeyRef?
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            if hotKeyID.id == 1 {
                NotificationCenter.default.post(name: .captureScreenShortcut, object: nil)
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4157), id: 1)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 9

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

extension Notification.Name {
    static let captureScreenShortcut = Notification.Name("captureScreenShortcut")
}

@main
struct AIwechatMacApp: App {
    @StateObject private var viewModel = AssistantViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("AIwechat") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 300, minHeight: 320)
                .onAppear {
                    viewModel.refreshHistory()
                    viewModel.startMonitoring()
                    NSApp.activate(ignoringOtherApps: true)
                    appDelegate.setAppViewModel(viewModel)
                }
                .onReceive(NotificationCenter.default.publisher(for: .captureScreenShortcut)) { _ in
                    let targetVM: AssistantViewModel
                    if SettingsManager.shared.settings.menuBarMode, let svm = appDelegate.statusViewModel {
                        targetVM = svm
                    } else {
                        targetVM = viewModel
                    }
                    targetVM.recognitionMode = .vision
                    targetVM.captureAndRecognize()
                }
        }
        .defaultSize(width: 320, height: 380)
        .windowResizability(.contentSize)
    }
}
