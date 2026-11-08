# BreezePilot

BreezePilot is a SwiftUI iPhone app for the Daikin FTKM-YV2S and compatible Xiaomi / Mijia air conditioners. It controls saved units directly over home Wi-Fi. After installation and setup, you can use it with the Mac switched off.

## Screens

- **Air Conditioners** groups saved units by room and shows live mode, target, fan speed, room temperature, and humidity when reported. Use **Add AC** to choose a brand and save a compatible unit. Each card opens that AC’s controls.
- **Control** puts the power icon beside refresh and shows the unit’s modes, fan speeds, and available room readings. Daikin extras include **Boost**, **Econo**, and **Streamer** where supported. Compatible Xiaomi units can show an **Eco mode** switch. The controls dim when the AC is off.
- **Edit AC** lets you change a unit’s name, room, or local address, check its connection, or remove it from the app.
- **Settings** lets you add, rename, or delete rooms and turn **Reopen Last AC** on or off. New ACs default to Living Room. ACs in a deleted room move to Living Room or the first remaining room. Keep at least one room.

The temperature buttons use the AC’s supported range and step. The app waits 750 ms after the last tap, sends the final target, and reads it back. It also reads back changes to power, operating mode, fan speed, and extras.

## Install on an iPhone

1. Open `BreezePilot.xcodeproj` in Xcode, select the **BreezePilot** scheme, and choose your iPhone as the destination.
2. In **Signing & Capabilities**, select your development team if Xcode asks. Run the app.
3. Tap **Add AC** and choose the brand. Enter the AC’s name and private IPv4 address, and allow Local Network access. For **Xiaomi / Mijia**, enter the 32-character Xiaomi device token. Tap **Check Connection**, then **Save**.
4. With the AC on in Cool mode, tap **+** or **−** to adjust the target.

The app and each AC need to be on the same home network. Xiaomi setup fetches the public specification for the detected model and saves it on the phone. The device token is stored in Keychain.

## Open the simulator

On Xcode 27, choose **Xcode → Open Developer Tool → Device Hub**. Select the **iPhone 18 Pro** simulator and click **View Screen**.

## Source layout

- `Domain` defines AC state, capabilities, and room readings.
- `Application` defines the device interface and the use case that validates, sends, and confirms a change.
- `Infrastructure` contains the Daikin HTTP and Xiaomi MIoT request providers, model specification lookup, and Keychain storage.
- `Presentation` contains the screen view models and SwiftUI views, including the room readings shared by the list and detail screens.
