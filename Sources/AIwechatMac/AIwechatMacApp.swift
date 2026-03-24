import SwiftUI
import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        registerGlobalHotKey()
    }

    private func registerGlobalHotKey() {
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
                    viewModel.startMonitoring()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .captureScreenShortcut)) { _ in
                    viewModel.recognitionMode = .vision
                    viewModel.captureAndRecognize()
                }
        }
        .defaultSize(width: 320, height: 380)
        .windowResizability(.contentSize)
    }
}
