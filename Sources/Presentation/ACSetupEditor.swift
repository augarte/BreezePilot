import SwiftUI

struct ACSetupEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ACSetup
    @State private var activeID: UUID?
    @State private var showingPicker = false
    @State private var showingIcons = false
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
                VStack(alignment: .leading, spacing: BreezeMetrics.sectionSpacing) {
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
                    }
                }
                .breezePage()
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

    /// Keeps the name in step with the icon until the user writes their own.
    private func chooseIcon(_ icon: ACSetupIcon) {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == draft.icon.label { draft.name = icon.label }
        draft.icon = icon
        showingIcons = false
    }

    private var nameCard: some View {
        HStack(spacing: 12) {
            Button { showingIcons = true } label: {
                Image(systemName: draft.icon.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BreezePilotPalette.accent)
                    .frame(width: BreezeMetrics.cardAccessory, height: BreezeMetrics.cardAccessory)
                    .background(BreezePilotPalette.ice, in: RoundedRectangle(cornerRadius: BreezeMetrics.tileRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scene icon")
            .accessibilityValue(draft.icon.label)
            .popover(isPresented: $showingIcons) {
                ACSetupIconPicker(selection: Binding(get: { draft.icon }, set: chooseIcon))
                    .presentationCompactAdaptation(.popover)
            }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Air Conditioners").font(.title3.weight(.semibold))
                Spacer()
                Button("Add AC", systemImage: "plus") { showingPicker = true }
                    .font(.subheadline.weight(.semibold))
                    .disabled(availableUnits.isEmpty)
            }
            if !draft.targets.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: BreezeMetrics.controlSpacing)],
                          spacing: BreezeMetrics.controlSpacing) {
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
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(activeID == target.id ? BreezePilotPalette.ice : BreezePilotPalette.surface,
                                        in: RoundedRectangle(cornerRadius: BreezeMetrics.tileRadius))
                            .overlay {
                                if activeID == target.id {
                                    RoundedRectangle(cornerRadius: BreezeMetrics.tileRadius)
                                        .strokeBorder(BreezePilotPalette.accent, lineWidth: 1.5)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target state").font(.subheadline).foregroundStyle(.secondary)
                    Text(activeUnit?.name ?? target.unitName).font(.title3.weight(.semibold))
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if statuses[unit.id] == nil {
                    ProgressView("Checking AC options…").font(.footnote)
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

private struct ACSetupIconPicker: View {
    @Binding var selection: ACSetupIcon

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(ACSetupIcon.allCases) { icon in
                Button { selection = icon } label: {
                    VStack(spacing: 5) {
                        Image(systemName: icon.symbol).font(.title3).frame(height: 24)
                        Text(icon.label)
                            .font(.caption2.weight(.medium))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(selection == icon ? Color.white : BreezePilotPalette.accent)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(selection == icon ? BreezePilotPalette.accent : BreezePilotPalette.ice,
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon.label)
                .accessibilityAddTraits(selection == icon ? .isSelected : [])
            }
        }
        .padding(12)
        .frame(width: 340)
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
        VStack(spacing: BreezeMetrics.cardSpacing) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Power", systemImage: "power").font(.headline)
                HStack(spacing: BreezeMetrics.controlSpacing) {
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
        VStack(alignment: .leading, spacing: 12) {
            Label("Mode", systemImage: "air.conditioner.horizontal").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: BreezeMetrics.controlSpacing)],
                      spacing: BreezeMetrics.controlSpacing) {
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
                Text("Saved mode: \(mode.label)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .setupPanel()
    }

    private var temperatureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { temperatureTitle; Spacer(minLength: 8); temperatureChoices }
                VStack(alignment: .leading, spacing: 12) { temperatureTitle; temperatureChoices }
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
                Text("Saved target: \(ACStatus.degrees(temperature))°C").font(.footnote)
            } else {
                Text(canSetTemperature ? "Temperature will stay as it is." : "Set temperature is unavailable for this mode or AC.")
                    .font(.footnote)
            }
        }
        .padding(BreezeMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(BreezePilotPalette.temperatureGradient, in: RoundedRectangle(cornerRadius: BreezeMetrics.cardRadius))
    }

    private var temperatureTitle: some View {
        Label("Temperature", systemImage: "thermometer.medium").font(.headline)
    }

    private var temperatureChoices: some View {
        HStack(spacing: BreezeMetrics.controlSpacing) {
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
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? BreezePilotPalette.navy : .white)
                .background(.white.opacity(selected ? 1 : enabled ? 0.18 : 0.08),
                            in: RoundedRectangle(cornerRadius: BreezeMetrics.controlRadius))
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
            ACTemperatureStepIcon(symbol: direction < 0 ? "minus" : "plus", enabled: allowed)
        }
        .buttonStyle(.plain)
        .disabled(!allowed)
        .accessibilityLabel(direction < 0 ? "Lower scene temperature" : "Raise scene temperature")
    }

    private var fanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Fan speed", systemImage: "fan").font(.headline)
                Spacer()
                choice("Leave as is", selected: target.fan == nil) { target.fan = nil }
                    .fixedSize(horizontal: true, vertical: false)
            }
            if !fans.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: BreezeMetrics.controlSpacing)],
                          spacing: BreezeMetrics.controlSpacing) {
                    ForEach(fans, id: \.self) { speed in
                        choice(speed.label, selected: target.fan == speed) { target.fan = speed }
                            .accessibilityLabel("Scene fan speed \(speed.label)")
                    }
                }
            }
            if let fan = target.fan, !fans.contains(fan) {
                Text("Saved fan speed: \(fan.label)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .setupPanel()
    }

    private func choice(_ title: String, selected: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .modifier(ACOptionAppearance(selected: selected, available: enabled))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    func setupPanel() -> some View { breezeCard() }
}
