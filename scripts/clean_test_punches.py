#!/usr/bin/env python3
"""
ZKTeco Biometric Punches Cleanup Script
---------------------------------------
Wipes the historical test punches (PIN 1, 157, 1111) from the `biometric_punches` 
collection in Cloud Firestore, and resets `synced_keys.json` and `pending_punches.json`
so the system starts completely fresh with real live employee punches.
"""

import os
import sys
import json

# Configure Windows stdout for UTF-8 encoding
if sys.platform == "win32" and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

def _ensure_package(module_name, pip_name=None):
    pip_name = pip_name or module_name
    try:
        __import__(module_name)
    except ImportError:
        import subprocess
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", pip_name])
        except Exception as e:
            print(f"[ERROR] Failed to install '{pip_name}': {e}")

_ensure_package("firebase_admin", "firebase-admin")
import firebase_admin
from firebase_admin import credentials, firestore

def init_firebase(creds_path="serviceAccountKey.json"):
    if firebase_admin._apps:
        try:
            return firestore.client()
        except Exception:
            return None
    if os.path.exists(creds_path):
        try:
            cred = credentials.Certificate(creds_path)
            firebase_admin.initialize_app(cred)
            print(f"[FIREBASE] Initialized with credentials: {creds_path}")
            return firestore.client()
        except Exception as e:
            print(f"[ERROR] Error loading {creds_path}: {e}")
    else:
        print(f"[ERROR] '{creds_path}' not found.")
    return None

def wipe_test_punches():
    db = init_firebase("serviceAccountKey.json")
    if not db:
        print("[ABORT] Could not connect to Firestore.")
        return

    print("[CLEANUP] Fetching documents from 'biometric_punches' collection...")
    punches_ref = db.collection("biometric_punches")
    docs = list(punches_ref.stream())

    print(f"[CLEANUP] Found {len(docs)} documents in 'biometric_punches'. Deleting...")
    deleted_count = 0
    batch = db.batch()
    batch_count = 0

    for doc in docs:
        batch.delete(doc.reference)
        batch_count += 1
        deleted_count += 1
        if batch_count >= 400:
            batch.commit()
            batch = db.batch()
            batch_count = 0

    if batch_count > 0:
        batch.commit()

    print(f"[CLEANUP] ✅ Successfully deleted {deleted_count} test documents from 'biometric_punches'.")

    # Reset synced_keys.json and pending_punches.json
    with open("synced_keys.json", "w") as f:
        json.dump([], f)
    print("[CLEANUP] ✅ Reset 'synced_keys.json' to empty state.")

    with open("pending_punches.json", "w") as f:
        json.dump([], f)
    print("[CLEANUP] ✅ Reset 'pending_punches.json' to empty state.")

if __name__ == "__main__":
    wipe_test_punches()
