import SwiftUI

struct ContentView: View {
    @EnvironmentObject var configManager: ConfigManager

    var body: some View {
        TabView {
            NavigationStack {
                TargetListView()
            }
            .tabItem { Label("目标", systemImage: "paperplane.fill") }

            NavigationStack {
                RuleListView()
            }
            .tabItem { Label("规则", systemImage: "list.bullet.indent") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ConfigManager())
}
