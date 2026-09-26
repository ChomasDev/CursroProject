import AppKit
import SwiftUI

@MainActor
struct AppPage: View {
    let preview: () -> Void
    @State private var showingSettings = false
    @State private var installed = CursorInstaller().isInstalled
    @State private var installing = false
    @State private var notice: String?
    private var settings: AppSettings { .shared }
    private var cursor: CursorConnection { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text("Ai-Ando").font(.system(size: 23, weight: .heavy, design: .rounded)).tracking(-0.7)
                    }
                    Spacer()
                    Button {
                        showingSettings.toggle()
                    } label: {
                        Label(showingSettings ? "Back to app" : "Settings", systemImage: showingSettings ? "arrow.left" : "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 17).padding(.vertical, 11)
                            .background(AppPalette.paper.opacity(0.7), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if showingSettings { AISettingsPage() }
                else { home }
            }
            .padding(32)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppPalette.background)
        .foregroundStyle(AppPalette.ink)
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: .openAISettings)) { _ in showingSettings = true }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Vibe coding.\nWith heckling.")
                        .font(.system(size: 62, weight: .heavy, design: .rounded))
                        .tracking(-2.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Cursor does the work.\nWe heckle from the sidelines.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppPalette.muted)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RoastMascot().frame(width: 160, height: 190).rotationEffect(.degrees(8))
                    .accessibilityHidden(true)
            }
            Button(action: preview) {
                HStack(alignment: .center, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sample roast").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.muted)
                        Text("“Fix the bug.” Cool.\nWhich bug, detective?")
                            .font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.6)
                            .multilineTextAlignment(.leading)
                        Text("Preview the roast").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.purple)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .frame(width: 48, height: 48)
                        .background(AppPalette.background, in: Circle())
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.paper, in: RoundedRectangle(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview the roast using sample text")

            VStack(alignment: .leading, spacing: 12) {
                Text(allReady ? "All set. Your next prompt is fair game." : "Three steps to get roasted")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.muted)
                VStack(spacing: 0) {
                    SetupStep(number: 1, title: "Hooks in Cursor",
                              detail: installed ? "Installed. Restart Cursor if it was already open." : "Lets Ai-Ando see your prompts.",
                              done: installed, busy: installing) {
                        if installed {
                            Button("Reinstall") { install() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.muted)
                                .disabled(installing)
                        } else {
                            Button { install() } label: {
                                Text(installing ? "Installing…" : "Install in Cursor")
                            }
                            .buttonStyle(RoastButtonStyle(compact: true)).disabled(installing)
                        }
                    }
                    StepDivider()
                    SetupStep(number: 2, title: "The brain",
                              detail: brainDetail, done: brainReady, busy: cursor.isBusy, enabled: installed) {
                        if !brainReady {
                            Button {
                                if settings.provider == .cursor { Task { try? await cursor.connect() } }
                                else { showingSettings = true }
                            } label: {
                                Text(cursor.isBusy ? "Working…" : settings.provider == .cursor ? "Connect Cursor" : "Add API key")
                            }
                            .buttonStyle(RoastButtonStyle(compact: true))
                            .disabled(!installed || cursor.isBusy)
                        }
                    }
                    if cursor.isBusy && settings.provider == .cursor { CursorProgress(state: cursor.state).padding(.horizontal, 20).padding(.bottom, 16) }
                    StepDivider()
                    SetupStep(number: 3, title: "Pick a model",
                              detail: brainReady ? "\(settings.provider.name) · \(settings.model)" : "Choose who roasts you.",
                              done: brainReady, enabled: brainReady) {
                        Button { showingSettings = true } label: {
                            HStack(spacing: 6) {
                                Text(brainReady ? "Change model" : "Choose model")
                                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                            }
                        }
                        .buttonStyle(RoastButtonStyle(compact: true, tint: brainReady ? AppPalette.purple : AppPalette.ink))
                        .disabled(!brainReady)
                    }
                }
                .background(AppPalette.paper, in: RoundedRectangle(cornerRadius: 22))
            }
            Text(notice ?? (settings.provider == .cursor ? "No API key needed. Roasts run on your Cursor account." : "No key needed for the preview. Your real key stays in macOS Keychain."))
                .font(.system(size: 12)).foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var brainReady: Bool {
        settings.provider == .cursor ? cursor.state == .connected : settings.configured
    }
    private var allReady: Bool { installed && brainReady }
    private var brainDetail: String {
        guard settings.provider == .cursor else {
            return settings.configured ? "\(settings.provider.name) API key saved." : "Add your \(settings.provider.name) API key."
        }
        if case .failed(let message) = cursor.state { return message }
        return cursor.state == .connected ? "Connected to your Cursor account." : cursor.isBusy ? cursor.statusText : "Uses your Cursor plan. No API key."
    }

    private func install() {
        installing = true
        notice = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try CursorInstaller().install() }.value
                installed = CursorInstaller().isInstalled
                notice = "Hooks installed. Restart Cursor to load them."
                installing = false
                if settings.provider == .cursor && cursor.state != .connected { try await cursor.connect() }
            } catch { notice = error.localizedDescription }
            installing = false
        }
    }
}

