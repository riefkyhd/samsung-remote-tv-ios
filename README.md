# Samsung Remote TV (iOS)

Samsung Remote TV is a SwiftUI iOS app for discovering Samsung TVs on local network, pairing with encrypted models, and controlling TV functions (power, volume, channel, D-pad, media, quick-launch shortcuts, and trackpad-like navigation).

## Features

- Auto discovery via Bonjour, SSDP, and IP-range scanning
- Saved TVs with rename, forget pairing, and remove device support
- Protocol handling for:
  - Modern WebSocket TVs
  - Legacy encrypted SPC TVs (PIN pairing)
  - Legacy remote transport
- Remote controls:
  - D-pad, number pad, media controls, color buttons
  - Volume/channel controls
  - Quick Launch sheet (curated app shortcuts)
  - Trackpad mode
- Connection state + reconnect flow
- Wake-on-LAN for supported models

## Project Structure

- `Samsung Remote TV/`
  - `Data/` network clients, discovery, repository, storage
  - `Domain/` models, repository protocol, use cases
  - `Presentation/` SwiftUI screens + view models
  - `Utilities/` helpers

## Requirements

- macOS with Xcode (latest stable recommended)
- iOS deployment target as defined in the Xcode project
- Devices on same local network for discovery/control

## Run

1. Open the project/workspace in Xcode.
2. Select the `Samsung Remote TV` scheme.
3. Build and run on simulator or physical device.

## Pairing Notes (Encrypted TVs)

- Keep TV turned on and connected to the same Wi-Fi.
- PIN sheet appears when pairing is required.
- Enter the PIN shown on TV.
- If pairing data is stale, use **Forget Pairing** in Settings and pair again.
- Use **Remove Device** when you want to clear pairing data and delete the saved TV entry.

## Storage

- Kept in `UserDefaults` (non-sensitive):
  - saved TVs
  - remote name
  - SPC device ID
- Stored in Keychain (sensitive):
  - TV token
  - SPC credentials
  - SPC variants

Legacy sensitive values previously stored in `UserDefaults` are migrated to Keychain on read and then removed from legacy storage.

## Logging

Runtime diagnostics are prefixed with `TVDBG`.

Useful tags include:

- `TVDBG][Repo` repository-level connection flow
- `TVDBG][SPC` encrypted pairing / SPC transport
- `TVDBG][UI` UI-level connection and error messages

## Troubleshooting

- TV not found:
  - Ensure iPhone and TV are on same subnet.
  - Pull to refresh on discovery screen.
- Cannot control after reconnect:
  - Retry connection from remote screen.
  - Forget pairing and re-pair if token/session expired.
- No PIN shown on TV:
  - Retry pairing and ensure CloudPIN page is running on TV.

## License

No license file is currently included. Add one if you plan to distribute or open source the project.
