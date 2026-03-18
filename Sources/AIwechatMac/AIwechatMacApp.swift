import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
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
        }
        .defaultSize(width: 320, height: 380)
        .windowResizability(.contentSize)
    }
}
