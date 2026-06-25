# AP Companion [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K2ND3Y8)

An unofficial Flutter companion app for **ALLPOWERS portable power stations**.  
Connect over Bluetooth, monitor battery and power flow in real time, build custom charging automations, and control the station remotely from any phone via MQTT.

---

## Features

### Bluetooth control
- Automatic connection to a previously paired station on launch
- Live battery level with colour-coded ring (red → amber → teal as charge increases)
- Real-time input / output wattage and estimated time remaining
- One-tap toggle for USB, AC, and 12 V DC outlets with haptic feedback
- Optimistic UI — outlet state updates instantly while the BLE relay catches up
- Auto-reconnect after unexpected disconnects with configurable back-off

### Automation flow builder
- Visual step sequencer — build multi-action automations triggered by battery events
- **Trigger types:** battery falls below or rises above a configurable threshold
- **Optional time window** — restrict a trigger to a specific time range, with correct handling of windows that cross midnight
- **Action steps (in any order, any number):**
  - **Wait** — pause for N seconds before the next step
  - **Set BLE outlet** — turn USB, AC, or DC on or off directly via Bluetooth
  - **Fire webhook** — send an HTTP GET request to any URL (Tapo, Voice Monkey, Home Assistant, etc.)
  - **Control Tapo** — turn a TP-Link Tapo smart plug on or off via the local KLAP protocol
- Drag-to-reorder steps, swipe-to-delete flows
- Per-flow edge-triggered guards persisted across app restarts — a flow fires once per threshold crossing and never re-fires until the battery recovers
- Starter templates replicate the classic "start charging at 10 %, stop at 95 %" sequence

### TP-Link Tapo integration (local network)
- Direct control via the **KLAP protocol** — no cloud required
- Automatic retry on transient failures
- Test connection button with friendly error messages
- Falls back to webhook URLs if the local connection fails

### Energy log
- Periodic snapshots of battery level, input watts, and output watts (default every 5 minutes)
- Interactive time-series charts with tap-to-inspect crosshair and chronological step buttons
- Zoom ranges: 3 h, 6 h, 24 h, 7 d, 30 d, All
- Aggregate stats: average and peak input / output per range
- Compact pipe-delimited storage — handles tens of thousands of entries without bloating SharedPreferences

### Automation history
- Timestamped log of every automation action with the battery level that triggered it
- Shows whether the action succeeded and which path carried it out (local Tapo, webhook, or none)

### Remote access via MQTT
Three operating modes selectable at runtime:

| Mode | Description |
|------|-------------|
| **Standalone** | Classic BLE-only. No broker involved. |
| **Gateway** | Holds the BLE connection, publishes telemetry, and executes remote outlet commands. Runs a foreground service to stay alive in the background. |
| **Client** | No BLE required. Monitors the station and sends outlet commands through the broker from anywhere. |

- Supports any standard MQTT broker (HiveMQ Cloud, Mosquitto, etc.)
- TLS / plain connections with optional username and password
- Status published as retained JSON so a freshly-connected client gets current state immediately
- **Flow sync** — automations edited on either the gateway or any client phone are published to `{prefix}/flows` as a retained message and applied on all connected devices in real time. The gateway is always the one that executes them.
- Outlet commands relay with ~1 s latency through the broker
- Exponential back-off reconnect (5 s → 60 s cap) with auto-reconnect on network drops

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
2. Set a **trigger** — choose *Falls below* or *Rises above*, set the threshold percentage, and optionally restrict to a time window.
3. Add **steps** in any order:
   - **Wait** — enter the number of seconds to pause.
   - **Set BLE outlet** — pick USB / AC / DC and the desired state.
   - **Fire webhook** — enter any HTTP URL.
   - **Control Tapo** — configure credentials in **Settings** first.
4. Drag handles to reorder steps. Swipe left to delete a flow.
5. Toggle the switch on each flow card to enable or disable it without deleting it.

### Tapo credentials

Go to **Settings → Local Tapo Control**, enter the plug's local IP address and your TP-Link account email and password, then tap **Test Connection** to verify.

---

## Remote access (MQTT)

### Gateway phone setup

1. Open **Settings → Remote Access**.
2. Select **Gateway** mode.
3. Enter your broker host, port, and credentials. Enable TLS if using port 8883.
4. Set a **topic prefix** (e.g. `ap/garage`) — all devices sharing a station must use the same prefix.
5. Tap **Test Broker Connection** to verify.

The gateway publishes status every 5 seconds (immediately on outlet state changes) and subscribes to outlet commands and flow updates from clients.

### Client phone setup

1. Open **Settings → Remote Access**.
2. Select **Client** mode.
3. Enter the same broker and topic prefix as the gateway.
4. The **Control** tab now shows the remote station's live status and outlet controls.
5. The **Automation** tab shows the shared flow list — edits sync to the gateway automatically.

> Energy and History tabs are only available on the gateway / standalone device, since the data is recorded locally there.

### Broker recommendations

| Provider | Free tier | Notes |
|----------|-----------|-------|
| [HiveMQ Cloud](https://www.hivemq.com/mqtt-cloud-broker/) | 100 connections | Use port **8883** with TLS **ON** |
| Self-hosted Mosquitto | Unlimited | Port 1883 plain or 8883 with certs |

---

## Architecture overview

```
MainShell
├── BleService          — scanning, connecting, packet parsing, outlet commands
├── FlowEngine          — evaluates AutomationFlow list against live status
│   ├── WebhookService  — HTTP GET actions
│   └── TapoService     — KLAP protocol actions
├── MqttService         — gateway/client pub-sub, flow sync
├── EnergyLogService    — throttled BLE snapshot recording
├── HistoryService      — automation action log
├── NotificationService — low-battery alerts
├── StorageService      — SharedPreferences wrapper (settings, flows, logs)
└── ForegroundService   — Android background persistence (standalone + gateway only)
```

All services are plain Dart classes — no external state management library. `BleService`, `HistoryService`, `EnergyLogService`, and `MqttService` extend `ChangeNotifier`; widgets rebuild via `AnimatedBuilder`.

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_blue_plus` | BLE scanning and communication |
| `permission_handler` | Runtime Bluetooth and location permissions |
| `flutter_local_notifications` | Low-battery push notifications |
| `flutter_foreground_task` | Android foreground service and boot autostart |
| `mqtt_client` | MQTT broker communication |
| `shared_preferences` | Persistent settings and log storage |
| `http` | Webhook HTTP requests |
| `crypto` + `pointycastle` | Tapo KLAP protocol cryptography |

---

## Limitations

- The KLAP Tapo integration has been tested against firmware versions current as of mid-2026 (1.5.5). TP-Link occasionally changes the protocol; if the test connection fails after a firmware update, open an issue.
- SharedPreferences is not designed for large binary blobs. The energy log is capped at 8 640 entries (~30 days at 5-minute intervals).
- Tapo credentials are stored in plain SharedPreferences.
- This is an **unofficial** app. ALLPOWERS and TP-Link are trademarks of their respective owners.

---
