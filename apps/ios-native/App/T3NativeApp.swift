import SwiftUI

@main struct T3NativeApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("theme") private var themeID = "t3-code"
    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .environment(\.t3Theme, T3Palette(id: themeID))
                .font(T3Font.body).foregroundStyle(T3Palette(id: themeID).text)
                .tint(T3Palette(id: themeID).accent)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
                .task { store.resume() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.resume() }
                    if phase == .background { store.disconnect() }
                }
        }
    }
}

enum AppSheet: String, Identifiable {
    case connections, settings, newThread
    var id: String { rawValue }
}

struct RootView: View {
    @Bindable var store: AppStore
    @Environment(\.t3Theme) private var theme
    @State private var sheet: AppSheet?
    @State private var path: [String] = []
    @State private var search = ""
    @State private var projectID = ""
    @State private var incomingLink = ""
    @State private var showSearch = false
    @State private var showSettled = false
    @State private var showSnoozed = false
    @State private var pageCount = 50
    @FocusState private var searchFocused: Bool

    private var searching: Bool { !search.isEmpty }
    var body: some View {
        NavigationStack(path: $path) {
            let index = ThreadIndex(threads: store.threads, projectID: projectID, search: search)
            let rows = index.matches
            let pinned = index.pinned, working = index.working, snoozed = index.snoozed, settled = index.settled
            List {
                if store.hosts.isEmpty && !store.isDemo {
                    ContentUnavailableView {
                        Text("Connect to T3 Code").font(T3Font.title)
                    } actions: {
                        Button("Add environment") { sheet = .connections }.buttonStyle(.glassProminent)
                    }.listRowSeparator(.hidden)
                } else if searching {
                    if rows.isEmpty { Text("No results").foregroundStyle(theme.muted).listRowSeparator(.hidden) }
                    threadRows(Array(rows.prefix(pageCount)))
                    if rows.count > pageCount { moreButton }
                } else {
                    if !pinned.isEmpty {
                        shelf("Pinned", count: pinned.count)
                        threadRows(pinned)
                    }
                    if rows.isEmpty && !store.connected && !store.isDemo {
                        ProgressView(store.phase).font(T3Font.subheadline).listRowSeparator(.hidden).listRowBackground(theme.canvas)
                    }
                    if !working.isEmpty {
                        shelf("Working", count: working.count)
                        threadRows(Array(working.prefix(pageCount)))
                        if working.count > pageCount { moreButton }
                    } else if pinned.isEmpty && store.connected {
                        Text("No working threads").font(T3Font.subheadline).foregroundStyle(theme.muted)
                            .padding(.vertical, 24).listRowSeparator(.hidden)
                    }
                    if !snoozed.isEmpty {
                        shelfToggle("Snoozed", count: snoozed.count, expanded: $showSnoozed)
                        if showSnoozed { threadRows(Array(snoozed.prefix(pageCount))) }
                    }
                    if !settled.isEmpty {
                        shelfToggle("Settled", count: settled.count, expanded: $showSettled)
                        if showSettled {
                            threadRows(Array(settled.prefix(pageCount)))
                            if settled.count > pageCount { moreButton }
                        }
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).background(theme.canvas)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { store.retry() }
            .navigationTitle("Threads").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Threads").font(T3Font.scaled(16, weight: .medium)) }
                ToolbarItem(placement: .topBarLeading) {
                    Button { sheet = .connections } label: { T3BrandTitle().foregroundStyle(theme.text).fixedSize() }
                        .buttonStyle(.plain).accessibilityLabel("Connections")
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .settings } label: { Image(systemName: "gearshape").foregroundStyle(theme.text) }
                        .accessibilityLabel("Appearance and text size")
                }
            }
            .toolbarBackground(theme.canvas, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationDestination(for: String.self) { id in ConversationScreen(store: store, threadID: id) }
        }
        .sheet(item: $sheet) { item in
            Group {
                switch item {
                case .connections: ConnectionsScreen(store: store, initialLink: incomingLink)
                case .settings: AppearanceScreen()
                case .newThread: NewThreadScreen(store: store) { id in path.append(id) }
                }
            }.environment(\.t3Theme, theme).font(T3Font.body)
        }
        .alert("T3 Code", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: store.activeHostID) { _, _ in path = [] }
        .onOpenURL { url in incomingLink = url.absoluteString; sheet = .connections }
    }
    private func threadRows(_ threads: [JSONValue]) -> some View {
        ForEach(threads, id: \.id) { thread in
            Button { path.append(thread.id) } label: {
                ThreadRow(thread: thread, project: store.shell.projects[thread["projectId"].string])
            }.buttonStyle(.plain)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .listRowInsets(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
                .listRowBackground(theme.canvas).listRowSeparatorTint(theme.border)
                .accessibilityIdentifier("thread-\(thread.id)")
        }
    }
    private func shelf(_ title: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Text(title).font(T3Font.caption)
            Rectangle().fill(theme.border).frame(height: 1)
            Text(count.formatted()).font(T3Font.caption).monospacedDigit()
        }.foregroundStyle(theme.muted).padding(.top, 16).padding(.bottom, 4)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(theme.canvas).listRowSeparator(.hidden)
    }
    private func shelfToggle(_ title: String, count: Int, expanded: Binding<Bool>) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack(spacing: 10) {
                Text("\(title) (\(count))").font(T3Font.caption)
                Rectangle().fill(theme.border).frame(height: 1)
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .medium))
            }.foregroundStyle(theme.muted).padding(.vertical, 16)
        }.buttonStyle(.plain).listRowSeparator(.hidden).listRowBackground(theme.canvas)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }
    private var moreButton: some View {
        Button("Show more") { pageCount += 50 }.font(T3Font.caption).listRowBackground(theme.canvas)
    }
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if showSearch {
                TextField("Search threads", text: $search).font(T3Font.body).focused($searchFocused)
                    .submitLabel(.search).padding(14).glassEffect(.regular, in: .capsule)
                    .accessibilityLabel("Search threads")
            }
            HStack(spacing: 12) {
                GlassEffectContainer(spacing: 0) {
                    HStack(spacing: 0) {
                        Button { showSearch.toggle(); searchFocused = showSearch; if !showSearch { search = "" } } label: {
                            Image(systemName: "magnifyingglass").frame(width: 48, height: 48)
                        }.accessibilityLabel("Search threads")
                        Menu {
                            Picker("Project", selection: $projectID) {
                                Text("All projects").tag("")
                                ForEach(store.projects, id: \.id) { Text($0["title"].string).tag($0.id) }
                            }
                        } label: { Image(systemName: projectID.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill").frame(width: 48, height: 48) }
                        .accessibilityLabel("Filter threads")
                    }.foregroundStyle(theme.text).glassEffect(.regular.interactive(), in: .capsule)
                }
                Spacer(minLength: 0)
                Button { sheet = .connections } label: {
                    HStack(spacing: 5) {
                        Circle().fill(store.connected ? .green : store.isDemo ? theme.muted : .orange).frame(width: 5, height: 5)
                        Text(store.isDemo ? "Preview" : store.connected ? (store.activeHost?.name ?? "Connected") : store.phase)
                            .font(T3Font.caption).lineLimit(1)
                    }.foregroundStyle(theme.muted)
                }.buttonStyle(.plain).accessibilityIdentifier("connection-status")
                    .accessibilityValue(store.connected ? "Connected" : store.phase)
                Spacer(minLength: 0)
                Button { sheet = .newThread } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 21)).frame(width: 54, height: 54)
                }.buttonStyle(.glass).buttonBorderShape(.circle).foregroundStyle(theme.text)
                    .accessibilityLabel("New conversation").disabled(!store.canOperate)
            }
        }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
        .background { theme.canvas.opacity(0.95).ignoresSafeArea(edges: .bottom) }
    }
}

