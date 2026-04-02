import SwiftUI
import AppKit

/// Main window with sidebar navigation — inspired by SuperWhisper
struct MainWindowView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            ZStack {
                VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()

                switch appState.selectedTab {
                case .summary:
                    SummaryView()
                case .configuration:
                    ConfigurationView()
                case .history:
                    HistoryView()
                }
            }
        }
    }
}

/// Sidebar navigation
struct SidebarView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            List(SidebarTab.allCases, selection: $appState.selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.vertical, 4)
                    .tag(tab)
            }
            .listStyle(.sidebar)

            Spacer()

            // App branding at bottom
            VStack(spacing: 16) {
                Button(action: { appState.triggerSync() }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(appState.isSyncing ? "Syncing..." : "Sync Now")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [.cyan.opacity(0.8), .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(appState.isSyncing)
                .padding(.horizontal, 16)

                VStack(spacing: 2) {
                    Text("JumpSync")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("v1.0")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 16)
        }
        .frame(minWidth: 180)
    }
}

// MARK: - NSVisualEffectView wrapper for full-window vibrancy

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    MainWindowView()
        .environment(AppState())
        .frame(width: 800, height: 560)
}
