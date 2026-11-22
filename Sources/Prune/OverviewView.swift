import SwiftUI

struct OverviewView: View {
    @Environment(Store.self) private var store

    private var subtitle: String {
        if store.isScanning { return "Scanning your Mac…" }
        if let last = store.lastScan { return trf("Last scanned %@", Fmt.relative(last)) + " · " + trf("%@ found", plural(store.allItems.count, .item)) }
        return "Find gigabytes hiding in dependencies, build output and caches."
    }

    var body: some View {
        ZStack {
            if !store.isScanning && !store.hasScanned {
                ReadyView().transition(.opacity)
            } else if store.isScanning {
                FirstScanView().transition(.opacity)
            } else {
                dashboard.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: store.lastScan == nil)
        .animation(.easeInOut(duration: 0.5), value: store.isScanning)
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Overview", subtitle: subtitle) {
                    Button("Quick scan") { store.scan() }
                        .buttonStyle(.secondary)
                        .help("⌘R")
                        .disabled(store.isScanning)
                    Button("Full scan") { store.fullScan() }
                        .buttonStyle(.secondary)
                        .help("⇧⌘R")
                        .disabled(store.isScanning || store.isMappingDisk)
                    CleanButton(items: store.selectedItems)
                }
                .appear()

                HeroCard()
                    .appear(0.04)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                    ForEach(Array(store.junkCategories.enumerated()), id: \.element) { i, c in
                        CategoryCard(category: c).appear(0.1 + Double(i) * 0.045)
                    }
                }

                Group {
                if store.developerMode {
                    TopItemsCard(
                        title: "Stale projects",
                        subtitle: trf("No commits in %lld+ days. Their dependencies are safe to drop.", Prefs.staleDays),
                        items: Array(store.staleProjects.prefix(6)),
                        empty: store.isScanning ? "Looking through your projects…" : "Every project is active. Nice.",
                        route: .category(.nodeModules),
                        detail: { trf("last commit %@", Fmt.relative($0.lastActivity)) })
                } else {
                    TopItemsCard(
                        title: "Largest files",
                        subtitle: "The biggest single files in your home folder.",
                        items: Array(store.items(.largeFiles).prefix(6)),
                        empty: store.isMappingDisk ? tr("Mapping your disk…") : trf("No files over %lld MB.", Prefs.largeFileMB),
                        route: .category(.largeFiles),
                        detail: { trf("modified %@", Fmt.relative($0.lastActivity)) },
                        selectable: false)
                }
                }
                .appear(0.4)
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 40)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }
}

// MARK: Hero

struct HeroCard: View {
    @Environment(Store.self) private var store

    var body: some View {
        let parts = Fmt.parts(store.reclaimable)
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Reclaimable space")
                            .font(Theme.sans(13, .medium))
                            .foregroundStyle(Theme.muted)
                        if store.isScanning { Badge(text: "Scanning", color: Theme.blue) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(parts.value)
                            .font(.system(size: 64, weight: .semibold))
                            .monospacedDigit()
                            .tracking(-2.5)
                            .foregroundStyle(Theme.text)
                            .contentTransition(.numericText())
                        Text(parts.unit)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Theme.faint)
                    }
                    Text(plural(store.allItems.count, .item) + " · " + plural(store.staleProjects.count, .staleProject))
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.faint)
                        .contentTransition(.numericText())
                }
                Spacer()
                HStack(spacing: 0) {
                    Stat(label: "Selected", bytes: store.selectedSize, accent: true)
                    Hairline(vertical: true).frame(height: 56).padding(.horizontal, 24)
                    Stat(label: "Free on disk", bytes: store.disk.free)
                }
                .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 14) {
                SegmentBar(segments: store.junkCategories.map { ($0.color, Double(store.size($0))) }, height: 10)
                FlowLegend()
            }
        }
        .padding(28)
        .card()
        .borderBeam(store.isScanning)
        .animation(.snappy(duration: 0.5), value: store.reclaimable)
    }
}

private struct Stat: View {
    let label: String
    let bytes: Int64
    var accent = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(tr(label)).font(Theme.sans(12)).foregroundStyle(Theme.faint)
            SizeText(bytes: bytes, size: 22, weight: .semibold)
        }
    }
}

private struct FlowLegend: View {
    @Environment(Store.self) private var store
    var body: some View {
        FlowLayout(spacing: 18, lineSpacing: 8) {
            ForEach(store.junkCategories.filter { store.size($0) > 0 }) { c in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: 8, height: 8)
                    Text(tr(c.title)).font(Theme.sans(12)).foregroundStyle(Theme.muted)
                    Text(Fmt.bytes(store.size(c))).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
    }
}

// MARK: Category card

struct CategoryCard: View {
    @Environment(Store.self) private var store
    let category: CategoryID
    @State private var hovering = false

