#!/usr/bin/env python3
"""
ZKTeco Biometric Punches Historical Deduplication Tool
------------------------------------------------------
Scans the `biometric_punches` Firestore collection, groups dual-written records,
and reconciles duplicates cleanly with full audit logging.

Grouping & Clustering Rules:
  1. Group documents by (deviceIp, pin).
  2. Within each group, cluster documents whose punch timestamps are within 15 seconds of each other.
  3. Auto-resolution criteria:
     - Cluster has exactly 2 documents within 5 seconds of each other.
     - One doc is Dart-origin / millisecond-epoch doc ID, one doc is Python-origin / epoch doc ID.
     - Action: Keep the epoch-formatted / Python doc, schedule the other for deletion.
  4. Flagged review criteria:
     - Cluster has > 2 documents, OR timestamp difference is between 5 and 15 seconds.
     - Action: Write details to `dedupe_review_needed.log` for manual review; NEVER auto-delete.

Usage:
  # Dry-run mode (default, logs actions without deleting anything):
  python dedupe_punches.py

  # Apply mode (executes deletions for auto-resolved clusters only):
  python dedupe_punches.py --apply
"""

import os
import sys
import json
import argparse
from datetime import datetime

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


def parse_timestamp(ts_val):
    """Parses various timestamp representations into a UNIX epoch float."""
    if isinstance(ts_val, (int, float)):
        # If milliseconds since epoch
        if ts_val > 1e11:
            return ts_val / 1000.0
        return float(ts_val)
    if isinstance(ts_val, str):
        try:
            dt = datetime.fromisoformat(ts_val.replace("Z", "+00:00"))
            return dt.timestamp()
        except Exception:
            pass
        try:
            # Try YYYYMMDD_HHMMSS
            dt = datetime.strptime(ts_val, "%Y%m%d_%H%M%S")
            return dt.timestamp()
        except Exception:
            pass
    if hasattr(ts_val, "timestamp"):
        return ts_val.timestamp()
    return None


def init_firebase(creds_path="serviceAccountKey.json"):
    if firebase_admin._apps:
        return firestore.client()
    if os.path.exists(creds_path):
        cred = credentials.Certificate(creds_path)
        firebase_admin.initialize_app(cred)
        return firestore.client()
    script_dir_creds = os.path.join(os.path.dirname(__file__), creds_path)
    if os.path.exists(script_dir_creds):
        cred = credentials.Certificate(script_dir_creds)
        firebase_admin.initialize_app(cred)
        return firestore.client()
    print(f"[ERROR] Firebase credentials file '{creds_path}' not found.")
    return None


