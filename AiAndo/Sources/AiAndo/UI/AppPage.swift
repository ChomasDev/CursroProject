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

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Cursor").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.muted)
                    HStack(spacing: 7) {
                        Circle().fill(installed ? AppPalette.purple : AppPalette.muted.opacity(0.5)).frame(width: 7, height: 7)
                        Text(installed ? "Ready to heckle" : "Not connected yet")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                Spacer(minLength: 0)
                Button { showingSettings = true } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("The brain").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.muted)
                        HStack(spacing: 6) {
                            Text(settings.provider == .cursor ? cursor.statusText : settings.configured ? settings.provider.name : "Bring your own API key")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(AppPalette.purple)
                    }
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 16) {
                Button { install() } label: {
                    HStack(spacing: 12) {
                        Text(installing ? "Installing…" : installed ? "Reinstall in Cursor" : "Install in Cursor")
                        if installing { ProgressView().controlSize(.small).tint(.white) }
                        else { Image(systemName: "arrow.down.to.line").fontWeight(.bold) }
                    }
                }
                .buttonStyle(RoastButtonStyle())
                .disabled(installing)
                Text(installed ? "Your next prompt is fair game." : "One click.\nZero chill.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
            }
            Text(notice ?? (settings.provider == .cursor ? "No API key needed. Roasts run on your Cursor account." : "No key needed for the preview. Your real key stays in macOS Keychain."))
                .font(.system(size: 12)).foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func install() {
        installing = true
        notice = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try CursorInstaller().install() }.value
                installed = CursorInstaller().isInstalled
                notice = "Installed in ~/Applications and connected to Cursor. Restart Cursor to load the hooks."
                installing = false
                if settings.provider == .cursor { try await cursor.connect() }
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
    @State private var connecting = false
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Model").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.muted)
                        Spacer()
                        Menu {
                            ForEach(provider.models, id: \.self) { suggestion in
                                Button(suggestion) { model = suggestion }
                            }
                        } label: {
                            Text("Suggestions").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.purple)
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                    TextField("Model ID", text: $model)
                        .textFieldStyle(.plain).font(.system(size: 20, weight: .semibold))
                        .accessibilityLabel("Model ID")
                    Text("Pick a suggestion or paste a model ID.")
                        .font(.system(size: 12)).foregroundStyle(AppPalette.muted)
                }
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
        .onAppear { loadKey() }
        .onChange(of: provider) {
            testTask?.cancel()
            testing = false
            model = AppSettings.shared.savedModel(for: provider)
            revealed = false
            notice = nil
            loadKey()
        }
        .onDisappear { testTask?.cancel(); apiKey = "" }
    }

    private var cursorAccount: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cursor account").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.muted)
            HStack(spacing: 12) {
                Circle().fill(cursor.state == .connected ? AppPalette.purple : AppPalette.muted.opacity(0.5)).frame(width: 8, height: 8)
                Text(cursor.statusText).font(.system(size: 17, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if cursor.state != .connected {
                    Button { connect() } label: {
                        HStack(spacing: 8) {
                            if connecting { ProgressView().controlSize(.small) }
                            Text("Connect Cursor")
                        }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(AppPalette.purple)
                    }
                    .buttonStyle(.plain).disabled(connecting)
                }
            }
            Text("No API key. Ai-Ando installs the Cursor CLI and uses your Cursor plan. You only approve once in the browser.")
                .font(.system(size: 12)).foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }

    private func connect() {
        connecting = true
        Task {
            try? await cursor.connect()
            connecting = false
        }
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
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .padding(.horizontal, 23).padding(.vertical, 16)
            .foregroundStyle(AppPalette.paper)
            .background(AppPalette.ink.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 14))
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
