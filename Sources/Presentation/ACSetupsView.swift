import SwiftUI

struct ACSetupsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: SetupSheet?
    @State private var runningID: UUID?
    @State private var results: [UUID: ACSetupRunResult] = [:]
    @State private var runError: String?
    @Binding var requestedSetupID: UUID?
    let library: ACLibrary
    let devices: ACDevices

    private enum SetupSheet: Identifiable {
        case editor(ACSetup)
        case result(ACSetupRunResult)

        var id: UUID {
            switch self {
            case let .editor(setup): setup.id
            case let .result(result): result.id
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.setups.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(library.setups) { setup in
                                setupCard(setup)
                            }
                        }
                        .frame(maxWidth: 520)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BreezePilotPalette.canvas)
            .navigationTitle("Scenes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Scene", systemImage: "plus") { sheet = .editor(ACSetup()) }
                        .labelStyle(.iconOnly)
                        .disabled(library.units.isEmpty || runningID != nil)
                }
            }
            .sheet(item: $sheet) { item in
                switch item {
                case let .editor(setup):
                    ACSetupEditor(setup: setup, library: library, devices: devices)
                case let .result(result):
                    resultSheet(result)
                }
            }
            .alert("Couldn’t run scene", isPresented: Binding(
                get: { runError != nil },
                set: { if !$0 { runError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(runError ?? "")
            }
            .onChange(of: requestedSetupID, initial: true) { _, id in
                guard let id else { return }
                requestedSetupID = nil
                guard let setup = library.setups.first(where: { $0.id == id }) else { return }
                if let result = ACSetupStore.lastResult(for: setup) ?? latestResult(for: setup) {
                    sheet = .result(result)
                } else {
                    sheet = .editor(setup)
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    for setup in library.setups {
                        if let result = ACSetupStore.lastResult(for: setup) { results[setup.id] = result }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(BreezePilotPalette.accent)
            Text("No scenes yet").font(.title3.weight(.semibold))
            Text(library.units.isEmpty ? "Add an AC in Air Conditioners to get started."
                 : "Save settings for multiple ACs and apply them with one tap.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !library.units.isEmpty {
                Button("New Scene", systemImage: "plus") { sheet = .editor(ACSetup()) }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 3)
            }
        }
        .padding(20)
    }

    private func setupCard(_ setup: ACSetup) -> some View {
        let names = Dictionary(library.units.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let summary = setup.summary(names: names)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Button { sheet = .editor(setup) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: setup.icon.symbol)
                            .font(.headline)
                            .foregroundStyle(BreezePilotPalette.accent)
                            .frame(width: 40, height: 40)
                            .background(BreezePilotPalette.ice, in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(setup.name).font(.headline).foregroundStyle(.primary)
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(setup.name)")
                .accessibilityHint(summary)
                .disabled(runningID != nil)

                if let result = latestResult(for: setup) {
                    Button {
                        sheet = .result(result)
                    } label: {
                        Label(result.summary, systemImage: result.allApplied ? "checkmark.circle" : "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(result.allApplied ? Color.secondary : .orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(runningID != nil)
                    .accessibilityLabel("Last result for \(setup.name): \(result.summary)")
                }
            }

            Button {
                run(setup)
            } label: {
                Group {
                    if runningID == setup.id {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(width: 68, height: 46)
                .foregroundStyle(.white)
                .background(BreezePilotPalette.action, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(runningID != nil)
            .opacity(runningID == nil || runningID == setup.id ? 1 : 0.45)
            .accessibilityLabel(runningID == setup.id ? "Running \(setup.name)" : "Run \(setup.name)")
        }
        .padding(12)
        .background(BreezePilotPalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func latestResult(for setup: ACSetup) -> ACSetupRunResult? {
        guard let result = results[setup.id], result.revision == setup.revision else { return nil }
        return result
    }

    private func resultSheet(_ result: ACSetupRunResult) -> some View {
        let setup = library.setups.first { $0.id == result.setupID && $0.revision == result.revision }
        return NavigationStack {
            List {
                Section {
                    Label(result.summary, systemImage: result.allApplied ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.headline)
                        .accessibilityIdentifier("setupRunSummary")
                    ForEach(result.units) { unit in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(library.units.first { $0.id == unit.id }?.name ?? unit.name)
                                .font(.subheadline.weight(.semibold))
                            if !unit.confirmed.isEmpty {
                                Text(unit.confirmed.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let message = unit.message {
                                Text(message).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Last run")
                }
                if let setup, result.units.contains(where: \.canRetry) {
                    Button("Retry Failed ACs", systemImage: "arrow.clockwise") { run(setup, retrying: result) }
                        .disabled(runningID != nil)
                    if runningID == result.setupID { ProgressView("Retrying…") }
                }
                if let runError {
                    Section { Text(runError).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(setup?.name ?? "Scene Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { sheet = nil; runError = nil }.disabled(runningID != nil)
                }
            }
        }
        .interactiveDismissDisabled(runningID != nil)
    }

    private func run(_ setup: ACSetup, retrying previous: ACSetupRunResult? = nil) {
        guard runningID == nil else { return }
        runningID = setup.id
        runError = nil
        Task {
            defer { runningID = nil }
            do {
                let result = try await RunACSetup(makeDevice: devices.make)(setup, units: library.units, retrying: previous)
                results[setup.id] = result
                sheet = .result(result)
            } catch {
                runError = error.localizedDescription
            }
        }
    }
}
