#if DEBUG
import SwiftUI
import WidgetKit

#Preview("Small · 1 AC", as: .systemSmall) {
    BreezePilotWidget()
} timeline: {
    ACWidgetEntry.sample(count: 1)
}

#Preview("Medium · 1 AC", as: .systemMedium) {
    BreezePilotWidget()
} timeline: {
    ACWidgetEntry.sample(count: 1)
}

#Preview("Medium · 2 ACs", as: .systemMedium) {
    BreezePilotWidget()
} timeline: {
    ACWidgetEntry.sample(count: 2)
}

#Preview("Large · 1 AC", as: .systemLarge) {
    BreezePilotWidget()
} timeline: {
    ACWidgetEntry.sample(count: 1)
}

#Preview("Large · 2 ACs", as: .systemLarge) {
    BreezePilotWidget()
} timeline: {
    ACWidgetEntry.sample(count: 2)
}

#Preview("Large · 3 ACs", as: .systemLarge) {
    BreezePilotWidget()
} timeline: {
    ACWidgetEntry.sample(count: 3)
}

#Preview("Large · 4 ACs", as: .systemLarge) {
    BreezePilotWidget()
} timeline: {
    ACWidgetEntry.sample(count: 4)
}

#Preview("Small · Off and unavailable", as: .systemSmall) {
    BreezePilotWidget()
} timeline: {
    ACWidgetEntry.sample(count: 1, isOn: false)
    ACWidgetEntry.sample(count: 1, isAvailable: false)
}

#Preview("Small · No AC selected", as: .systemSmall) {
    BreezePilotWidget()
} timeline: {
    ACWidgetEntry(date: .now, readings: [])
    ACWidgetEntry(date: .now, readings: [], hasSavedUnits: false)
}
#endif
