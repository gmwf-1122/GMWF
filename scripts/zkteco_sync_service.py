#!/usr/bin/env python3
"""
ZKTeco LAN Standalone Service to Cloud Firestore Sync
-----------------------------------------------------
Description:
    Connects to ZKTeco biometric devices over TCP port 4370 (Standalone/Pull Mode),
    fetches attendance logs from internal memory chips, deduplicates records,
    and pushes them directly to Google Cloud Firestore in real time.

Features:
    1. Isolated try/except per device so unplugged/offline scanners won't crash the script.
    2. Document-level deduplication on Firestore (doc_id = "{device_ip}_{user_id}_{timestamp}").
    3. Offline fallback buffer (pending_punches.json) if internet/Firestore drops temporarily.
    4. Optional hardware memory clearing (conn.clear_attendance()) to prevent memory full.
    5. Automatic daemon loop running every 15 seconds (configurable).

Dependencies:
    pip install pyzk firebase-admin

Usage:
    python zkteco_sync_service.py --config config.json
"""

import os
import sys
import json
import time
import argparse
from datetime import datetime

# Configure Windows stdout for UTF-8 encoding
if sys.platform == "win32" and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

# Automatic Dependency Installer (Self-healing import)
def _ensure_package(module_name, pip_name=None):
    pip_name = pip_name or module_name
    try:
        __import__(module_name)
    except ImportError:
        print(f"[INFO] Package '{pip_name}' is missing. Installing automatically via pip...")
        import subprocess
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", pip_name])
            print(f"[INFO] Successfully installed '{pip_name}'.")
        except Exception as e:
            print(f"[ERROR] Failed to auto-install '{pip_name}': {e}")

_ensure_package("zk", "pyzk")
_ensure_package("firebase_admin", "firebase-admin")

# Import ZKTeco library (pyzk)
from zk import ZK

# Import Firebase Admin SDK
import firebase_admin
from firebase_admin import credentials, firestore


# Default Configuration
DEFAULT_CONFIG = {
    "sync_interval_seconds": 15,
    "firebase_credentials_path": "serviceAccountKey.json",
    "clear_memory_after_sync": False,
    "devices": [
        {
            "name": "Office HQ Main Gate Scanner",
            "ip": "192.168.1.150",
            "port": 4370,
            "location": "Office/Dasterkhwaan"
        },
        {
            "name": "Dispensary Medical Scanner",
            "ip": "192.168.1.151",
            "port": 4370,
            "location": "Dispensary"
        },
        {
            "name": "Madrassa Gate Scanner",
            "ip": "192.168.1.152",
            "port": 4370,
            "location": "Madrassa"
        },
        {
            "name": "GMWF Model School Scanner",
            "ip": "192.168.1.153",
            "port": 4370,
            "location": "School"
        },
        {
            "name": "Dasterkhwaan Kitchen Scanner",
            "ip": "192.168.1.154",
            "port": 4370,
            "location": "Dasterkhwaan Kitchen"
        },
        {
            "name": "Auxiliary Staff Scanner",
            "ip": "192.168.1.155",
            "port": 4370,
            "location": "Office/Dasterkhwaan"
        }
    ]
}

OFFLINE_BUFFER_FILE = "pending_punches.json"
STATE_FILE = "synced_keys.json"


def load_config(config_path="config.json"):
    """Loads configuration from JSON file or generates default if missing."""
    if os.path.exists(config_path):
        with open(config_path, "r") as f:
            try:
                return json.load(f)
            except Exception as e:
                print(f"[WARN] Failed to parse {config_path}: {e}. Using default configuration.")
    else:
        with open(config_path, "w") as f:
            json.dump(DEFAULT_CONFIG, f, indent=4)
        print(f"[INFO] Created template configuration file at: {os.path.abspath(config_path)}")
    return DEFAULT_CONFIG


def init_firebase(creds_path):
    """Initializes Firebase Admin SDK smoothly with local buffer fallback."""
    if firebase_admin._apps:
        try:
            return firestore.client()
        except Exception:
            return None

    if os.path.exists(creds_path):
        try:
            cred = credentials.Certificate(creds_path)
            firebase_admin.initialize_app(cred)
            print(f"[FIREBASE] Initialized with credentials file: {creds_path}")
            return firestore.client()
        except Exception as e:
            print(f"[WARN] Error loading {creds_path}: {e}")

    print("[FIREBASE] Running in Local Storage Mode (Buffering scans to 'pending_punches.json').")
    print("[FIREBASE] To sync directly to Cloud Firestore, place 'serviceAccountKey.json' in scripts/ directory.")
    return None


def load_synced_keys():
    """Loads already processed punch keys to prevent re-processing."""
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                return set(json.load(f))
        except Exception:
            return set()
    return set()


def save_synced_keys(keys_set):
    """Saves synced keys set to state file (capped at 20,000 entries)."""
    keys_list = list(keys_set)
    if len(keys_list) > 20000:
        keys_list = keys_list[-10000:]  # Keep latest 10k entries
    with open(STATE_FILE, "w") as f:
        json.dump(keys_list, f)


def save_offline_punch(punch):
    """Saves punch to offline buffer file if Firestore is unreachable."""
    pending = []
    if os.path.exists(OFFLINE_BUFFER_FILE):
        try:
            with open(OFFLINE_BUFFER_FILE, "r") as f:
                pending = json.load(f)
        except Exception:
            pending = []

    pending.append(punch)
    with open(OFFLINE_BUFFER_FILE, "w") as f:
        json.dump(pending, f, indent=2)


