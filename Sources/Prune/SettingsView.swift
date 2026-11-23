import SwiftUI
import ServiceManagement

struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case general = "General", scanning = "Scanning", permissions = "Permissions", about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .scanning: "magnifyingglass"
            case .permissions: "lock.shield"
            case .about: "info.circle"
            }
        }
    }

    @State private var page: Page = .general
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Color.clear.frame(height: 44) // traffic lights
                Text("Settings")
                    .font(Theme.sans(12, .medium))
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                ForEach(Page.allCases) { p in
                    SidebarRow(symbol: p.symbol, title: p.rawValue, trailing: nil, loading: false,
                               selected: page == p, ns: ns) { page = p }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(width: 200)
            .frame(maxHeight: .infinity)
            .background(VisualEffect().ignoresSafeArea())

            Rectangle().fill(Theme.text.opacity(0.08)).frame(width: 1).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(tr(page.rawValue))
                        .font(Theme.sans(22, .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.text)
                    switch page {
                    case .general: GeneralSettings()
                    case .scanning: ScanningSettings()
                    case .permissions: PermissionSettings()
                    case .about: AboutSettings()
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.top, 44)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
                .id(page)
                .transition(.opacity)
            }
            .scrollIndicators(.never)
            .background(Theme.bg)
        }
        .animation(.easeOut(duration: 0.15), value: page)
        .ignoresSafeArea()
        .frame(width: 820, height: 600)
    }
}