    var body: some View {
        let items = store.items(category)
        let selected = store.selected(in: category).count
        Button {
            store.route = .category(category)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    IconTile(symbol: category.tileSymbol, color: category.color, size: 34)
                    Spacer()
                    if store.pending.contains(category) {
                        Spinner(size: 11)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(hovering ? Theme.text : Theme.faint)
                    }
                }
                Spacer(minLength: 16)
                Text(tr(category.title))
                    .font(Theme.sans(14, .semibold))
                    .foregroundStyle(Theme.text)
                Text(tr(category.blurb))
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(3, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
                HStack(alignment: .firstTextBaseline) {
                    SizeText(bytes: store.size(category), size: 20, weight: .semibold)
                    Spacer()
                    if category == .docker && store.dockerStatus == .notRunning {
                        Text("not running").font(Theme.mono(11)).foregroundStyle(Theme.faint)
                    } else if category == .docker && store.dockerStatus == .notInstalled {
                        Text("not installed").font(Theme.mono(11)).foregroundStyle(Theme.faint)
                    } else if selected > 0 {
                        Badge(text: trf("%lld selected", selected), color: category.color)
                    } else {
                        Text(plural(items.count, .item)).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                    }
                }
                .frame(height: 24)
                .padding(.top, 12)
            }
            .padding(18)
            .frame(height: 212)
            .card(highlighted: hovering)
            .scaleEffect(hovering ? 1.015 : 1)
            .shadow(color: .black.opacity(hovering ? 0.28 : 0), radius: 18, y: 10)
            .borderBeam(store.pending.contains(category))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
    }
}

// MARK: Stale projects

struct TopItemsCard: View {
    @Environment(Store.self) private var store
    let title: String
    let subtitle: String
    let items: [CleanItem]
    let empty: String
    let route: Route
    let detail: (CleanItem) -> String
    /// Large files are cleaned from their own page, so their rows link there instead of toggling.
    var selectable = true

    var body: some View {
        let stale = items
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(title))
                        .font(Theme.sans(14, .semibold))
                        .foregroundStyle(Theme.text)
                    Text(tr(subtitle))
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("View all") { store.route = route }
                    .buttonStyle(.ghost)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Hairline()

            if stale.isEmpty {
                Text(tr(empty))
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
            } else {
                ForEach(Array(stale.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Hairline() }
                    HoverRow {
                        HStack(spacing: 12) {
                            if selectable {
                                CheckBox(state: store.selection.contains(item.id))
                            } else {
                                Image(systemName: NodeKind.forFile(item.url.pathExtension).symbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 15)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(item.name).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text)
                                    Text(item.kind).font(Theme.mono(11)).foregroundStyle(Theme.faint)
                                }
                                Text(item.location)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.faint)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(detail(item))
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.muted)
                            Text(Fmt.bytes(item.size))
                                .font(Theme.mono(13, .medium))
                                .foregroundStyle(Theme.text)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                    }
                    .onTapGesture { if selectable { store.toggle(item) } else { store.route = route } }
                }
            }
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: First scan