@MainActor
private struct AISettingsPage: View {
    @State private var provider = AppSettings.shared.provider
    @State private var model = AppSettings.shared.model
    @State private var apiKey = ""
    @State private var revealed = false
    @State private var notice: String?
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @State private var keyLoaded = false
    private var cursor: CursorConnection { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose your\nprofessional hater.")
                        .font(.system(size: 43, weight: .heavy, design: .rounded)).tracking(-1.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Same questionable prompts. Your choice of brain.")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(AppPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RoastMascot(caption: "BYO brain").frame(width: 114, height: 140).rotationEffect(.degrees(-7))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Provider").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.muted)
                HStack(spacing: 10) {
                    ForEach(AIProvider.allCases) { choice in
                        Button { provider = choice } label: {
                            VStack(spacing: 9) {
                                Text(providerLetter(choice))
                                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                                Text(choice.name).font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(provider == choice ? AppPalette.paper : AppPalette.ink)
                            .background(provider == choice ? AppPalette.purple : AppPalette.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.name)
                        .accessibilityAddTraits(provider == choice ? [.isSelected] : [])
                    }
                }
            }
            VStack(spacing: 0) {
                ModelPicker(model: $model, options: modelOptions,
                            loading: provider == .cursor && cursor.models.isEmpty && cursor.state == .connected)
                    .padding(18)
                Rectangle().fill(AppPalette.background).frame(height: 2).padding(.horizontal, 22)
                if provider == .cursor { cursorAccount } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("API key").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.muted)
                        Spacer()
                        Label("Keychain protected", systemImage: "lock.fill")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(AppPalette.muted)
                    }
                    HStack(spacing: 12) {
                        Group {
                            if revealed { TextField("Paste your key. We can keep a secret.", text: $apiKey) }
                            else { SecureField("Paste your key. We can keep a secret.", text: $apiKey) }
                        }
                        .textFieldStyle(.plain).font(.system(size: 17, weight: .medium))
                        .accessibilityLabel("API key")
                        Button { revealed.toggle() } label: {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                                .foregroundStyle(AppPalette.muted).frame(width: 30, height: 28)
                        }
                        .buttonStyle(.plain).accessibilityLabel(revealed ? "Hide API key" : "Show API key")
                    }
                    Text("Sent only to your selected provider. Never saved in a plain-text file.")
                        .font(.system(size: 12)).foregroundStyle(AppPalette.muted)
                }
                .padding(18)
                }
            }
            .background(AppPalette.paper, in: RoundedRectangle(cornerRadius: 22))
            HStack(spacing: 20) {
                Button("Save settings") { save() }
                    .buttonStyle(RoastButtonStyle())
                    .disabled(testing || !keyLoaded)
                Button { test() } label: {
                    HStack(spacing: 8) {
                        if testing { ProgressView().controlSize(.small) }
                        else { Image(systemName: "bolt.horizontal.fill") }
                        Text(testing ? "Checking the brain…" : "Test connection")
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(testing || !keyLoaded || (provider.needsKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(notice ?? "Connection tests send a tiny request and may incur a small provider charge.")
                .font(.system(size: 12)).foregroundStyle(AppPalette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            loadKey()
            if provider == .cursor { Task { await cursor.loadModels() } }
        }
        .onChange(of: provider) {
            testTask?.cancel()
            testing = false
            model = AppSettings.shared.savedModel(for: provider)
            if provider == .cursor { Task { await cursor.loadModels() } }
            revealed = false
            notice = nil
            loadKey()
        }
        .onDisappear { testTask?.cancel(); apiKey = "" }
    }

    private var modelOptions: [CursorModel] {
        if provider == .cursor, !cursor.models.isEmpty { return cursor.models }
        return provider.models.map { CursorModel(id: $0, name: $0) }
    }

    private var cursorAccount: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cursor account").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.muted)
            HStack(spacing: 12) {
                Circle().fill(cursor.state == .connected ? AppPalette.purple : AppPalette.muted.opacity(0.5)).frame(width: 8, height: 8)
                Text(cursor.statusText).font(.system(size: 17, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if cursor.state != .connected && !cursor.isBusy {
                    Button("Connect Cursor") { connect() }
                        .buttonStyle(RoastButtonStyle(compact: true, tint: AppPalette.purple))
                }
            }
            if cursor.isBusy { CursorProgress(state: cursor.state) }
            Text("No API key. Ai-Ando installs the Cursor CLI and uses your Cursor plan. You only approve once in the browser.")
                .font(.system(size: 12)).foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }

    private func connect() {
        Task { try? await cursor.connect() }
    }

    private func providerLetter(_ provider: AIProvider) -> String {
        switch provider {
        case .cursor: return "C"
        case .anthropic: return "A"
        case .openai: return "O"
        case .google: return "G"
        case .openrouter: return "↗"
        }
    }

    private func loadKey() {
        guard provider.needsKey else { apiKey = ""; keyLoaded = true; return }
        do { apiKey = try APIKeyStore.read(provider); keyLoaded = true }
        catch { apiKey = ""; keyLoaded = false; notice = error.localizedDescription }
    }
    private func save() {
        do {
            try AppSettings.shared.save(provider: provider, model: model, key: apiKey)
            notice = !provider.needsKey ? "Settings saved. Roasts now run on your Cursor account."
                : apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "API key removed. Add a key to enable roasts." : "Settings saved. Your next roast will use this model."
        } catch { notice = error.localizedDescription }
    }
    private func test() {
        testing = true
        notice = nil
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = provider
        testTask = Task {
            do {
                var configuration = AIConfiguration(provider: provider.rawValue, model: model, apiKey: apiKey)
                if !provider.needsKey { configuration.agentPath = try await cursor.connect().path }
                try await AIWorker.test(configuration)
                guard !Task.isCancelled else { return }
                notice = "Connected. Save settings to use this model."
            } catch {
                guard !Task.isCancelled else { return }
                notice = error.localizedDescription
            }
            testing = false
        }
    }
}

/// Current model plus a searchable list of what the provider offers. Any ID can still be typed.
private struct ModelPicker: View {
    @Binding var model: String
    let options: [CursorModel]
    let loading: Bool
    @State private var query = ""

    private var matches: [CursorModel] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return options }
        return options.filter { $0.id.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.muted)
                Spacer()
                if loading {
                    HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Loading your models…") }
                        .font(.system(size: 11.5)).foregroundStyle(AppPalette.muted)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppPalette.muted)
                TextField("Search \(options.count) models, or paste an ID", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                    .accessibilityLabel("Search models")
                    .onSubmit {
                        let typed = query.trimmingCharacters(in: .whitespaces)
                        if let first = matches.first { model = first.id } else if !typed.isEmpty { model = typed }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AppPalette.muted) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(AppPalette.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(matches, id: \.id) { option in
                        Button { model = option.id } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.name).font(.system(size: 14, weight: .semibold))
                                    if option.name != option.id {
                                        Text(option.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(AppPalette.muted)
                                    }
                                }
                                Spacer()
                                if option.id == model {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppPalette.purple)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(option.id == model ? AppPalette.purple.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option.id == model ? [.isSelected] : [])
                    }
                    let typed = query.trimmingCharacters(in: .whitespaces)
                    if !typed.isEmpty && !matches.contains(where: { $0.id == typed }) {
                        Button { model = typed } label: {
                            Label("Use “\(typed)” as model ID", systemImage: "plus.circle")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.purple)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: min(260, CGFloat(max(matches.count, 1)) * 48 + 8))
            Text("Selected: \(model.isEmpty ? "none" : model)")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(AppPalette.muted)
        }
    }
}

extension Notification.Name {
    static let openAISettings = Notification.Name("AiAndo.openSettings")
}

private enum AppPalette {
    static let background = Color(red: 0.91, green: 0.88, blue: 0.98)
    static let paper = Color(red: 0.995, green: 0.99, blue: 1.0)
    static let ink = Color(red: 0.12, green: 0.09, blue: 0.18)
    static let muted = Color(red: 0.40, green: 0.36, blue: 0.49)
    static let purple = Color(red: 0.40, green: 0.25, blue: 0.80)
    static let peach = Color(red: 1.0, green: 0.70, blue: 0.61)
}

private struct RoastButtonStyle: ButtonStyle {
    var compact = false
    var tint = AppPalette.ink
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: .bold))
            .padding(.horizontal, compact ? 16 : 23).padding(.vertical, compact ? 10 : 16)
            .foregroundStyle(AppPalette.paper)
            .background(tint.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.25), in: RoundedRectangle(cornerRadius: compact ? 11 : 14))
    }
}

