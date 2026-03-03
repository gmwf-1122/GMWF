# 🏥 GMWF — Clinic Management System

A production-grade **Flutter clinic management app** with offline-first architecture, real-time LAN synchronization, and Firebase Firestore cloud backup. Built for multi-device clinic environments where receptionists, doctors, and dispensers need fast, reliable data — even without internet.

---

## ✨ Features

- **Offline-First** — Every write hits local Hive storage first. The app works fully offline and syncs automatically when connectivity returns.
- **Real-Time LAN Sync** — All devices on the same network stay in sync instantly via WebSocket. No internet required for inter-device communication.
- **Dedicated LAN Server** — A dedicated always-on device runs the LAN server for maximum stability. No dependency on any staff member's device.
- **Multi-Role Support** — Separate flows for receptionist, doctor, dispenser, admin, CEO, and chairman.
- **Firebase Firestore Backup** — All data is asynchronously pushed to Firestore as the cloud source of truth.
- **Smart Reconnect** — Devices that go offline receive a targeted catch-up bundle when they reconnect — not a full re-sync.
- **Cross-Platform** — Supports Android, iOS, Windows, macOS, Linux, and ChromeOS.

---

## 🏗️ Architecture

The system uses a three-tier hybrid architecture:

```
Local Hive Storage  ←→  LAN WebSocket Sync  ←→  Firebase Firestore
(always available)      (dedicated server)        (cloud truth)
```

A **dedicated always-on server device** runs the LAN hub. All staff devices — receptionist, doctor, and dispenser — connect to it as clients. Every write goes to local Hive first — Firestore uploads are always async and queued.

```
                    ┌─────────────────────┐
                    │   Dedicated Server  │
                    │  (always-on device) │
                    │  lan_server.dart    │
                    │  server_sync_mgr    │
                    └──────────┬──────────┘
                               │ WebSocket (port 53281)
          ┌────────────────────┼────────────────────┐
          │                    │                    │
          ▼                    ▼                    ▼
   Receptionist            Doctor              Dispenser
   (client only)          (client)             (client)
   realtime_manager    realtime_manager     realtime_manager
   firestore_service   firestore_service    firestore_service
```

---

## 📁 Project Structure

```
lib/
├── services/
│   ├── firestore_service.dart       # Primary write gateway (Hive + LAN + Firestore)
│   ├── sync_service.dart            # Client-side Firestore uploader
│   ├── auth_service.dart            # Firebase Auth + role-based LAN setup
│   └── offline_auth_service.dart    # Offline credential cache
│
├── lan/
│   ├── lan_host_manager.dart        # Dedicated server lifecycle orchestrator
│   ├── lan_server.dart              # Raw WebSocket server (port 53281)
│   ├── lan_discovery.dart           # mDNS / UDP / subnet scan discovery
│   ├── server_sync_manager.dart     # Server-side data hub & Firestore bridge
│   ├── realtime_manager.dart        # Client WebSocket connection manager
│   ├── realtime_router.dart         # Incoming LAN message handler
│   └── connection_manager.dart      # Connection state machine for UI
│
└── utils/
    └── network_utils.dart           # Cross-platform LAN IP detection
```

---

## 🔄 Data Flow

### Creating a Token (any client device)
```
Staff taps 'Create Token'  (receptionist, doctor, or dispenser)
        │
        ▼
firestore_service.dart
   ├── 1. Save to Hive entriesBox         (immediate, offline-safe)
   ├── 2. Enqueue in syncBox              (queued for Firestore upload)
   ├── 3. Broadcast via RealtimeManager   (LAN WebSocket → dedicated server)
   └── 4. Trigger SyncService upload
        │
        ▼
lan_server.dart  (dedicated server device)
   ├── Routes message to all other branch clients
   └── ServerSyncManager intercepts
        ├── Saves to server's Hive         (immediate)
        └── Enqueues in server_sync_queue  (for Firestore)
        │
   ┌────┴─────────────────────────────────┐
   ▼                                      ▼
Other client devices               Firestore upload
realtime_router.dart               server_sync_manager.dart
   └── Saves to Hive                  └── Uploads when online
                                               │
                                               ▼
                                     Firebase Firestore
```

### Device Reconnect / Catch-up
```
Any client device reconnects to LAN
        │
        ▼
connection_manager.dart → RealtimeManager.reconnect()
        │
        ▼
Dedicated server receives identify message
server_sync_manager.dart
   └── sendToSocket(socketId, missedData)   ← targeted, NOT broadcast
        │
        ▼
realtime_router.dart on reconnected device
   └── Deduplicates by _messageId, saves to Hive
```

