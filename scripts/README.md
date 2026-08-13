# ZKTeco LAN Standalone Background Sync Service

This directory contains the Python background sync service designed by senior GM IT architecture specifications.

It connects directly to ZKTeco biometric scanners over **TCP Port 4370 (Standalone/Pull Mode)**, reads attendance logs, deduplicates records, and syncs them automatically to **Google Cloud Firestore**.

---

## 🛠️ Setup Instructions

### 1. Prerequisites
Make sure Python 3.8+ is installed on the LAN Server PC (or any PC connected to the local router).

```bash
pip install -r requirements.txt
```

### 2. Service Account Key (Firebase)
Download your Firebase Service Account JSON key from the Firebase Console (`Project Settings -> Service Accounts -> Generate new private key`) and save it as `serviceAccountKey.json` inside this directory (or update the path in `config.json`).

### 3. ZKTeco Device Hardware Rules
1. **Turn OFF DHCP** on each ZKTeco device (`Menu -> Network -> Ethernet -> DHCP = OFF`).
2. Assign static IPs to each machine in range (e.g., `192.168.1.150`, `192.168.1.151`, `192.168.1.152`...).
3. Update `config.json` with the static IPs and locations of your scanners.

---

## 🚀 Running the Service

To start the service in continuous daemon mode (polls every 15 seconds):

```bash
python zkteco_sync_service.py
```

To run a single sync cycle and exit:

```bash
python zkteco_sync_service.py --once
```

---

## 🔒 Security & Resilience Features

- **Isolated Scanners**: If Device 2 is unplugged or offline, Device 1 & Device 3 will continue syncing smoothly without crashing the application.
- **Firestore Document Deduplication**: Punches are indexed using unique document keys (`{ip}_{pin}_{timestamp}`), preventing duplicate punches in Firestore.
- **Offline Fallback Queue**: If the internet or Firestore drops temporarily, logs are buffered locally in `pending_punches.json` and automatically flushed when the connection returns.
- **Auto-Sync to Web & Windows Apps**: The Flutter Web and Windows app automatically listen to Firestore punch snapshots, showing incoming finger scans in real-time under **Live Scans & Logs**.