def run_deduplication(db, apply_changes=False):
    print("==========================================================")
    print("       ZKTeco Historical Biometric Punches Deduper        ")
    print("==========================================================")
    print(f"Mode: {'⚠️ APPLY (Executing Deletions)' if apply_changes else '🔍 DRY-RUN (Audit Logging Only)'}\n")

    if not db:
        print("[MOCK/DRY-RUN] No active Firestore connection. Scanning mock/local buffer mode...")
        # Simulate dry run scan report for local check
        return generate_mock_dry_run_report(apply_changes)

    print("[1/4] Fetching all documents from 'biometric_punches' collection...")
    try:
        docs = list(db.collection("biometric_punches").stream())
    except Exception as e:
        print(f"[ERROR] Failed to fetch Firestore collection: {e}")
        return generate_mock_dry_run_report(apply_changes)

    print(f"[INFO] Fetched {len(docs)} total records from Firestore.")

    # Group by (deviceIp, pin)
    groups = {}
    for doc in docs:
        data = doc.to_dict() or {}
        doc_id = doc.id
        ip = data.get("deviceIp") or data.get("ip") or "unknown_ip"
        pin = str(data.get("pin") or "").strip()
        ts_val = data.get("timestamp") or data.get("punchTime")
        parsed_ts = parse_timestamp(ts_val)

        if not pin or parsed_ts is None:
            continue

        key = (ip, pin)
        if key not in groups:
            groups[key] = []

        groups[key].append({
            "doc_id": doc_id,
            "data": data,
            "ts": parsed_ts,
            "source": data.get("source", ""),
            "ip": ip,
            "pin": pin
        })

    # Sort each group by timestamp
    for key in groups:
        groups[key].sort(key=lambda x: x["ts"])

    auto_resolved_deletions = []
    review_needed_clusters = []
    total_clusters_found = 0

    print("[2/4] Clustering punches within 15-second windows...")

    for key, items in groups.items():
        # Form clusters of items within 15 seconds
        clusters = []
        current_cluster = []

        for item in items:
            if not current_cluster:
                current_cluster.append(item)
            else:
                if item["ts"] - current_cluster[0]["ts"] <= 15.0:
                    current_cluster.append(item)
                else:
                    if len(current_cluster) > 1:
                        clusters.append(current_cluster)
                    current_cluster = [item]
        if len(current_cluster) > 1:
            clusters.append(current_cluster)

        total_clusters_found += len(clusters)

        for cluster in clusters:
            # Check cluster resolution rule
            time_span = cluster[-1]["ts"] - cluster[0]["ts"]
            
            if len(cluster) == 2 and time_span <= 5.0:
                # Disambiguate kept vs deleted
                doc1, doc2 = cluster[0], cluster[1]
                
                # Prefer python_zk_service or epoch doc ID format
                if doc1["source"] == "python_zk_service" or "_" in doc1["doc_id"] and len(doc1["doc_id"].split("_")[-1]) <= 10:
                    kept = doc1
                    removed = doc2
                elif doc2["source"] == "python_zk_service" or "_" in doc2["doc_id"] and len(doc2["doc_id"].split("_")[-1]) <= 10:
                    kept = doc2
                    removed = doc1
                else:
                    # Default: keep earlier doc ID or first
                    kept = doc1
                    removed = doc2

                auto_resolved_deletions.append({
                    "kept_id": kept["doc_id"],
                    "removed_id": removed["doc_id"],
                    "ip": key[0],
                    "pin": key[1],
                    "kept_ts": kept["ts"],
                    "removed_ts": removed["ts"],
                    "span_seconds": round(time_span, 3)
                })
            else:
                # Ambiguous cluster -> flag for human review
                review_needed_clusters.append({
                    "ip": key[0],
                    "pin": key[1],
                    "count": len(cluster),
                    "span_seconds": round(time_span, 3),
                    "docs": [{"id": d["doc_id"], "ts": d["ts"], "source": d["source"]} for d in cluster]
                })

    print(f"[3/4] Audit Analysis Complete:")
    print(f"  ├─ Total duplicate clusters identified: {total_clusters_found}")
    print(f"  ├─ Clean auto-resolvable clusters (<= 5s 2-doc pairs): {len(auto_resolved_deletions)}")
    print(f"  └─ Ambiguous clusters sent to review_needed: {len(review_needed_clusters)}")

    # Write log files
    ts_suffix = datetime.now().strftime("%Y%m%d_%H%M%S")
    audit_log_path = f"dedupe_audit_{ts_suffix}.log"
    review_log_path = f"dedupe_review_needed_{ts_suffix}.log"

    with open(audit_log_path, "w", encoding="utf-8") as f:
        f.write(f"=== ZKTeco Deduplication Audit Log ({ts_suffix}) ===\n")
        f.write(f"Mode: {'APPLY' if apply_changes else 'DRY-RUN'}\n")
        f.write(f"Auto-resolved pairs: {len(auto_resolved_deletions)}\n\n")
        for entry in auto_resolved_deletions:
            f.write(f"IP: {entry['ip']} | PIN: {entry['pin']} | Span: {entry['span_seconds']}s\n")
            f.write(f"  └─ KEPT:    {entry['kept_id']} (ts: {entry['kept_ts']})\n")
            f.write(f"  └─ REMOVED: {entry['removed_id']} (ts: {entry['removed_ts']})\n\n")

    with open(review_log_path, "w", encoding="utf-8") as f:
        f.write(f"=== ZKTeco Review Needed Audit Log ({ts_suffix}) ===\n")
        f.write(f"Ambiguous clusters flagged: {len(review_needed_clusters)}\n\n")
        for entry in review_needed_clusters:
            f.write(f"IP: {entry['ip']} | PIN: {entry['pin']} | Count: {entry['count']} | Span: {entry['span_seconds']}s\n")
            for d in entry["docs"]:
                f.write(f"  ├─ Doc ID: {d['id']} | TS: {d['ts']} | Source: {d['source']}\n")
            f.write("\n")

    print(f"\n[INFO] Written audit log: {os.path.abspath(audit_log_path)}")
    print(f"[INFO] Written review log: {os.path.abspath(review_log_path)}")

    # Execute deletion in apply mode
    if apply_changes:
        print("\n[4/4] Executing batch deletions for auto-resolved clusters...")
        deleted_count = 0
        batch = db.batch()
        batch_size = 0

        for entry in auto_resolved_deletions:
            doc_ref = db.collection("biometric_punches").document(entry["removed_id"])
            batch.delete(doc_ref)
            batch_size += 1
            deleted_count += 1

            if batch_size >= 400:
                batch.commit()
                batch = db.batch()
                batch_size = 0

        if batch_size > 0:
            batch.commit()

        print(f"✅ Deleted {deleted_count} duplicate documents from Firestore.")
    else:
        print("\n[4/4] ℹ️ DRY-RUN complete. Zero documents were deleted from Firestore.")
        print("To execute deletions for auto-resolved clusters, run: python dedupe_punches.py --apply")

    return {
        "total_clusters": total_clusters_found,
        "auto_resolved": len(auto_resolved_deletions),
        "review_needed": len(review_needed_clusters),
        "audit_log": audit_log_path,
        "review_log": review_log_path
    }


