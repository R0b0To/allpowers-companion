# AP Companion [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8) [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

An unofficial Flutter companion app for **ALLPOWERS portable power stations**.
Connect over Bluetooth, monitor battery and power flow in real time, build custom charging automations, and control the station remotely from any phone via MQTT.

---

## Features

### Bluetooth control
- Automatic connection to a previously paired station on launch
- Live battery level with colour-coded ring (red → amber → teal as charge increases)
- Real-time input / output wattage and estimated time remaining
- One-tap toggle for USB, AC, and 12 V DC outlets with haptic feedback
- Optimistic UI — outlet state updates instantly while the BLE relay catches up, protected by a short manual-override window so an in-flight status broadcast can't immediately flip it back
- **Confirmed commands** — outlet toggles wait for the station's own status broadcast to echo back the expected socket mask before being reported as successful, rather than trusting the write alone
- Connection watchdog — forces a reconnect if no packet has arrived for 45 s, even if the OS still reports "connected" (guards against "zombie" GATT links on some OEMs)
- Keepalive — proactively re-requests a status broadcast every 20 s, which resolves most missed-broadcast cases in under a second without a full reconnect
- Auto-reconnect after unexpected disconnects with linear back-off (2 s × attempt, capped at 30 s)

### Automation flow builder
- Visual step sequencer — build multi-action automations triggered by battery or smart-plug events
- **Trigger types:** battery falls below or rises above a configurable threshold, or a Tapo plug entering a specific state
- Battery triggers can also **require a Tapo plug to be in a specific state** at the same time (e.g. "battery below 10% AND plug is off") via an AND condition on the trigger
- **Optional time window** — restrict a trigger to a specific time range, with correct handling of windows that cross midnight (required for the plug-state trigger, optional for battery triggers)
- **Action steps (in any order, any number):**
  - **Wait** — pause for N seconds before the next step
  - **Set BLE outlet** — turn USB, AC, or DC output on or off directly via Bluetooth, confirmed against a real status packet before the flow continues
  - **Fire webhook** — send an HTTP GET request to any URL (Tapo, Voice Monkey, Home Assistant, etc.); a plain-`http://` URL logs a warning that credentials/tokens in the query string travel in cleartext
  - **Control Tapo** — turn a TP-Link Tapo smart plug on or off via the local KLAP protocol, confirmed by reading the device's own state back
- Drag-to-reorder steps, swipe-to-delete flows
- Per-flow edge-triggered guards persisted across app restarts — a flow fires once per threshold/state crossing and never re-fires until the condition resets
- A step that fails to confirm aborts the rest of that flow run rather than continuing on unconfirmed state
- Starter templates replicate the classic "start charging at 10 %, stop at 95 %" sequence

### TP-Link Tapo integration (local network)
- Direct control via the **KLAP protocol** — no cloud required
- Devices are added from the **Devices** tab (name, IP, TP-Link account e-mail/password), with a built-in **Test Connection** button
- Automatic retry on transient failures (one retry after a short delay) for status polls and commands
- Sessions are cached per plug and evicted LRU-style once more than 16 are open, so editing or churning through devices over time can't leak memory indefinitely

### Energy log
- Periodic snapshots of battery level, input watts, and output watts (default every 5 minutes), throttled against the last *stored* sample so a relaunch never backfills
- Backed by a local SQLite database rather than SharedPreferences, so each new sample is a single row insert instead of rewriting the whole log
- Interactive time-series charts with tap-to-inspect crosshair and chronological step buttons
- Zoom ranges: 3 h, 6 h, 24 h, 7 d, 30 d, All
- Aggregate stats: average and peak input / output per range, computed once per range change rather than on every frame
- Capped at 8,640 samples (30 days at the default 5-minute interval); older rows are pruned automatically
- A pre-existing SharedPreferences-based log from older installs is migrated into SQLite automatically on first launch after upgrading

### Automation history
- Timestamped log of every automation action with the battery level that triggered it
- Shows whether the action succeeded and which path carried it out (local Tapo, webhook, BLE outlet, or none)
- Synced to client phones over MQTT — the gateway pushes each new entry live, plus a full retained snapshot on every (re)connect so a client is never stuck on stale history

### Remote access via MQTT
Three operating modes selectable at runtime:

