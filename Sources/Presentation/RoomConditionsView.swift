import SwiftUI

struct RoomConditionsView: View {
    let conditions: RoomConditions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { readings }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 5) { readings }
        }
    }

    @ViewBuilder
    private var readings: some View {
        if let temperature = conditions.temperature {
            Label("\(temperature) °C", systemImage: "thermometer.medium")
                .accessibilityLabel("Room temperature, \(temperature) degrees Celsius")
        }
        if let humidity = conditions.humidity {
            Label("\(humidity)%", systemImage: "drop")
                .accessibilityLabel("Humidity, \(humidity) percent")
        }
    }
}