def flush_offline_buffer(db):
    """Attempts to push unsent offline buffered punches to Firestore."""
    if not db or not os.path.exists(OFFLINE_BUFFER_FILE):
        return

    try:
        with open(OFFLINE_BUFFER_FILE, "r") as f:
            pending = json.load(f)

        if not pending:
            return

        print(f"[SYNC] Found {len(pending)} offline buffered punches. Uploading to Firestore...")
        remaining = []

        for punch in pending:
            doc_id = punch.get("doc_id") or f"{punch['deviceIp']}_{punch['pin']}_{punch['timestamp']}"
            try:
                db.collection("biometric_punches").document(doc_id).set(punch, merge=True)
            except Exception as e:
                print(f"[WARN] Failed to flush punch {doc_id}: {e}")
                remaining.append(punch)

        with open(OFFLINE_BUFFER_FILE, "w") as f:
            json.dump(remaining, f, indent=2)

        if not remaining:
            print("[SYNC] ✅ All offline buffered punches flushed successfully!")

    except Exception as e:
        print(f"[WARN] Error reading offline buffer file: {e}")


def fetch_and_sync_device(device_cfg, db, synced_keys, clear_memory=False):
    """
    Connects to a single ZKTeco device via pyzk on port 4370.
    Wrapped in isolated try/except so one offline device won't break others.
    """
    ip = device_cfg.get("ip")
    port = device_cfg.get("port", 4370)
    name = device_cfg.get("name", f"ZKTeco ({ip})")
    location = device_cfg.get("location", "Office")

    print(f"\n[DEVICE] Connecting to {name} at {ip}:{port}...")

    zk = ZK(ip, port=port, timeout=5, password=0, force_udp=False, ommit_ping=False)
    conn = None

    try:
        conn = zk.connect()
        print(f"[DEVICE] ✅ Connected to {name} ({ip})")

        # Disable device during read operation to prevent concurrent writes
        conn.disable_device()

        # Fetch attendance logs from internal memory
        attendances = conn.get_attendance()
        print(f"[DEVICE] Read {len(attendances)} total raw log records from {name}")

        new_punches_count = 0

        for atten in attendances:
            pin = str(atten.user_id).strip()
            timestamp_dt = atten.timestamp
            timestamp_str = timestamp_dt.isoformat()

            # Unique deduplication key
            dedup_key = f"{ip}_{pin}_{timestamp_str}"

            if dedup_key in synced_keys:
                continue

            synced_keys.add(dedup_key)
            new_punches_count += 1

            doc_id = f"{ip}_{pin}_{timestamp_dt.strftime('%Y%m%d_%H%M%S')}"

            punch_record = {
                "id": doc_id,
                "doc_id": doc_id,
                "pin": pin,
                "timestamp": timestamp_str,
                "deviceIp": ip,
                "deviceName": name,
                "buildingLocation": location,
                "source": "python_zk_service",
                "syncedAt": datetime.now().isoformat()
            }

            if db:
                try:
                    db.collection("biometric_punches").document(doc_id).set(punch_record, merge=True)
                    print(f"  └─ [SYNCED] PIN: {pin} | Time: {timestamp_str} | Loc: {location}")
                except Exception as e:
                    print(f"  └─ [OFFLINE BUFFERED] Firestore error: {e}")
                    save_offline_punch(punch_record)
            else:
                save_offline_punch(punch_record)

        # Re-enable device
        conn.enable_device()

        # Optional Memory Clear after verified sync
        if clear_memory and new_punches_count > 0:
            print(f"[DEVICE] ⚠️ Clearing internal log memory for {name}...")
            conn.clear_attendance()

        print(f"[DEVICE] Finished {name}: {new_punches_count} new punches synced.")

    except Exception as e:
        print(f"[DEVICE] ❌ Could not connect or sync {name} ({ip}): {e}")
        print("  └─ Isolated error: Other devices will continue syncing.")
    finally:
        if conn:
            try:
                conn.disconnect()
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser(description="ZKTeco LAN Service to Cloud Firestore Sync")
    parser.add_argument("--config", default="config.json", help="Path to config.json file")
    parser.add_argument("--once", action="store_true", help="Run sync once and exit (no continuous loop)")
    args = parser.parse_args()

    print("==========================================================")
    print("      ZKTeco LAN Standalone Service to Firestore Sync     ")
    print("==========================================================")

    config = load_config(args.config)
    creds_path = config.get("firebase_credentials_path", "serviceAccountKey.json")
    interval = config.get("sync_interval_seconds", 15)
    clear_memory = config.get("clear_memory_after_sync", False)

    db = init_firebase(creds_path)
    synced_keys = load_synced_keys()

    try:
        while True:
            # 1. Flush offline buffer if Firestore is available
            flush_offline_buffer(db)

            # 2. Iterate through all registered ZKTeco scanners
            devices = config.get("devices", [])
            for dev in devices:
                fetch_and_sync_device(dev, db, synced_keys, clear_memory=clear_memory)

            # Save state
            save_synced_keys(synced_keys)

            if args.once:
                print("\n[INFO] Single run completed. Exiting.")
                break

            print(f"\n[SLEEP] Waiting {interval} seconds until next sync cycle...")
            time.sleep(interval)

    except KeyboardInterrupt:
        print("\n[INFO] Service stopped by user.")
        save_synced_keys(synced_keys)
        sys.exit(0)


if __name__ == "__main__":
    main()