/// One row of the home checklist: number (or check), title, status line, and its action.
private struct SetupStep<Action: View>: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    var busy = false
    var enabled = true
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? AppPalette.purple : AppPalette.background)
                if busy { ProgressView().controlSize(.small) }
                else if done { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(AppPalette.paper) }
                else { Text("\(number)").font(.system(size: 14, weight: .heavy, design: .rounded)) }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(AppPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action()
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
    }
}

private struct StepDivider: View {
    var body: some View { Rectangle().fill(AppPalette.background).frame(height: 2).padding(.horizontal, 20) }
}

/// Real progress for the Cursor CLI setup: which stage is running, a moving bar, and elapsed time.
private struct CursorProgress: View {
    let state: CursorConnection.State
    @State private var started = Date()

    private var stages: [(CursorConnection.State, String)] {
        [(.checking, "Check account"), (.installing, "Install Cursor CLI"), (.signingIn, "Approve in browser")]
    }
    private var current: Int { stages.firstIndex { $0.0 == state } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    HStack(spacing: 5) {
                        Image(systemName: index < current ? "checkmark.circle.fill" : index == current ? "circle.dotted" : "circle")
                            .symbolEffect(.pulse, isActive: index == current)
                        Text(stage.1)
                    }
                    .font(.system(size: 12, weight: index == current ? .bold : .medium))
                    .foregroundStyle(index <= current ? AppPalette.purple : AppPalette.muted.opacity(0.6))
                    if index < stages.count - 1 {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(AppPalette.muted.opacity(0.5))
                    }
                }
            }
            ProgressView().progressViewStyle(.linear).tint(AppPalette.purple)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(hint + " · \(Int(context.date.timeIntervalSince(started)))s")
                    .font(.system(size: 11.5)).foregroundStyle(AppPalette.muted)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(AppPalette.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: state) { started = Date() }
    }

    private var hint: String {
        switch state {
        case .installing: return "Downloading from cursor.com, usually under a minute"
        case .signingIn: return "Click Continue on the Cursor page that just opened"
        default: return "Talking to Cursor"
        }
    }
}

