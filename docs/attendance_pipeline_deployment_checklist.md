# Biometric Attendance Pipeline Deployment Checklist

This checklist must be followed when setting up or auditing the ZKTeco biometric attendance pipeline across GMWF branches.

---

## 1. Designated Attendance Server PC (Per Branch)

- [ ] **Single Active Poller**: Exactly **one** designated Server PC per branch must run the Server Dashboard.
- [ ] **Attendance Server Role**: The Server Dashboard "Start Server" action sets `is_attendance_server = true` in `app_settings`.
- [ ] **Client Instances Suppressed**: Client machines (receptionist, doctor, dispensary, admin laptops) must **not** have the attendance server role active. On client machines, active UDP polling is automatically suppressed to prevent port/polling collisions, while passive listeners (ADMS HTTP 8088 / UDP 4370) remain available.

---

## 2. Hardware Device Registration

- [ ] **Registered in Biometric Device Manager**: Every physical ZKTeco device on the LAN must be registered in the app's Biometric Device Manager (`biometricDevicesBox`) with:
  - Correct LAN IP (e.g. `192.168.1.150`)
  - Port (`4370`)
  - Target branch ID (e.g. `gujrat`, `sialkot`, `karachi`)
  - Physical building location (e.g. `Office`, `Dispensary`, `Madrassa`, `School`)
- [ ] **Unregistered Device Safety**: If a punch originates from an unregistered or unmapped device IP/branch, the system automatically flags it as cross-branch requiring HQ Manager approval rather than silently trusting it.

---

## 3. Polling Ownership & Python Daemon Coordination

- [ ] **Single Polling Owner**: For every physical device, ensure only **one** process (Dart app OR Python daemon) actively pulls attendance logs:
  - If Python (`scripts/zkteco_sync_service.py`) is used for a device, configure `"branch": "<branch_id>"` in `config.json` so Firestore document IDs are branch-namespaced (`{branch}_{ip}_{pin}_{epoch}`).
  - In the Flutter app's device configuration, set the device's `pollingOwner` to `'python'`. The Flutter app will skip active polling for that device to avoid dual-connection contention.
  - If the Flutter Server PC is polling the device directly, leave `pollingOwner` as `'dart'` (or unset) and do **not** run the Python daemon against that device IP.

---

## 4. PIN Mapping & Unmapped Punches

- [ ] **Unique Biometric PINs**: Every active employee, teacher, or student must have a unique numeric PIN assigned in the app.
- [ ] **Unmapped Punch Review**: Unmapped scans (where a fingerprint/PIN is scanned on a device before being registered in the app) are stored in `LocalStorageService.unmappedPunchesBox` and displayed in the Attendance Tab banner for 1-click administrative assignment.
- [ ] **Cross-Branch Punch Review**: Punches from employees at non-home branches are queued in `LocalStorageService.crossBranchPunchesBox` for HQ approval.

---

## 5. Attendance Firestore Schema Standardization

All attendance records are synchronized to the canonical Firestore path:
```
branches/{branchId}/employee_attendance/{dateKey}/records/{employeeId}
```
where:
- `{branchId}`: lowercase branch code (e.g. `gujrat`, `sialkot`, `karachi`)
- `{dateKey}`: `YYYY-MM-DD` date string
- `{employeeId}`: unique staff/student identifier
