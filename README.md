# Nebula Gateway

A lightweight macOS menu bar application for managing [Nebula](https://github.com/slackhq/nebula) VPN connections.

## Features

- Menu bar app with quick access popover
- Manage multiple Nebula connections
- Start, stop, and restart connections with one click
- Real-time upload/download speed monitoring
- Import and manage Nebula configs and certificates
- Privileged helper for root-level operations (no repeated sudo prompts)
- The official Nebula release bundled in the app

## Requirements

- macOS 14.0 or later
- Xcode 16+ (for building from source)

## Nebula

The app ships the official [Nebula](https://github.com/slackhq/nebula) release (1.11.2, signed by Defined Networking)
in `Contents/Helpers`; no separate install is needed. The privileged helper copies `nebula` to
`/Library/Application Support/NebulaGateway/bin/` and runs that copy only if its sha256 matches
`NebulaGatewayHelper/BundledNebula.swift`.

## Build

```bash
# Install XcodeGen (first time only)
brew install xcodegen

# Fetch the official nebula binaries into Vendor/nebula/ (checked by sha256)
tools/fetch-nebula.sh

# Generate Xcode project
xcodegen generate

# Open in Xcode
open NebulaGateway.xcodeproj

# Or build from command line
xcodebuild -scheme NebulaGateway -configuration Release build
```

The helper accepts connections only from `com.nebulagateway.app` signed by the Apple team named in `clientRequirement`
(`NebulaGatewayHelper/HelperTool.swift`). A build signed by another team needs that team's ID there.

## Usage

1. Launch Nebula Gateway — it appears in the menu bar as a globe icon
2. Click the globe to open the popover
3. Set up the privileged helper (one-time, requires admin password)
4. Add a Nebula configuration (config.yml + certificates)
5. Press "Move to local storage": the helper runs only configs from the app's storage, so Start stays disabled until
   then
6. Click Start to connect

## Configuration

App settings are stored in `~/Library/Application Support/Nebula Gateway/config.toml`, and connections moved to local
storage in `~/Library/Application Support/Nebula Gateway/connections/`.
Logs are in `~/Library/Logs/Nebula Gateway/`; the helper writes each connection's log to `/Library/Logs/NebulaGateway/`.

## License

TBD

## Author

Evgeny Gorbov
