import SwiftUI

@main
struct ControlLabApp: App {
    @StateObject private var model = BridgeViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1336, height: 950)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