/// Shown while a scan runs: the logo at work, a live trail of what's being read, progress and a running total.
struct FirstScanView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let parts = Fmt.parts(store.reclaimable)
        let cats = store.junkCategories
        let done = cats.filter { !store.pending.contains($0) }.count
        let fraction = cats.isEmpty ? 0 : Double(done) / Double(cats.count)

        VStack(spacing: 0) {
            Spacer(minLength: 20)
            OrbView(size: 104, scanning: true)
                .padding(.top, 30)
                .padding(.bottom, 28)

            Text("Scanning your Mac")
                .font(Theme.sans(26, .semibold))
                .tracking(-0.6)
                .foregroundStyle(Theme.text)
                .appear(0.05)

            // Running total.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Found").font(Theme.sans(15)).foregroundStyle(Theme.muted)
                Text(parts.value)
                    .font(Theme.mono(15, .semibold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text(parts.unit).font(Theme.sans(15)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 8)
            .animation(.snappy, value: store.reclaimable)
            .appear(0.1)

            // Progress across categories + elapsed time.
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.text.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.blue, Theme.teal], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * max(fraction, 0.04)))
                            .animation(.spring(duration: 0.6), value: fraction)
                        // Shimmer on the bar so it never looks frozen.
                        ScanLine().clipShape(Capsule())
                    }
                }
                .frame(width: 380, height: 6)
                HStack {
                    Text(trf("%lld of %lld checked", done, cats.count))
                        .contentTransition(.numericText())
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(elapsed).monospacedDigit()
                    }
                }
                .font(Theme.sans(11.5))
                .foregroundStyle(Theme.faint)
                .frame(width: 380)
            }
            .padding(.top, 18)
            .appear(0.15)

            // Live trail: folders looked at and the one being read right now.
            VStack(spacing: 4) {
                Text(trf("%@ folders looked at", store.scanLive.files.formatted(.number.locale(Lang.locale))))
                    .font(Theme.sans(12, .medium))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
                Text(Fmt.tilde(store.scanLive.path))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 460)
                    .id(store.scanLive.path)
                    .transition(.opacity)
            }
            .animation(.easeOut(duration: 0.15), value: store.scanLive.path)
            .padding(.top, 14)
            .appear(0.2)

            VStack(spacing: 0) {
                ForEach(Array(cats.enumerated()), id: \.element) { i, c in
                    if i > 0 { Hairline() }
                    let pending = store.pending.contains(c)
                    HStack(spacing: 10) {
                        ZStack {
                            if pending {
                                Spinner(size: 11)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.green)
                                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                            }
                        }
                        .frame(width: 16)
                        Image(systemName: c.symbol).font(.system(size: 12)).foregroundStyle(Theme.faint).frame(width: 16)
                        Text(tr(c.title))
                            .font(Theme.sans(13))
                            .foregroundStyle(pending ? Theme.muted : Theme.text)
                        Spacer()
                        if !pending {
                            Text(Fmt.bytes(store.size(c)))
                                .font(Theme.mono(12))
                                .foregroundStyle(store.size(c) > 0 ? Theme.text : Theme.faint)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 31)
                    .background(pending ? Theme.text.opacity(0.02) : .clear)
                    .animation(.spring(duration: 0.45, bounce: 0.3), value: pending)
                }
            }
            .frame(width: 400)
            .card()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 18)
            .appear(0.3)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var elapsed: String {
        let s = Int(Date().timeIntervalSince(store.scanStarted ?? Date()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: Ready

/// Before the first scan: show what we already know (the disk) and let the user start.
struct ReadyView: View {
    @Environment(Store.self) private var store
    @State private var ringIn: CGFloat = 0

    var body: some View {
        let disk = store.disk
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .stroke(Theme.text.opacity(0.07), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: disk.usedFraction * ringIn)
                    .stroke(AngularGradient(colors: [Theme.blue.opacity(0.6), Theme.blue, Theme.teal],
                                            center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * disk.usedFraction)),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                OrbView(size: 118, intro: true)
            }
            .frame(width: 190, height: 190)
            .onAppear {
                withAnimation(.spring(duration: 1.6, bounce: 0.1).delay(0.6)) { ringIn = 1 }
            }

            HStack(spacing: 6) {
                Text(trf("%lld%% used", Int((disk.usedFraction * 100).rounded())))
                    .foregroundStyle(Theme.text)
                Text("·").foregroundStyle(Theme.faint)
                Text(trf("%@ free of %@", Fmt.bytes(disk.free), Fmt.bytes(disk.total)))
                    .foregroundStyle(Theme.muted)
            }
            .font(Theme.sans(12.5, .medium))
            .monospacedDigit()
            .padding(.top, 18)
            .appear(0.8)

            Text("Let's see what's taking space")
                .font(Theme.sans(30, .semibold))
                .tracking(-0.8)
                .foregroundStyle(Theme.text)
                .padding(.top, 26)
                .appear(0.9)
            Text("Prune reads file sizes only. Nothing is removed until you choose.")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
                .appear(1.0)

            HStack(spacing: 10) {
                Button("Quick scan") { store.scan() }
                    .buttonStyle(PruneButtonStyle(kind: .primary, height: 38))
                Button("Full scan") { store.fullScan() }
                    .buttonStyle(PruneButtonStyle(kind: .secondary, height: 38))
            }
            .padding(.top, 26)
            .appear(1.1)
            Text("Quick checks caches and junk in seconds. Full also maps the disk and finds large files.")
                .font(Theme.sans(11.5))
                .foregroundStyle(Theme.faint)
                .padding(.top, 12)
                .appear(1.15)


            Spacer(minLength: 24)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct Feature: View {
        let symbol: String
        let color: Color
        let title: String
        let text: String
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: symbol, color: color, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(title)).font(Theme.sans(13, .semibold)).foregroundStyle(Theme.text)
                    Text(tr(text)).font(Theme.sans(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()
        }
    }
}
