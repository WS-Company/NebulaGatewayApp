# Nebula Gateway

A lightweight macOS menu bar application for managing [Nebula](https://github.com/slackhq/nebula) VPN connections.

## Features

- Menu bar app with quick access popover
- Manage multiple Nebula connections
- Start, stop, and restart connections with one click
- Real-time upload/download speed monitoring
- Import and manage Nebula configs and certificates
- Privileged helper for root-level operations (no repeated sudo prompts)

## Requirements

- macOS 14.0 or later
- [Nebula](https://github.com/slackhq/nebula) binary (installed via Homebrew or bundled)
- Xcode 16+ (for building from source)

## Install Nebula

```bash
brew install nebula
```

## Build

```bash
# Install XcodeGen (first time only)
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open NebulaGateway.xcodeproj

# Or build from command line
xcodebuild -scheme NebulaGateway -configuration Release build
```

## Usage

1. Launch Nebula Gateway — it appears in the menu bar as a globe icon
2. Click the globe to open the popover
3. Set up the privileged helper (one-time, requires admin password)
4. Add a Nebula configuration (config.yml + certificates)
5. Click Start to connect

## Configuration

App settings are stored in `~/Library/Application Support/Nebula Gateway/config.toml`.
Logs are in `~/Library/Logs/Nebula Gateway/`.

## License

TBD

## Author

Evgeny Gorbov
