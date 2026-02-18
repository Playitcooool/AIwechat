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
                .frame(minWidth: 320, minHeight: 360)
                .onAppear {
                    viewModel.startMonitoring()
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 340, height: 400)
        .windowResizability(.contentSize)
    }
}