/// A bored little skull: all vector shapes, no image assets or downloads.
private struct RoastMascot: View {
    var caption = "zero chill"
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 180
            ZStack {
                SkullShape().fill(AppPalette.paper)
                SkullShape().stroke(AppPalette.ink, lineWidth: 3)
                HStack(spacing: 25) {
                    boredEye(rotation: -7)
                    boredEye(rotation: 7)
                }
                .offset(y: -7)
                RoundedRectangle(cornerRadius: 3).fill(AppPalette.ink)
                    .frame(width: 13, height: 10).rotationEffect(.degrees(45)).offset(y: 23)
                HStack(spacing: 12) {
                    ForEach(0..<3) { _ in
                        Capsule().fill(AppPalette.ink).frame(width: 3, height: 21)
                    }
                }
                .offset(y: 56)
                Text(caption)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(AppPalette.peach, in: Capsule())
                    .overlay(Capsule().stroke(AppPalette.ink, lineWidth: 2))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 8, y: 87)
            }
            .frame(width: 180, height: 190)
            .scaleEffect(scale, anchor: .topLeading)
        }
    }

    private func boredEye(rotation: Double) -> some View {
        ZStack(alignment: .top) {
            Ellipse().fill(AppPalette.ink).frame(width: 35, height: 30)
            Rectangle().fill(AppPalette.paper).frame(width: 39, height: 10).offset(y: -1)
            Capsule().fill(AppPalette.ink).frame(width: 37, height: 3).offset(y: 9)
        }
        .rotationEffect(.degrees(rotation))
    }
}

private struct SkullShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 49, y: 150))
        path.addLine(to: CGPoint(x: 49, y: 133))
        path.addCurve(to: CGPoint(x: 18, y: 80), control1: CGPoint(x: 23, y: 129), control2: CGPoint(x: 18, y: 110))
        path.addCurve(to: CGPoint(x: 90, y: 19), control1: CGPoint(x: 18, y: 40), control2: CGPoint(x: 42, y: 19))
        path.addCurve(to: CGPoint(x: 162, y: 80), control1: CGPoint(x: 138, y: 19), control2: CGPoint(x: 162, y: 40))
        path.addCurve(to: CGPoint(x: 131, y: 133), control1: CGPoint(x: 162, y: 110), control2: CGPoint(x: 157, y: 129))
        path.addLine(to: CGPoint(x: 131, y: 150))
        path.addQuadCurve(to: CGPoint(x: 113, y: 169), control: CGPoint(x: 131, y: 169))
        path.addLine(to: CGPoint(x: 67, y: 169))
        path.addQuadCurve(to: CGPoint(x: 49, y: 150), control: CGPoint(x: 49, y: 169))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 180, y: rect.height / 190))
    }
}