### Login / Role Setup
```
User enters credentials
        │
        ▼
offline_auth_service.dart
   └── Checks local cache → returns user offline if valid
        │  (falls through to Firebase if not cached)
        ▼
auth_service.dart → FirebaseAuth.signIn()
        │
        ├── role == server (dedicated device)
        │       └── lan_host_manager.dart.start()
        │               ├── network_utils → detect IP
        │               ├── lan_server → start WebSocket server
        │               └── server_sync_manager → start
        │
        └── role == receptionist / doctor / dispenser
                └── realtime_manager.connect(savedIP)
                        └── connection_manager watches state
```

---

## 🗄️ Local Storage (Hive Boxes)

| Box | Written by | Read by | Purpose |
|-----|-----------|---------|---------|
| `entriesBox` | FirestoreService, RealtimeRouter, SSM | FirestoreService, SyncService | Tokens / queue entries |
| `patientsBox` | FirestoreService, RealtimeRouter | FirestoreService | Patient records |
| `prescriptionsBox` | FirestoreService, RealtimeRouter | ServerSyncManager | Prescriptions |
| `syncBox` | FirestoreService | SyncService | Client upload queue |
| `server_sync_queue` | ServerSyncManager | ServerSyncManager | Server upload queue |
| `app_settings` | AuthService, ConnectionManager | ConnectionManager, SyncService | Saved IP, feature flags |
| `local_edit_requests` | ServerSyncManager | ServerSyncManager | Approved edit requests |

---

## 🔐 Firebase Firestore Paths

```
/branches/{branchId}/patients/{patientId}
/branches/{branchId}/serials/{ddMMyy}/{queueType}/{serial}
/branches/{branchId}/prescriptions/{cnic}/prescriptions/{serial}
/branches/{branchId}/dispensary_records/{date-serial}
```

---

## 🌐 LAN Discovery

Client devices find the dedicated server using three parallel methods — first to succeed wins:

| Method | Typical Speed |
|--------|--------------|
| mDNS (`_gmwftoken._tcp`) | ~1–2 seconds |
| UDP Broadcast | ~2–3 seconds |
| Subnet Scan (batches of 25) | Fallback |

---

## 👥 User Roles

| Role | Device Type | LAN Behaviour |
|------|------------|--------------|
| `server` | Dedicated always-on device | Runs LAN hub — ServerSyncManager + LanServer |
| `receptionist` | Staff tablet/PC | Client only — connects to dedicated server |
| `doctor` | Staff tablet/PC | Client — connects to dedicated server |
| `dispenser` | Staff tablet/PC | Client — connects to dedicated server |
| `admin / ceo / chairman` | Any | No LAN setup — Firestore only |

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `>=3.0.0`
- Dart SDK `>=3.0.0`
- Firebase project with Firestore and Authentication enabled
- A dedicated always-on device to run the LAN server
- All clinic devices must be on the **same local network**

### Installation

```bash
# Clone the repository
git clone https://github.com/your-username/gmwf.git
cd gmwf

# Install dependencies
flutter pub get

# Configure Firebase
# Add your google-services.json (Android) and GoogleService-Info.plist (iOS)
# to the respective platform folders

# Run the app
flutter run
```

### Setup Order

1. Start the **dedicated server device** first — it begins advertising on the LAN immediately.
2. All **staff devices** (receptionist, doctor, dispenser) log in — they auto-discover the server.
3. The server IP is saved locally after first connection for faster reconnects.

---

## 🔧 Key Design Decisions

**Dedicated always-on server** — The server runs on its own device, independent of any staff member. This eliminates the instability that came from tying the LAN hub to the receptionist's device (e.g. device sleep, logout, crash).

**All staff are equal clients** — Receptionist, doctor, and dispenser all connect to the dedicated server the same way. No device has special LAN authority except the server.

**Double-queue system** — Clients use `syncBox` (via `SyncService`), the server uses `server_sync_queue` (via `ServerSyncManager`). Both upload to the same Firestore paths independently.

**No runtime Firestore reads** — After the initial download, all reads come from Hive. Firestore is write-destination and initial-sync-source only. This keeps the app fast and fully offline-capable.

**Targeted catch-up** — When a device reconnects, `ServerSyncManager` sends missed data only to that device's socket. Not a broadcast.

**Echo prevention** — `RealtimeManager` ignores incoming messages that carry its own `_clientId` to avoid processing its own broadcasts.

---

## 📦 Key Dependencies

| Package | Purpose |
|---------|---------|
| `hive` / `hive_flutter` | Local offline storage |
| `firebase_core` / `cloud_firestore` | Cloud sync and backup |
| `firebase_auth` | Authentication |
| `web_socket_channel` | LAN WebSocket communication |
| `bonsoir` | mDNS server discovery |
| `flutter_secure_storage` | Encrypted offline credential cache |
| `connectivity_plus` | Network state detection |

---

## 📄 License

 © 2026 Gulzar Madina Welfare Foundation. All rights reserved.

---

*Built for reliable clinic operations — works offline, syncs when online.*