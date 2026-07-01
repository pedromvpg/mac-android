import SwiftUI

@main
struct MacAndroidApp: App {
    @StateObject private var adb = AdbService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(adb)
                .onAppear { adb.startPolling() }
                .onDisappear { adb.stopPolling() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 640)
    }
}
