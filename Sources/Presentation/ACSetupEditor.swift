import SwiftUI

struct ACSetupEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ACSetup
    @State private var activeID: UUID?
    @State private var showingPicker = false
    @State private var confirmingDeletion = false
    @State private var statuses: [UUID: ACStatus] = [:]
    @State private var failedReads: Set<UUID> = []
    let library: ACLibrary
    let devices: ACDevices

    init(setup: ACSetup, library: ACLibrary, devices: ACDevices) {
        _draft = State(initialValue: setup)
        _activeID = State(initialValue: setup.targets.first?.id)
        self.library = library
        self.devices = devices
    }

    private var existing: Bool { library.setups.contains { $0.id == draft.id } }
    private var availableUnits: [SavedAC] { library.units.filter { unit in !draft.targets.contains { $0.id == unit.id } } }
    private var activeUnit: SavedAC? { library.units.first { $0.id == activeID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    nameCard
                    unitPicker
                    if let target = draft.targets.first(where: { $0.id == activeID }) {
                        stateEditor(for: target)
                    } else {
                        Text(library.units.isEmpty ? "Add an AC in Control before creating a scene."
                             : "Add an air conditioner to choose its target state.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .setupPanel()
                    }
                    if existing {
                        Button("Delete Scene", role: .destructive) { confirmingDeletion = true }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 6)
                    }
                }
                .frame(maxWidth: 520)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .background(BreezePilotPalette.canvas)
            .navigationTitle(existing ? "Edit Scene" : "New Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if library.saveSetup(draft) { dismiss() } }
                        .disabled(!draft.canSave)
                }
            }
            .sheet(isPresented: $showingPicker) {
                NavigationStack {
                    List(availableUnits) { unit in
                        Button {
                            draft.targets.append(ACSetupTarget(id: unit.id, unitName: unit.name))
                            activeID = unit.id
                            showingPicker = false
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(unit.name).foregroundStyle(.primary)
                                if let room = library.rooms.first(where: { $0.id == unit.roomID }), room.name != unit.name {
                                    Text(room.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .navigationTitle("Choose an AC")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingPicker = false } }
                    }
                }
            }
            .confirmationDialog("Delete this scene?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("Delete Scene", role: .destructive) {
                    library.removeSetup(draft.id)
                    ACSetupStore.removeResult(for: draft.id)
                    dismiss()
                }
            }
            .task(id: activeUnit) {
                guard let unit = activeUnit, let address = LocalAddress(unit.address) else { return }
                let status = try? await devices.make(unit, address).readStatus()
                guard !Task.isCancelled else { return }
                if let status {
                    statuses[unit.id] = status
                    failedReads.remove(unit.id)
                } else {
                    failedReads.insert(unit.id)
                }
            }
        }
    }

    private var nameCard: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(ACSetupIcon.allCases) { icon in
                    Button(icon.label, systemImage: icon.symbol) { draft.icon = icon }
                }
            } label: {
                Image(systemName: draft.icon.symbol)
                    .font(.title3)
                    .foregroundStyle(BreezePilotPalette.accent)
                    .frame(width: 44, height: 44)
                    .background(BreezePilotPalette.ice, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Scene icon")
            VStack(alignment: .leading, spacing: 3) {
                Text("Scene name").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Sleep", text: $draft.name)
                    .font(.headline)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel("Scene name")
            }
        }
        .setupPanel()
    }

    private var unitPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Air Conditioners").font(.headline)
                Spacer()
                Button("Add AC", systemImage: "plus") { showingPicker = true }
                    .font(.subheadline.weight(.semibold))
                    .disabled(availableUnits.isEmpty)
            }
            if !draft.targets.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 7)], spacing: 7) {
                    ForEach(draft.targets) { target in
                        let unit = library.units.first { $0.id == target.id }
                        Button { activeID = target.id } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(unit?.name ?? target.unitName).font(.subheadline.weight(.semibold))
                                Text(unit == nil ? "AC removed" : target.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                            .padding(.horizontal, 8)
                            .background(activeID == target.id ? BreezePilotPalette.ice : BreezePilotPalette.surface,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                if activeID == target.id {
                                    RoundedRectangle(cornerRadius: 12).strokeBorder(BreezePilotPalette.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(activeID == target.id ? .isSelected : [])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stateEditor(for target: ACSetupTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target state").font(.caption).foregroundStyle(.secondary)
                    Text(activeUnit?.name ?? target.unitName).font(.headline)
                }
                Spacer()
                Button("Remove AC from scene", systemImage: "trash", role: .destructive) {
                    draft.targets.removeAll { $0.id == target.id }
                    activeID = draft.targets.last?.id
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
            }
            if let unit = activeUnit {
                ACSetupTargetEditor(target: binding(for: target), unit: unit, status: statuses[unit.id])
                if failedReads.contains(unit.id) {
                    Text("Couldn’t read this AC. Available choices may be limited until it reconnects.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if statuses[unit.id] == nil {
                    ProgressView("Checking AC options…").font(.caption)
                }
            } else {
                Text("This AC was removed. Remove it from the scene or add another AC.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .setupPanel()
            }
        }
    }

    private func binding(for target: ACSetupTarget) -> Binding<ACSetupTarget> {
        Binding {
            draft.targets.first { $0.id == target.id } ?? target
        } set: { updated in
            if let index = draft.targets.firstIndex(where: { $0.id == target.id }) {
                draft.targets[index] = updated
            }
        }
    }
}

private struct ACSetupTargetEditor: View {
    @Binding var target: ACSetupTarget
    let unit: SavedAC
    let status: ACStatus?

    private var powerWritable: Bool { status?.powerWritable ?? unit.xiaomi?.power.writable ?? true }

    private var modes: [ClimateMode] {
        if let profile = unit.xiaomi {
            return profile.mode?.writable == true ? ClimateMode.allCases.filter { profile.modes[$0] != nil } : []
        }
        return status?.availableModes ?? []
    }

    private var targetModes: Set<ClimateMode> { status?.targetModes ?? (unit.xiaomi == nil ? [.cool] : [.cool, .heat]) }
    private var limits: ClosedRange<Int>? {
        if let profile = unit.xiaomi {
            return profile.setpoint?.property.writable == true ? profile.setpoint?.limits : nil
        }
        return status?.limits
    }
    private var step: Int { max(1, status?.targetStep ?? unit.xiaomi?.setpoint?.step ?? 1) }
    private var canSetTemperature: Bool { limits != nil && (target.mode.map(targetModes.contains) ?? true) }

    private var fans: [FanSpeed] {
        if let profile = unit.xiaomi {
            return profile.fan?.writable == true ? FanSpeed.allCases.filter { profile.speeds[$0] != nil } : []
        }
        if let status, let mode = target.mode, mode != status.mode {
            return status.fanOptionsByMode[mode] ?? []
        }
        return status?.fan?.available ?? []
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Power", systemImage: "power").font(.subheadline.weight(.semibold))
                HStack(spacing: 5) {
                    choice("On", selected: target.power == true, enabled: powerWritable) { target.power = true }
                    choice("Off", selected: target.power == false, enabled: powerWritable) { target.power = false }
                    choice("Leave as is", selected: target.power == nil) { target.power = nil }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Desired power")
            }
            .setupPanel()

            if target.power == false {
                Label("This AC will turn off when you run the scene.", systemImage: "power")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .setupPanel()
            } else {
                modeCard
                temperatureCard
                fanCard
            }
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Mode", systemImage: "snowflake").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 65), spacing: 5)], spacing: 5) {
                ForEach(modes, id: \.self) { mode in
                    choice(mode.label, selected: target.mode == mode) {
                        target.mode = mode
                        if !targetModes.contains(mode) { target.temperature = nil }
                        if let speed = target.fan, !fans.contains(speed) { target.fan = nil }
                    }
                    .accessibilityLabel("Scene mode \(mode.label)")
                }
                choice("Leave as is", selected: target.mode == nil) { target.mode = nil }
            }
            if let mode = target.mode, !modes.contains(mode) {
                Text("Saved mode: \(mode.label)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .setupPanel()
    }

    private var temperatureCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack { temperatureTitle; Spacer(minLength: 6); temperatureChoices }
                VStack(alignment: .leading, spacing: 6) { temperatureTitle; temperatureChoices }
            }
            if let temperature = target.temperature, canSetTemperature, let limits {
                HStack {
                    temperatureStep(-1, current: temperature, limits: limits)
                    Text(ACStatus.degrees(temperature) + "°C")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("setupTemperature")
                    temperatureStep(1, current: temperature, limits: limits)
                }
            } else if let temperature = target.temperature {
                Text("Saved target: \(ACStatus.degrees(temperature))°C").font(.caption)
            } else {
                Text(canSetTemperature ? "Temperature will stay as it is." : "Set temperature is unavailable for this mode or AC.")
                    .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(BreezePilotPalette.temperatureGradient, in: RoundedRectangle(cornerRadius: 16))
    }

    private var temperatureTitle: some View {
        Label("Temperature", systemImage: "thermometer.medium").font(.subheadline.weight(.semibold))
    }

    private var temperatureChoices: some View {
        HStack(spacing: 5) {
            temperatureChoice("Set", selected: target.temperature != nil, enabled: canSetTemperature) {
                if target.temperature == nil, let limits {
                    let preferred = min(max(status?.target ?? 52, limits.lowerBound), limits.upperBound)
                    target.temperature = limits.lowerBound + (preferred - limits.lowerBound) / step * step
                }
            }
            temperatureChoice("Leave as is", selected: target.temperature == nil, enabled: true) {
                target.temperature = nil
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func temperatureChoice(_ title: String, selected: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? BreezePilotPalette.navy : .white)
                .background(.white.opacity(selected ? 1 : enabled ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func temperatureStep(_ direction: Int, current: Int, limits: ClosedRange<Int>) -> some View {
        let next = current + direction * step
        let allowed = limits.contains(next)
        return Button {
            target.temperature = next
        } label: {
            ACTemperatureStepIcon(symbol: direction < 0 ? "minus" : "plus", enabled: allowed, size: 44)
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .accessibilityLabel(direction < 0 ? "Lower scene temperature" : "Raise scene temperature")
    }

    private var fanCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Fan speed", systemImage: "fan").font(.subheadline.weight(.semibold))
                Spacer()
                choice("Leave as is", selected: target.fan == nil) { target.fan = nil }
                    .fixedSize(horizontal: true, vertical: false)
            }
            if !fans.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 5)], spacing: 5) {
                    ForEach(fans, id: \.self) { speed in
                        choice(speed.label, selected: target.fan == speed) { target.fan = speed }
                            .accessibilityLabel("Scene fan speed \(speed.label)")
                    }
                }
            }
            if let fan = target.fan, !fans.contains(fan) {
                Text("Saved fan speed: \(fan.label)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .setupPanel()
    }

    private func choice(_ title: String, selected: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, minHeight: 44)
                .modifier(ACOptionAppearance(selected: selected, available: enabled, cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    func setupPanel() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BreezePilotPalette.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