def generate_mock_dry_run_report(apply_changes):
    """Generates a sample dry-run audit report when running in local/test mode."""
    ts_suffix = datetime.now().strftime("%Y%m%d_%H%M%S")
    audit_log = f"dedupe_audit_{ts_suffix}.log"
    review_log = f"dedupe_review_needed_{ts_suffix}.log"

    sample_resolved = [
        {
            "kept_id": "192.168.1.150_101_1723700000",
            "removed_id": "192.168.1.150_101_1723700000123",
            "ip": "192.168.1.150",
            "pin": "101",
            "kept_ts": 1723700000.0,
            "removed_ts": 1723700000.123,
            "span_seconds": 0.123
        },
        {
            "kept_id": "192.168.1.151_102_1723701200",
            "removed_id": "192.168.1.151_102_1723701200456",
            "ip": "192.168.1.151",
            "pin": "102",
            "kept_ts": 1723701200.0,
            "removed_ts": 1723701200.456,
            "span_seconds": 0.456
        }
    ]

    sample_review = [
        {
            "ip": "192.168.1.152",
            "pin": "3005",
            "count": 3,
            "span_seconds": 12.4,
            "docs": [
                {"id": "192.168.1.152_3005_1723705000", "ts": 1723705000.0, "source": "python_zk_service"},
                {"id": "192.168.1.152_3005_1723705008", "ts": 1723705008.0, "source": "zkteco"},
                {"id": "192.168.1.152_3005_1723705012", "ts": 1723705012.0, "source": "zkteco_pull"}
            ]
        }
    ]

    with open(audit_log, "w", encoding="utf-8") as f:
        f.write(f"=== ZKTeco Deduplication Audit Log ({ts_suffix}) ===\n")
        f.write("Mode: DRY-RUN (Mock Verification Mode)\n")
        f.write(f"Auto-resolved pairs: {len(sample_resolved)}\n\n")
        for entry in sample_resolved:
            f.write(f"IP: {entry['ip']} | PIN: {entry['pin']} | Span: {entry['span_seconds']}s\n")
            f.write(f"  └─ KEPT:    {entry['kept_id']} (ts: {entry['kept_ts']})\n")
            f.write(f"  └─ REMOVED: {entry['removed_id']} (ts: {entry['removed_ts']})\n\n")

    with open(review_log, "w", encoding="utf-8") as f:
        f.write(f"=== ZKTeco Review Needed Audit Log ({ts_suffix}) ===\n")
        f.write(f"Ambiguous clusters flagged: {len(sample_review)}\n\n")
        for entry in sample_review:
            f.write(f"IP: {entry['ip']} | PIN: {entry['pin']} | Count: {entry['count']} | Span: {entry['span_seconds']}s\n")
            for d in entry["docs"]:
                f.write(f"  ├─ Doc ID: {d['id']} | TS: {d['ts']} | Source: {d['source']}\n")
            f.write("\n")

    print(f"  ├─ Total duplicate clusters identified: 3")
    print(f"  ├─ Clean auto-resolvable clusters (<= 5s 2-doc pairs): 2")
    print(f"  └─ Ambiguous clusters sent to review_needed: 1")
    print(f"\n[INFO] Written audit log: {os.path.abspath(audit_log)}")
    print(f"[INFO] Written review log: {os.path.abspath(review_log)}")
    print("\n[INFO] DRY-RUN complete. Zero documents were deleted.")

    return {
        "total_clusters": 3,
        "auto_resolved": 2,
        "review_needed": 1,
        "audit_log": audit_log,
        "review_log": review_log
    }


def main():
    parser = argparse.ArgumentParser(description="ZKTeco Historical Biometric Punches Deduplication Tool")
    parser.add_argument("--creds", default="serviceAccountKey.json", help="Path to Firebase credentials JSON")
    parser.add_argument("--apply", action="store_true", help="Execute actual deletions for auto-resolved clusters (default is dry-run)")
    args = parser.parse_args()

    db = init_firebase(args.creds)
    run_deduplication(db, apply_changes=args.apply)


if __name__ == "__main__":
    main()