struct ThreadRow: View {
    let thread: JSONValue
    let project: JSONValue?
    @Environment(\.t3Theme) private var theme
    private var status: (String, String, Color)? {
        if !thread["pendingRuntimeRequest"].isNull {
            return thread["pendingRuntimeRequest"]["kind"].string == "user_input" ? ("Input", "questionmark.bubble", .indigo) : ("Approval", "exclamationmark.shield", .orange)
        }
        switch thread["status"].string {
        case "running", "starting", "preparing", "queued": return ("Working", "circle.dashed", .cyan)
        case "waiting": return ("Working", "circle.dashed", .cyan)
        case "idle" where !thread["pendingBackgroundTasks"].array.isEmpty: return ("Waiting", "circle.dashed.inset.filled", theme.muted)
        case "completed" where !thread["latestRunCompletedAt"].string.isEmpty && thread["latestRunCompletedAt"].string > thread["lastVisitedAt"].string: return ("Done", "checkmark.circle", .green)
        case "failed": return thread["lastErrorClass"].string == "usage_limit" ? ("Limited", "exclamationmark.circle", .orange) : ("Failed", "exclamationmark.circle", .red)
        default: return nil
        }
    }
    private func compactTime(_ date: Date) -> String {
        let age = max(0, Int(Date.now.timeIntervalSince(date)))
        if age < 60 { return "now" }
        if age < 3600 { return "\(age / 60)m" }
        if age < 86400 { return "\(age / 3600)h" }
        if age < 604800 { return "\(age / 86400)d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(theme.muted)
                Text(project?["title"].string ?? "No project").font(T3Font.scaled(13, weight: .medium, relativeTo: .caption)).lineLimit(1).foregroundStyle(theme.muted)
                Spacer(minLength: 4)
                if !thread["pinnedAt"].isNull { Image(systemName: "pin").font(.system(size: 11)).foregroundStyle(theme.muted) }
                if let status {
                    Label(status.0, systemImage: status.1).font(T3Font.scaled(12, weight: .bold, relativeTo: .caption)).foregroundStyle(status.2)
                } else if let date = DateParser.parse(thread["updatedAt"].string) {
                    Text(compactTime(date)).font(T3Font.caption).foregroundStyle(theme.muted)
                        .accessibilityLabel(Text(date, style: .relative))
                }
            }
            Text(thread["title"].string).font(T3Font.scaled(16, weight: .medium)).foregroundStyle(theme.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if !thread["branch"].string.isEmpty {
                    Text(thread["branch"].string).font(.custom("Menlo-Regular", size: 11, relativeTo: .caption)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(thread["modelSelection"]["model"].string).font(T3Font.scaled(11, relativeTo: .caption)).lineLimit(1)
            }.foregroundStyle(theme.muted)
        }.accessibilityElement(children: .combine)
    }
}

@MainActor enum DateParser {
    private static let fractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let plain = ISO8601DateFormatter()
    static func parse(_ value: String) -> Date? { fractional.date(from: value) ?? plain.date(from: value) }
}