| Mode | Description |
|------|-------------|
| **Standalone** | Classic BLE-only. No broker involved. |
| **Gateway** | Holds the BLE connection, publishes telemetry, and executes remote outlet/Tapo/flow commands. Runs a foreground service to stay alive in the background. |
| **Client** | No BLE required (the local Bluetooth stack is paused entirely to avoid contending with the gateway for the station's single connection slot). Monitors the station, browses devices and history, and sends commands through the broker from anywhere. |

- Supports any standard MQTT broker (HiveMQ Cloud, Mosquitto, etc.), TLS or plain, with optional username/password
- The Settings screen advises — without blocking the connection — when a configuration looks risky: a recognisably public/shared test broker, TLS disabled, or no credentials set
- Status is published as a retained message with a Last Will and Testament, so a gateway that disappears uncleanly (crash, force-quit, dead Wi-Fi) is reported offline immediately rather than leaving clients trusting stale "everything is fine" data
- On every successful (re)connect the gateway republishes its full state — status, Tapo devices, and a history snapshot — so a client is never left waiting on the next organic change
- **Flow sync** — automations edited on either the gateway or any client phone are published as a retained message and applied on all connected devices in real time. The gateway is always the one that executes them
- **Tapo device sync** — the gateway publishes live plug state (online/on/model) as a retained message; clients display and control it via RPC
- Outlet, Tapo, and flow-management commands go through a request/response RPC channel with a 10 s timeout and correlation IDs, relaying with roughly 1 s of latency
- Reconnects use a linear back-off (5 s × attempt, capped at 60 s); the gateway also republishes its status on a 30 s heartbeat during idle periods

### Other
- Android foreground service with persistent notification showing battery %, watts in/out, and time remaining — skipped entirely in client mode
- Boot autostart (Android) so the gateway resumes monitoring after a reboot
- Low-battery push notification with debounce — fires once per threshold crossing, resets when the battery recovers
- English and Italian localisation
- Dark theme with teal accent throughout

---

## Requirements

- Flutter SDK **3.12+** / Dart **3.12+**
- A supported ALLPOWERS power station with BLE (tested r2500v2 series)
- For Tapo integration: a TP-Link Tapo smart plug (P100 / P110 or compatible) on the same local network as the gateway phone

---

## Getting started

### 1. Clone

```bash
git clone https://github.com/R0b0To/allpowers-companion.git
cd ap_companion
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Run

```bash
flutter run
```

For a release build:

```bash
flutter build apk --release          # Android
```

### 4. Pair your station

1. Power on your ALLPOWERS station.
2. Open the app and tap **Scan for Station**.
3. Select your device from the list — the app connects and saves it for future auto-connect.

---

## Automation setup

### Quick start with templates

Go to **Automation → Build from scratch** or tap **Use charging templates** to get two pre-built flows:

- **Start Charging** — fires when battery falls below 10 % between 21:00 and 08:00: cuts AC, waits 5 s, turns the Tapo plug on, waits 10 s, restores AC.
- **Stop Charging** — fires when battery rises above 95 %: restores AC, turns the Tapo plug off.

### Custom flows

1. Tap **+** to create a new automation.
2. Set a **trigger** — choose *Falls below*, *Rises above*, or *Plug State*; set the threshold percentage (for battery triggers), and optionally restrict to a time window. Battery triggers can also require a specific Tapo plug state at the same time via **Also require plug state**.
3. Add **steps** in any order:
   - **Wait** — enter the number of seconds to pause.
   - **Set BLE outlet** — pick USB / AC / DC and the desired state.
   - **Fire webhook** — enter any HTTP URL.
   - **Control Tapo** — pick a configured device and the desired state.
4. Drag handles to reorder steps. Swipe left to delete a flow.
5. Toggle the switch on each flow card to enable or disable it without deleting it.

### Adding a Tapo device

Go to the **Devices** tab and tap **Add device**. Enter a name, the plug's local IP address, and your TP-Link account e-mail and password, then tap **Test** to verify before saving.

---

## Remote access (MQTT)

### Gateway phone setup

1. Open **Settings → Remote Access**.
2. Select **Gateway** mode.
3. Enter your broker host, port, and credentials. Enable TLS if using port 8883.
4. Set a **topic prefix** (e.g. `ap/garage`) — all devices sharing a station must use the same prefix.
5. Tap **Test Broker Connection** to verify.

The gateway publishes status on change (or at least every 30 s) and subscribes to outlet/Tapo/flow-management commands from clients.

### Client phone setup

1. Open **Settings → Remote Access**.
2. Select **Client** mode.
3. Enter the same broker and topic prefix as the gateway.
4. The **Control** tab now shows the remote station's live status and outlet controls.
5. The **Devices** and **Automation** tabs mirror the gateway's Tapo plugs, flows, and history — edits to flows sync back automatically.

> The Energy tab is only available on the gateway / standalone device, since samples are recorded locally there and are not synced over MQTT.

### Broker recommendations

| Provider | Free tier | Notes |
|----------|-----------|-------|
| [HiveMQ Cloud](https://www.hivemq.com/mqtt-cloud-broker/) | 100 connections | Use port **8883** with TLS **ON** |
| Self-hosted Mosquitto | Unlimited | Port 1883 plain or 8883 with certs |

---

## Architecture overview

```
AppCoordinator                  — owns every service and all cross-service wiring
├── BleService                  — scanning, connecting, watchdog/keepalive, confirmed outlet commands
│   └── StatusPacketParser      — pure BLE status-packet decoding (unit tested)
├── FlowEngine                  — evaluates AutomationFlow list against live BLE + Tapo state
│   ├── WebhookService          — HTTP GET actions
│   └── TapoService             — KLAP protocol actions (LRU-capped sessions, retry policy)
├── TapoDeviceService           — polls and holds saved Tapo plugs' live state
├── MqttService                 — gateway/client pub-sub, RPC, flow/history/device sync
│   └── MqttMessageRouter       — pure topic/payload decoding (unit tested)
├── EnergyLogService            — throttled BLE snapshot recording
├── HistoryService               — automation action log
├── NotificationService         — low-battery alerts
└── ForegroundService           — Android background persistence (standalone + gateway only)

AppRepositories                 — composition root for persistence
├── SharedPreferencesSource     — shared handle for non-sensitive config (flows, thresholds,
│                                  topic prefix, dashboard layout, history) — one JSON blob per
│                                  feature, written atomically
├── SecureStorageSource         — Tapo device passwords and the MQTT broker password, backed by
│                                  the Android Keystore / iOS Keychain
└── EnergyLogDatabase           — SQLite database backing the energy log
```

All services are plain Dart classes — no external state management library. `BleService`, `HistoryService`, `EnergyLogService`, `TapoDeviceService`, and `MqttService` extend `ChangeNotifier`; widgets rebuild via `AnimatedBuilder`. Repositories that previously stored data in an older or less secure format (plaintext passwords, per-field SharedPreferences keys, the pre-SQLite energy log) migrate it automatically the first time they're loaded after an upgrade.

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_blue_plus` | BLE scanning and communication |
| `permission_handler` | Runtime Bluetooth and location permissions |
| `flutter_local_notifications` | Low-battery push notifications |
| `flutter_foreground_task` | Android foreground service and boot autostart |
| `mqtt_client` | MQTT broker communication |
| `shared_preferences` | Persistent non-sensitive settings and log storage |
| `flutter_secure_storage` | Encrypted storage for Tapo and MQTT broker passwords |
| `sqflite` + `path` | SQLite-backed energy log storage |
| `http` | Webhook HTTP requests |
| `crypto` + `pointycastle` | Tapo KLAP protocol cryptography |

---

## Limitations

- The KLAP Tapo integration has been tested against firmware versions current as of mid-2026 (1.5.5). TP-Link occasionally changes the protocol; if the test connection fails after a firmware update, open an issue.
- The energy log is capped at 8,640 samples (~30 days at the default 5-minute interval); older samples are pruned automatically.
- The MQTT command/RPC channel has no application-level authentication beyond whatever the broker itself enforces — anyone who can publish to your topic prefix can control the station. Use a private broker, TLS, and real credentials; the app will warn you in Settings if your current configuration looks risky.
- This is an **unofficial** app. ALLPOWERS and TP-Link are trademarks of their respective owners.

---

## License

This project is licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE) for the full text.
