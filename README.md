<p align="center">
  <img src="NebulaGateway/Resources/Assets.xcassets/AboutLogo.imageset/logo.svg" width="120" height="120" alt="Nebula Gateway">
</p>

<h1 align="center">Nebula Gateway</h1>

<p align="center">
  A lightweight macOS menu bar application for managing <a href="https://github.com/slackhq/nebula">Nebula</a> VPN connections.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-Apache%202.0-green" alt="License">
</p>

---

## Overview

Nebula Gateway provides a native macOS interface for [Nebula](https://github.com/slackhq/nebula) — an open-source overlay networking tool developed by Slack. Instead of managing Nebula connections through the terminal, Nebula Gateway lets you start, stop, and monitor your VPN tunnels directly from the menu bar.

Built with SwiftUI. No Electron. No web views. Just a fast, native macOS experience.

## Features

- **Menu bar app** — lives in your menu bar, stays out of the way
- **Multiple connections** — manage several Nebula configs simultaneously
- **One-click controls** — start, stop, and restart connections instantly
- **Live speed monitoring** — real-time upload/download speed for each connection
- **Configuration manager** — import, edit, and organize Nebula configs and certificates
- **Local storage** — optionally copy configs into the app's secure storage with standardized file naming
- **Privileged helper** — XPC-based launch daemon handles root operations, no repeated sudo prompts
- **Localization-ready** — all UI strings externalized for easy translation
- **Nebula auto-detection** — automatically finds Homebrew-installed Nebula, falls back to bundled binary

## Screenshots

*Coming soon*

## Requirements

- macOS 14.0 (Sonoma) or later
- [Nebula](https://github.com/slackhq/nebula) binary
- Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for building from source)

## Installation

### Install Nebula

```bash
brew install nebula
```

### Build from source

```bash
# Clone the repository
git clone https://github.com/WS-Company/NebulaGatewayApp.git
cd NebulaGatewayApp

# Install XcodeGen (first time only)
brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Open in Xcode
open NebulaGateway.xcodeproj
```

Build and run with **Cmd+R**, or build from the command line:

```bash
xcodebuild -scheme NebulaGateway -configuration Release build
```

## Usage

1. **Launch** — Nebula Gateway appears as an icon in your menu bar
2. **Setup helper** — on first launch, install the privileged helper (one-time, requires admin password)
3. **Add connection** — click "Add configuration" and select your Nebula `config.yml`
4. **Connect** — click **Start** to bring up the tunnel
5. **Monitor** — view connection status and live traffic speed in the popover

### Configuration storage

| Path | Contents |
|------|----------|
| `~/Library/Application Support/Nebula Gateway/config.toml` | App settings and connection list |
| `~/Library/Application Support/Nebula Gateway/connections/` | Locally stored configs and certificates |
| `~/Library/Logs/Nebula Gateway/` | Application and per-connection logs |

### Local storage

When you click **Move to local storage**, the app copies your config and all referenced PKI files (CA cert, node cert, private key) into its own directory with standardized names:

```
connections/connection_1/
├── config.yml
├── pki_ca.crt
├── pki_cert.crt
└── pki_key.key
```

Paths inside `config.yml` are automatically rewritten to point to the local copies.

## Architecture

```
NebulaGateway/
├── App/            # Entry point, global state
├── Views/
│   ├── Popover/    # Menu bar popover UI
│   ├── Settings/   # Configuration editor, About tab
│   └── Shared/     # Reusable components
├── Models/         # Data models (ConnectionConfig, ConnectionState, etc.)
├── Services/       # Business logic (NebulaService, HelperManager, NetworkMonitor, etc.)
├── XPC/            # Shared XPC protocol definition
├── Utilities/      # Logger, constants
└── Resources/      # Assets, localization strings

NebulaGatewayHelper/    # Privileged XPC helper daemon
├── main.swift          # XPC listener entry point
├── HelperTool.swift    # Nebula process management
└── launchd.plist       # LaunchDaemon configuration
```

### How it works

1. The **main app** runs as a menu bar accessory and communicates with the **privileged helper** via XPC
2. The **helper** runs as a LaunchDaemon (root) and manages Nebula processes — starting, stopping, and reporting status
3. The app **polls** the helper every 3 seconds to detect running connections, including those started before the app launched
4. **Network speed** is measured by reading interface byte counters via `getifaddrs()` on the tun interface created by Nebula

## Built with

- [Nebula](https://github.com/slackhq/nebula) — scalable overlay networking tool by Slack
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — Xcode project generator
- SwiftUI and the Observation framework

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

This project is licensed under the Apache License 2.0 — see the [LICENSE](LICENSE) file for details.

## Author

Evgeny Gorbov — [WS.Company](https://github.com/WS-Company)
