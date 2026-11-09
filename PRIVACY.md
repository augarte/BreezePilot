# Privacy

BreezePilot does not use advertising, analytics, or tracking. It does not require a BreezePilot account.

## Data on your iPhone

BreezePilot stores saved AC and room names, local IP addresses, model information, and preferences on the iPhone. It shares the saved AC details with its widget through an iOS App Group. Xiaomi device tokens are stored in the iPhone’s Keychain and used to authenticate to the AC. iOS manages backups of app data.

## Network connections

- BreezePilot uses Local Network access to read status and send commands to your AC. Daikin control uses unencrypted HTTP on your local network.
- During Xiaomi setup, BreezePilot fetches public model specifications from `miot-spec.org` over HTTPS. The service receives ordinary connection information, such as your internet IP address. The request does not include your AC token or readings.
- The optional Xiaomi token help link opens a third-party tool’s documentation on GitHub in your browser.

## Manage your data

Remove a saved AC in **Edit AC** to delete its configuration and stored token. Manage rooms in **Settings**. You can disable Local Network access in iPhone Settings and enable it again to resume AC control.
