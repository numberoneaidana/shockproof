import SwiftUI
import Foundation

@main
struct ShockProofApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).tint(Theme.ink)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("seenGuide") private var seenGuide = false
    var body: some View {
        if m.connected {
            TabView {
                FoundationView().tabItem { Label("Foundation", systemImage: "square.stack.3d.up") }
                FuturesView().tabItem { Label("Futures", systemImage: "chart.line.uptrend.xyaxis") }
                StressView().tabItem { Label("Stress", systemImage: "bolt") }
                RisksView().tabItem { Label("Risks", systemImage: "list.bullet.rectangle") }
                StatementsView().tabItem { Label("Accounts", systemImage: "tray.and.arrow.up") }
            }
            .sheet(isPresented: Binding(get: { !seenGuide }, set: { if !$0 { seenGuide = true } })) { GuideView() }
        } else {
            WelcomeView()
        }
    }
}
