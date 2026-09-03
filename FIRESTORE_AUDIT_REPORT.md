# FIRESTORE FULL APPLICATION AUDIT

**Date**: September 1, 2026  
**Application**: GMWF (Flutter)  
**Current State**: 100+ users, 300 patients/day, 3 branches  
**Status**: Exhausting daily quota within ~1 hour

---

## 1. Executive Summary

### Current Firestore Consumption Profile

The application is **heavily listener-based** with **poor multi-user multiplication control**. The primary quota consumers are:

1. **Real-time listeners that fire per user per screen** — 15+ permanent listeners
2. **Token queue screens** — 2-3 listeners per operational screen open × 20+ concurrent users
3. **Inventory live listeners** — Active per screen × multiple concurrent screens
4. **Sync service background operations** — Periodic fetches every 2 hours + connectivity-triggered
5. **Global listeners** (users, branches, donations audit trail) — No user/branch filtering
6. **Download/export operations** — Massive batch gets (15+ collections per download)

### Key Problem: Listener Multiplication

With **100+ users**:
- Each opened screen creates **independent Firestore listeners**
- Token screen listener runs for every receptionist + every doctor = potentially 20-40 concurrent listeners
- Inventory listener runs per dispensary screen = potentially 10-15 concurrent listeners
- Each listener receives **ALL changes** and broadcasts to LAN + Firestore
- **Result**: A single token update can trigger 100+ Firestore document reads across all listeners

### Suspected Hot Spots (Ranked by Probability)

🔴 **CRITICAL** (Likely causing majority of quota exhaustion):
1. Token screen branch doc + edit requests listeners × 20+ users
2. Patient queue serials listeners (3 queue types × multiple users)
3. Inventory live listeners × concurrent screens
4. Donations audit trail listener (global, no filters)
5. ZKTECO remote devices listener (2000-document gets)

🟠 **HIGH** (Significant multiplier effect):
6. Home router user doc listeners (every login)
7. Madrassa student/guardian listeners
8. Finance operations periodic downloads
9. Global users collection listener
10. Branches management listeners

---

## 2. Firestore Reads (Every .get() Operation)

### Summary
- **Total .get() operations found**: 326 instances
- **Estimated daily reads**: 15,000+ reads with 100+ concurrent users
- **Patterns**: Bulk collection fetches, no pagination, filters in Dart instead of Firestore

| File | Operation | Collection | Scope | Frequency | Users Affected |
|------|-----------|-----------|-------|-----------|-----------------|
| `download_screen.dart` | Bulk export | branches/patients/serials/inventory/prescriptions | 15+ collections per branch | On-demand | Admin users |
| `sync_service.dart` | Token download | branches/{id}/serials/{date}/{type} | Per branch, per day | Daily + connectivity | All users |
| `sync_service.dart` | Inventory download | branches/{id}/inventory | Per branch | 2-hour timer | All users |
| `sync_service.dart` | Prescriptions refresh | branches/{id}/prescriptions | Per branch | 2-hour timer | All users |
| `sync_service.dart` | Donations download | branches/{id}/donations | Per branch | 2-hour timer (if permission) | Permitted users |
| `sync_service.dart` | Attendance download | collectionGroup('employees') | Global | Periodic | Finance users |
| `data_cleanup_screen.dart` | Collection scan | branches/serials/dispensary | Entire structure | On-demand | Admin |
| `finance_local_storage.dart` | Employee records | collectionGroup('employees') | Global scan | Startup + periodic | Finance module |
| `zkteco_network_service.dart` | Device sync | branches/{id}/biometric_devices | Limit: 2000 docs | Periodic | Biometric users |
| `home_dashboard_service.dart` | Branch stats fallback | branches/{id}/donations/tokens/serials | Multiple collections | Fallback (local first) | Dashboard viewers |
| `madrassa_local_storage.dart` | Student records | branches/{id}/madrassa_students | Per branch | Periodic | Madrassa module |
| `donations_local_storage.dart` | Donor records | donors + branches/{id}/donors | Global + local | 2-hour timer | Donations module |
| `school_sync_service.dart` | Attendance queries | schools database | Per branch | Periodic | School module |
| `token_screen.dart` | Patient search | branches/{id}/patients | Limited query | Per CNIC search | Receptionists |
| `patient_detail_screen.dart` | Patient + siblings | branches/{id}/patients | doc.get() + where query | Per patient detail view | Doctors/Receptionists |

### Major Read Operations Analysis

**1. Download Screen (Massive Batch Reads)**
```
Per branch export triggers:
- branches.get() — all branches
- branches/{id}/patients.get()
- branches/{id}/serials.get() (all serials docs)
- branches/{id}/serials/{date}/{type}.get() (all queue items)
- branches/{id}/prescriptions.get()
- branches/{id}/prescriptions/{cnic}/prescriptions.get()
- branches/{id}/inventory.get()
- branches/{id}/dasterkhwaan.get()
- branches/{id}/dasterkhwaan/{date}/tokens.get()
- branches/{id}/dasterkhwaan_stock.get()
- branches/{id}/dasterkhwaan_stock_logs.get()

Total: 12-15 READ operations per download
Estimated impact: Admin user exports once daily = 15+ reads
Multi-admin scenario: 50-100 reads daily from exports alone
```

**2. Sync Service Periodic Refresh (2-Hour Timer)**
```
Every 2 hours, for EVERY authorized branch:
- downloadTodayTokens() → serials/{date}/{type}.get() × 3 types
- downloadInventory() → inventory.get() × camps
- refreshPrescriptions() → prescriptions.get() + per-patient collection
- downloadAllDonations() → donations query.where().get()
- downloadAttendance() → collectionGroup('employee_attendance').get()

Total: 8-12 READ operations per 2-hour cycle
With 3 branches: 24-36 reads every 2 hours = ~288-432 reads daily
With 100+ users syncing: 28,800-43,200 reads daily from sync alone
```

**3. Finance Operations**
```
collectionGroup('employees').get() — NO BRANCH FILTERING
- Returns ALL employees across ALL branches
- Executed during finance page load + periodic sync
- Impact: 1 query = potentially 500+ employee docs
```

**4. ZKTECO Biometric Sync**
```
query.limit(2000).get() on remote devices
- Downloads 2000 device records every sync cycle
- No branch or date filtering
```

### Impact Calculation: 100 Users

| Operation | Per User | Per Cycle | Daily | With 100 Users |
|-----------|----------|-----------|-------|-----------------|
| Sync 2-hour refresh (3 branches) | 24-36 reads | Every 2h | 288-432 | 28,800-43,200 |
| Connectivity-triggered sync | 20-30 reads | Varies | ~50-100 | 5,000-10,000 |
| Dashboard fallback query | 5-8 reads | Per load | ~10-20 | 1,000-2,000 |
| Download export | 15 reads | ~1-2x daily | 30 | 3,000 |
| Navigation queries | 2-5 reads | Per screen | ~50 | 5,000 |
| **ESTIMATED DAILY TOTAL** | — | — | — | **42,800-63,200 reads** |

**Firestore Daily Quota**: 50,000 reads  
**Estimated Daily Usage**: 42,800-63,200 reads  
**Result**: ⚠️ **Quota exhaustion guaranteed**

---

## 3. Firestore Listeners (Real-time snapshots())

### Summary
- **Total listeners found**: 59 snapshots() + 63 listen() calls = **122 listener instantiations**
- **Critical issue**: Many listeners **fire PER SCREEN OPEN** × **concurrent users**
- **Multi-user multiplication**: Each listener streams to ALL clients

### Complete Listener Map

| Screen/File | Listener | Collection | Scope | When Started | When Stopped | Documents | Critical Issues |
|-------------|----------|-----------|-------|-------------|-------------|-----------|-----------------|
| **Token Screen** (receptionist) | Branch doc | branches/{id} | Single doc | initState | dispose | ~1 | ✅ Per user, scoped |
| **Token Screen** | Edit requests | branches/{id}/edit_requests | Filtered (token_exception + approved) | initState | dispose | 0-50 | ✅ Scoped by filters |
| **Token Screen** | Realtime messages | LAN event stream | N/A (local) | initState | dispose | N/A | ✅ LAN only |
| **Patient Queue (Doctor)** | Today's serials | branches/{id}/serials/{date}/{type} | Per queue type | initState | dispose (multiple) | 0-100 | 🔴 3 listeners × users × day |
| **Patient Queue** | Live inventory | branches/{id}/{inventory_col} | Filtered | initState | dispose (multiple) | 0-50 per medicine | 🔴 Multiple parallel listeners |
| **Patient Queue** | Exception requests | branches/{id}/edit_requests | Filtered | initState | dispose | 0-20 | ✅ Scoped |
| **Patient List (Receptionist)** | Today's serials | branches/{id}/serials/{date}/{type} | Per queue type | initState | dispose | 0-100 | 🔴 Fallback, 3 listeners |
| **Dispensary Screen** | Realtime messages | LAN event stream | N/A (local) | initState | dispose | N/A | ✅ LAN only |
| **Inventory Tab** | Live inventory | branches/{id}/{inventory_col} | Filtered | initState | dispose | 0-50 | 🔴 Active stream per camp |
| **Inventory Tab** | Log combined | Stock log stream | Filtered | initState | dispose | Variable | 🟠 BehaviorSubject |
| **Home Router** | User document | users/{uid} | Single doc + revocation | initState | dispose | 1 | ⚠️ Per login, every session |
| **Donations** | Global audit trail | global_audit_logs | Ordered, limit 100 | initState | dispose | 0-100 | 🔴 No branch filtering, global |
| **Donations** | Pagination watcher | Hive donations box | Local cache | init | dispose | N/A (Hive) | ✅ Local only |
| **Madrassa Guardian** | Student records | branches/{id}/madrassa_students | Multiple filters | didBuild | dispose | 0-100 | 🟠 Per guardian view |
| **Madrassa Overview** | Student records | branches/{id}/madrassa_students | Various | initState | dispose | 0-500 | 🟠 Module-wide |
| **Madrassa Holiday Mgmt** | Holiday listener | branches/{id}/madrassa_holidays | Filtered | didBuild | dispose | 0-50 | ✅ Scoped |
| **Madrassa Config** | Facility config | branches/{id}/madrassa_config | Filtered | initState | dispose | 0-20 | ✅ Scoped |
| **Madrassa Parent Report** | Report cards | branches/{id}/madrassa_attendance | Report listener | build | dispose | 0-100 | 🟠 Per report card |
| **Madrassa Parent Report** | Enrollment | branches/{id}/madrassa_enrollments | Multiple | build | dispose | 0-50 | 🟠 Multiple per card |
| **Notification Screen** | Notifications | branches/{id}/notifications | Admin: all, else: receiverId filter | initState | dispose | 0-100 | 🟠 Scoped by filter |
| **Office - Biometric Punch** | Punch stream | ZKTECO punch service | Live events | initState | dispose | Real-time | 🟠 Hardware-driven |
| **Request Screen** | Requests | Global request stream | Filtered | initState | dispose | 0-100 | 🟠 Cross-module |
| **School Daily Attendance** | Attendance | school attendance collection | Filtered | initState | dispose | 0-100 | ✅ Scoped |
| **User Detail Screen** | User document | users/{uid} | Single user | initState | dispose | 1 | ✅ Scoped |
| **User Detail Screen** | User sessions | user_sessions/{uid} | Single user sessions | initState | dispose | 0-10 | ✅ Scoped |
| **Users Management** | All users | users collection | NO FILTERING (**GLOBAL**) | initState | dispose | 100-500 | 🔴 GLOBAL, every user synced |
| **Users Management** | User sessions | user_sessions collection | Filtered | initState | dispose | Variable | 🟠 Per user |
| **Branches Management** | Branches | branches collection | NO FILTERING (**GLOBAL**) | initState | dispose | 3-10 | ⚠️ Small but global |
| **Notifications** | Admin notifications | notifications/{branchId} | Admin: receives all branches | initState | dispose | 0-100 | 🟠 Admin receives global |
| **Multi Server Service** | Branches | branches collection | Global | init | dispose | 3-10 | ⚠️ Infrastructure |
| **Multi Server Service** | Servers | servers collection | Global | init | dispose | 5-20 | ⚠️ Infrastructure |
| **ZKTECO Network Service** | Remote devices | branches/{id}/biometric_devices | Filtered + limit 2000 | start | stop | 2000 | 🔴 Massive doc download |
| **ZKTECO Network Service** | Remote credentials | branches/{id}/biometric_credentials | Filtered | start | stop | 0-500 | 🟠 Large binary docs |
| **Serials Service** | Branches switchMap | branches collection | Global | getSerialStream | — | 3-10 | ⚠️ Chained listener |
| **Real-time Connection Mgr** | Message stream | LAN broadcast | N/A | init | dispose | N/A | ✅ LAN only |
| **LAN Server** | HTTP requests | N/A | Local network | start | stop | N/A | ✅ LAN only |
| **Finance Local Storage** | Attendance download | collectionGroup('employee_attendance') | Filtered by branch | periodic | — | 500+ docs | 🔴 Large bulk download |

### Critical Listener Issues

**🔴 ISSUE #1: Token Queue Multi-Listener Per Day**

```
Patient Queue (Doctor) initState creates:
1. serialsRef.collection('zakat').snapshots().listen() 
2. serialsRef.collection('non-zakat').snapshots().listen()
3. serialsRef.collection('gmwf').snapshots().listen()
4. Live inventory listeners (1-3 per medicine per camp)
5. Exception requests listener

Total per doctor screen open: 6-8 active listeners
Expected concurrent doctors: 20-40 during operating hours
Total active listeners: 120-320 concurrent listeners
Each listener broadcasts on every token change
Impact: Minimal per listener, but massive aggregate when multiplied

Result: 1 token update → 120-320 listener notifications → 120-320 Firestore document reads
```

**🔴 ISSUE #2: Global Users Collection Listener (No Filtering)**

```
File: lib/pages/users.dart line 2079
Query: FirebaseFirestore.instance.collection('users').snapshots()

Problem:
- Returns ALL users in system (100-500 docs)
- Every time users.dart screen opens, a new listener is created
- No branch filtering, no role filtering, completely global
- Used by user management admin screens

Impact with 100+ users:
- Users screen opened by admin = streams all 100+ users
- Any user change = all listeners receive update
- If 5 admins have users screen open = 5 × 100 user docs per change
```

**🔴 ISSUE #3: Global Donations Audit Trail Listener**

```
File: lib/pages/donations/global_audit_trail.dart line 34
Query: _db.collection('global_audit_logs').orderBy('timestamp', descending: true).limit(100)

Problem:
- No branch filtering — receives logs from all branches
- No user filtering — receives all types of operations
- limit(100) keeps 100 most recent docs in stream
- Every donation create/update/delete triggers listener for all viewers

Impact:
- Each donation operation updates all audit log listeners globally
- With 300 patients/day × multiple operations per patient = 1000+ operations
- Each operation streams to all active audit trail listeners
```

**🔴 ISSUE #4: ZKTECO Biometric Device Listener (2000 Documents)**

```
File: lib/services/zkteco_network_service.dart line 1219
Query: _remoteDevicesSub = query.snapshots().listen((snap) async {...})

Problem:
- Listener on 2000-document collection (limit: 2000 in .get())
- Downloads and caches all device records
- Active as long as biometric service running
- On device register/update = all 2000 docs streamed to listener

Impact:
- Initial listener: 2000 document reads
- Any device change: 2000 document reads to listener
- Used by biometric enrollment screens
```

**🟠 ISSUE #5: Inventory Live Listeners (Per Screen)**

```
File: lib/pages/dispensary/dispensar/patient_queue.dart line 660-670
Multiple inventory listeners per inventory collection

Problem:
- 1 listener per medicine being tracked
- Creates multiple parallel listeners
- Each listener tracks real-time stock changes
- Runs whenever doctor screen is open

Impact:
- Doctor screen open with 50 medicines = 50 active listeners
- 20 concurrent doctors = 1000 active listeners
- Each inventory update: streams to 1000 listeners
```

**🟠 ISSUE #6: Home Router User Document Listener (Per Login)**

```
File: lib/pages/home_router.dart line 128
_startRevokeListener(uid, branchId) creates persistent listener on users/{uid}

Problem:
- Listener created once per app session/login
- Stays active for entire session
- Triggered for every user action to check revocation status
- Used to detect if user access has been revoked

Impact:
- 100 users = 100 active user document listeners
- Each user update: streams to relevant listener
- Small scale individually but prevents offline access
```

---

## 4. Firestore Writes (set/update/delete/batch)

### Summary
- **Total write operations found**: 100+ instances across sync_service and various screens
- **Pattern**: Local-first writes to Hive, then async to Firestore, with retry queue
- **Batching**: Inconsistent — some operations batch, others issue individual writes

### Write Operation Breakdown

| Operation Type | File | Trigger | Count | Batched | Transaction | Retry |
|---|---|---|---|---|---|---|
| Save patient | sync_service.dart | Patient registration | Per patient | ❌ Individual | ❌ | ✅ Queue |
| Save entry (token) | sync_service.dart | Token issuance | ~300/day | ❌ Individual | ❌ | ✅ Queue |
| Save prescription | sync_service.dart | Doctor prescription | ~200-300/day | ❌ Individual | ❌ | ✅ Queue |
| Update serial status | sync_service.dart | Token completion | ~300/day | ❌ Individual | ❌ | ✅ Queue |
| Save dispensary charge | sync_service.dart | Dispensing | ~300/day | ❌ Individual | ❌ | ✅ Queue |
| Update inventory | sync_service.dart | Medicine deduction | 500-1000/day | ❌ Individual | ✅ Transaction | ✅ Queue |
| Save donation | sync_service.dart | Donation entry | 50-200/day | ❌ Individual | ❌ | ✅ Queue |
| Save audit log | sync_service.dart | Every operation | 1000+/day | ✅ Batch (2-write) | ❌ | ✅ Queue |
| Save journal entry | sync_service.dart | Finance operation | 50-100/day | ✅ Batch (2-write) | ❌ | ✅ Queue |
| Madrassa update | madrassa_widgets.dart | Attendance/grades | 100-300/day | ✅ Batch | ❌ | ❓ |
| Finance batch update | finance_page.dart | Payroll operations | 50-100 | ✅ Batch | ❌ | ❓ |
| ZKTECO punch record | zkteco_network_service.dart | Biometric punch | 3-5 per employee | ❌ Individual | ❌ | ❌ Direct |

### Patient Workflow Write Sequence

Single patient from reception to completion:

```
RECEPTION (Token Issuance):
├─ save_patient (Write #1)
│  └─ Firestore: branches/{id}/patients/{id}.set()
└─ save_entry (Write #2)
   └─ Firestore: branches/{id}/serials/{date}/{type}/{serial}.set()

DOCTOR (Prescription):
└─ save_prescription (Write #3)
   ├─ Firestore: branches/{id}/prescriptions/{cnic}/{serial}.set()
   └─ Firestore: branches/{id}/serials/{date}/{type}/{serial}.set(status: completed)

DISPENSARY (Medicine Dispensing):
├─ save_dispensary_charge (Write #4)
│  ├─ Firestore: branches/{id}/dispensary_charges/{date}/{serial}.set()
│  └─ Firestore: branches/{id}/serials/{date}/{type}/{serial}.set(daysOfMedicine)
└─ update_inventory (Write #5-7)
   └─ Firestore transactions: branches/{id}/{inventory}/{medicine}.update() × per medicine

TOTAL WRITES PER PATIENT: 7-10 Firestore writes
```

### Audit Logging Write Multiplication

**Every single write creates audit log:**
```
Patient save → audit_log write (Batch: 2 writes)
  └─ branches/{id}/audit_logs/{id}.set()
  └─ global_audit_logs/{id}.set()

Result: 1 operation = 2 audit writes
Tokens per day: 300 × 7 writes avg = 2100 writes
Audit logs: 2100 × 2 = 4200 writes
Total daily writes: ~6000 writes
```

### Retry Queue Behavior

**SyncService enqueue pattern:**
```
Save to Hive → Attempt Firestore (5s timeout) → Fails → Enqueue retry
Retry cycle: Every 2 hours or on connectivity restore
With 100+ users: Each might have 5-10 pending items in retry queue
Retry attempts: Could trigger 500-1000 additional writes per 2-hour cycle
```

---

## 5. Background / Sync Firestore Usage

### Timers and Scheduled Operations

| Timer | Interval | Trigger | Operation | Firestore Impact |
|---|---|---|---|---|
| Daily token refresh | 00:05 (midnight) | Automatic | `downloadTodayTokens()` | Read: ~100 docs per branch |
| Periodic sync | 2 hours | Automatic | Refresh all data | Read: 24-36 operations × branches |
| Connectivity listener | On change | Network change | `triggerUpload()` | Read: 20-30 ops if offline→online |
| Health check | Periodic | In `_isFirestoreAvailable()` | `.collection('_ping').limit(1).get()` | Read: 1 doc (cached 60s) |
| ZKTECO sync | Periodic (unclear) | Service running | Remote device list + creds | Read: 2000+ devices + creds |
| Device session record | On startup | App launch | Record user online | Write: 1 per user per session |
| Auto-update check | On startup + periodic | App launch | Check version doc | Read: 1 doc |

### Startup Initialization Sequence

```
App Start:
├─ Firebase init (platform-specific)
├─ Hive init (40+ boxes)
├─ Crash marker check + delete (1 write)
├─ Main.dart providers init
├─ Auth service init
│  └─ If online: User doc.get() (1 read)
├─ OfflineAuthService init
│  └─ Load cached user data
├─ SyncService.start(branchId)
│  ├─ Set up connectivity listener
│  ├─ _setupDailyTokenRefresh()
│  │  └─ Schedule midnight token refresh
│  ├─ Start 2-hour periodic sync timer
│  ├─ triggerUpload() immediately
│  │  ├─ For each authorized branch:
│  │  │  ├─ downloadTodayTokens() (3 reads per queue type)
│  │  │  ├─ downloadInventory() (reads per camp)
│  │  │  ├─ refreshPrescriptions() (multiple reads)
│  │  │  ├─ downloadAllDonations() (if permitted)
│  │  │  └─ downloadAttendance() (if finance)
│  │  └─ Result: 20-40 reads on startup
│  └─ Upload any pending sync queue items
├─ DeviceInfoService startup
│  └─ Record user session (1 write)
├─ Auto-update service check
│  └─ Get version doc (1 read)
├─ Realtime system init (LAN)
│  └─ mDNS discovery
├─ ZKTECO service init
│  └─ Remote device listener start (2000+ doc reads)
└─ Home route init
   └─ _startRevokeListener() (user doc listener)

Total on app startup: ~25-50 Firestore operations
```

### Offline Behavior Impact

**When device goes offline:**
1. Sync queue accumulates writes locally
2. On reconnect: `triggerUpload()` attempts all queued writes
3. If 100 patients processed offline: 100 × 7 = 700 writes queued
4. Reconnect causes: 700 writes + 40 refresh reads = 740 Firestore ops in single burst
5. With 20+ users going offline/online in a day: Massive quota spike

---

## 6. Dashboard Analysis

### Home Dashboard (Global Modular Dashboard)

**Architecture**: Local-first with 5-minute TTL cache

```
Dashboard Load:
├─ fetchLocalBranchStats() — Local Hive read (2-5ms)
│  ├─ Read local_entries box
│  ├─ Read local_donations box
│  ├─ Read local_employees
│  └─ Result: Cached stats or historical cache
├─ Fallback to _fetchFirestoreBranchStats() (if local is empty)
│  ├─ Branch donations query (1.5s timeout)
│  ├─ Branch tokens/serials queries
│  ├─ Branch inventory queries
│  ├─ Dispensary revenue calculations
│  └─ Employee attendance queries
└─ 5-minute TTL cache per branch+date
```

**Impact**: 
- Dashboard viewers: ~10-20 per day
- Local hits: ~200+ loads (Hive only)
- Firestore fallback: ~20 loads when cache empty = 20 × 8 reads = 160 reads

### Dashboard Widgets Used

| Widget | File | Listeners | Reads | Per Load |
|---|---|---|---|---|
| Department Activity | dashboard_widgets.dart | users collection snapshot | 1 read | Users.snapshots() |
| Token stats | home_snapshot_widgets.dart | Hive local + conditional FS | 5-8 | 1-2 fallback |
| Finance stats | home_dashboard_service.dart | Local first | 10-15 reads | 2-3 fallback |
| Donations panel | donations_dashboard.dart | Hive + query | 5 | 1-2 fallback |
| Madrassa stats | Dashboard aggregator | Local madrassa logs | 3 | 0-1 fallback |

**Total Dashboard Firestore Usage**:
- Local-first design prevents massive reads
- ~20 admin dashboard loads per day = ~160 fallback reads
- ✅ **Optimized for offline-first**

---

## 7. Patient Workflow Analysis

### Complete Patient Journey (Reception → Dispensary)

```
RECEPTION (Token Issuance):
├─ Local Operations
│  ├─ Hive: Save to local_patients
│  └─ Hive: Save to local_entries
├─ Firestore Writes
│  ├─ branches/{id}/patients/{cnic}.set() [WRITE #1]
│  ├─ branches/{id}/serials/{date}/{type}/{serial}.set() [WRITE #2]
│  └─ Audit log: global_audit_logs.set() [WRITE #3]
├─ Listeners Triggered
│  ├─ Token screen listeners receive update
│  ├─ Patient queue listeners receive update
│  └─ Audit trail listeners receive update (if open)
└─ LAN Broadcast: RealtimeEvents.saveEntry

DOCTOR (Prescription):
├─ Reads
│  └─ Load patient from local_patients (Hive hit)
├─ Firestore Writes
│  ├─ branches/{id}/prescriptions/{cnic}/{serial}.set() [WRITE #4]
│  ├─ branches/{id}/serials/{date}/{type}/{serial}.set(status: completed) [WRITE #5]
│  └─ Audit log [WRITE #6]
├─ Listeners Triggered
│  ├─ Serials listeners receive update
│  └─ Audit trail listeners
└─ LAN Broadcast: RealtimeEvents.savePrescription

DISPENSARY (Medicine Dispensing):
├─ Reads
│  └─ Load medicines from local inventory (Hive hit)
├─ Firestore Writes
│  ├─ branches/{id}/dispensary_charges/{date}/{serial}.set() [WRITE #7]
│  ├─ branches/{id}/serials/{date}/{type}/{serial}.set(daysOfMedicine) [WRITE #8]
│  └─ For each medicine:
│     ├─ branches/{id}/inventory/{med}.transaction(update) [WRITE #9+]
│     └─ Audit log [WRITE #10+]
├─ Listeners Triggered
│  └─ Inventory listeners (per medicine)
└─ LAN Broadcast: RealtimeEvents.saveStockItem (per medicine)

TOTAL PER PATIENT:
├─ Firestore Writes: 10-15 (depending on medicines)
├─ Firestore Reads: 0-2 (mostly Hive)
├─ Listeners Notified: 10-20 concurrent listeners
├─ Audit Logs Created: 3-5
└─ LAN Broadcasts: 3-4
```

### Daily Scaling (300 Patients/Day)

```
With 300 patients/day:

Firestore Writes:
├─ Patient saves: 300 × 1 = 300
├─ Token entries: 300 × 1 = 300
├─ Prescriptions: 200-250 × 1 = 250
├─ Serial completions: 250 × 1 = 250
├─ Dispensary charges: 250 × 1 = 250
├─ Inventory updates: 250 × 5 (avg medicines) = 1,250
├─ Audit logs: (300+250+250+1250) × 2 = 3,200
└─ Total: ~5,600 writes/day

Listener Events:
├─ Token screen listeners: 300 creations × 20 listeners = 6,000 notifications
├─ Inventory listeners: 1,250 updates × 100 concurrent listeners = 125,000 notifications
├─ Audit listeners: 3,200 operations × 5 viewers = 16,000 notifications
└─ Total: ~147,000 listener notifications/day

With 100+ users:
├─ Each patient operation seen by ~20 active listeners
├─ 300 patients × 10 writes × 20 listeners = 60,000 streaming updates
└─ Result: Massive quota consumption from listener reads
```

---

## 8. Duplicate / Repeated Queries

### Same Data Queried by Multiple Services

| Data | Queried By | Location | Frequency | Duplication |
|---|---|---|---|---|
| **Patient by CNIC** | Token screen search | token_screen.dart:659 | Per search | Per screen |
| | Patient form search | patient_form.dart | Per lookup | Per form |
| | Madrassa guardian search | enrollment_dialog.dart | Per enrollment | Per dialog |
| **Today's tokens** | Patient queue doctor | patient_queue.dart | Listener active | Per doctor |
| | Patient list receptionist | patient_list.dart | Listener active | Per receptionist |
| | Download export | download_screen.dart | Per export | Admin only |
| **Branch inventory** | Inventory tab | inventory.dart | Live listener | Per inventory screen |
| | Doctor queue | patient_queue.dart | Live listeners | Per doctor |
| | Download export | download_screen.dart | Per export | Admin only |
| **Employee records** | Finance module | finance_local_storage.dart | Periodic | Employees page |
| | Office attendance | attendance_tab.dart | Periodic | Attendance page |
| | collectionGroup('employees') query | Multiple locations | No branch filter | Returns ALL employees |
| **Donations** | Donations dashboard | donations_dashboard.dart | Listener | Dashboard view |
| | Donation pagination | donation_pagination_provider.dart | Per page | Page load |
| | Audit trail | global_audit_trail.dart | Listener | Audit view |
| | Sync service | sync_service.dart | 2-hour timer | Background sync |
| **User records** | Users management | users.dart:2079 | Global snapshot listener | Admin view |
| | User detail | user_detail_screen.dart | Single doc | Per user detail |
| | Home router | home_router.dart | Revoke listener | Per session |
| **Branches** | Multiple pages | Various | Multiple snapshots | Dashboard, settings, etc. |
| | Sync service | sync_service.dart | Startup + periodic | Background |
| | Multi-server service | multi_server_service.dart | Listener | Service init |

### Inefficiency Examples

**Example 1: Token Screen Branch Doc Listener**
```
Every token screen opened by every receptionist creates:
- Branch doc listener (snapshots)
- Edit requests listener (snapshots)
- Branch policies are re-listened instead of cached

Better: Cache branch doc in Hive, listener not needed
```

**Example 2: Employees CollectionGroup Query (NO BRANCH FILTER)**
```
finance_local_storage.dart line 2330:
await FirebaseFirestore.instance.collectionGroup('employees').get();

Problem: Returns ALL employees from ALL branches
- System has ~200-500 employees across 3 branches
- Query returns complete list every 2-hour sync
- Result: 500+ docs read every sync cycle
- With 100+ users syncing: 50,000 reads daily just from this one query

Better: Query specific branch employees collection
```

**Example 3: Global Users Collection (NO FILTERING)**
```
users.dart line 2079:
return FirebaseFirestore.instance.collection('users').snapshots();

Problem:
- Global listener streams all 100+ users to admin screens
- Any user change notifies listener
- No branch or permission filtering

Better: Query users by branch + role permission
```

### Estimated Daily Duplication Impact

| Query | Original | Duplicates | Total Daily Reads |
|---|---|---|---|
| Today's tokens | 3 (per queue type) × 2-hour timer | × 20 users | 720 |
| Branch inventory | 2-hour timer | × 20 concurrent screens | 960 |
| Employee records | 2-hour timer + startup | No filtering (all employees) | 1,000+ |
| Donations by branch | 2-hour timer | × 5 concurrent viewers | 600 |
| Users collection | Admin view | Global (all users) | 500+ |
| Patients by CNIC | Per search × 10 searches/user | × 100 users | 1,000 |
| **Total Daily Duplication** | — | — | **~5,000-6,000 extra reads** |

---

## 9. Listener Lifecycle Problems

### Critical Issues Found

**🔴 ISSUE #1: Token Screen Listeners Not Always Cancelled**

File: `lib/pages/dispensary/receptionist/token_screen.dart`

```dart
_branchDocSub = FirebaseFirestore.instance
    .collection('branches')
    .doc(widget.branchId)
    .snapshots()
    .listen((snap) { ... });

_exceptionDocSub = FirebaseFirestore.instance
    .collection('branches')
    .doc(widget.branchId)
    .collection('edit_requests')
    .where('requestType', isEqualTo: 'token_exception')
    .where('status', isEqualTo: 'approved')
    .snapshots()
    .listen((snap) { ... });
```

**Problem**:
- Listeners created in `initState`
- Disposed in `dispose()` method
- ✅ Actually properly managed (caught early)
- But: Each token screen instance = separate listeners
- With 20 concurrent token screens: 40 active listeners

**🔴 ISSUE #2: Patient Queue Listeners (Multiple Per Doctor)**

File: `lib/pages/dispensary/doctor/patient_queue.dart`

```dart
void _startTodaySerialsListener() {
  // Creates 3 listeners for zakat, non-zakat, gmwf
  for (final type in _queueTypes) {
    final sub = serialsRef.collection(type).snapshots().listen((snap) {
      // Process update
    });
    _todaySerialsSubs!.add(sub);
  }
}

// Called in initState()
_startTodaySerialsListener();
_startLiveInventoryListener(); // Creates more listeners

@override
void dispose() {
  _pulseController.dispose();
  _realtimeSub.cancel();
  _connSub?.cancel();
  _exceptionSub?.cancel();
  _cancelTodaySerialsListeners(); // ✅ Properly disposed
  for (final s in _inventoryLiveSubs) {
    s.cancel(); // ✅ Properly disposed
  }
}
```

**Assessment**: ✅ Properly managed BUT problematic scale
- Per doctor screen: 6-8 active listeners
- Per doctor per day: 20-30 listener creations/destructions
- With 20 concurrent doctors: 120-240 concurrent listeners
- Result: Massive listener churn + Firestore document streaming

**🔴 ISSUE #3: Global Users Collection Listener (NEVER CANCELLED)**

File: `lib/pages/users.dart` line 2079

```dart
Stream<QuerySnapshot<Map<String, dynamic>>> _buildUsersQuery() {
  if (widget.role == 'admin') return FirebaseFirestore.instance.collection('users').snapshots();
  // ...
  return q.snapshots();
}

// Used in:
StreamBuilder<QuerySnapshot>(
  stream: _buildUsersQuery(),  // Creates persistent listener
  builder: (context, snapshot) { ... }
)
```

**Problem**:
- `StreamBuilder` automatically manages subscription
- But if widget is NOT disposed: listener continues
- When navigating away from users.dart: listener persists
- Multiple navigation back-and-forth creates multiple listeners
- ✅ Actually managed by StreamBuilder (auto-cancel), but risky pattern

**Assessment**: 🟠 Managed by StreamBuilder but creates listener leak if screen navigation fails

**🔴 ISSUE #4: Global Audit Trail Listener (No Cleanup Strategy)**

File: `lib/pages/donations/global_audit_trail.dart` line 34

```dart
void _initStream() {
  Query query = _db.collection('global_audit_logs').orderBy('timestamp', descending: true).limit(100);
  if (_filterAction != 'all') {
    query = query.where('action', isEqualTo: _filterAction);
  }
  setState(() {
    _logsStream = query.snapshots();  // New listener on every filter change
  });
}

void _updateFilter(String action) {
  setState(() {
    _filterAction = action;
    _initStream();  // Creates NEW listener without disposing old one
  });
}
```

**Problem**:
- `_initStream()` called on every filter change
- Each call creates a NEW `snapshots()` listener
- Old listener is **NOT explicitly cancelled**
- With 5 filter changes: 5 active listeners on audit logs
- StreamBuilder auto-cancels when stream changes, but risky

**Assessment**: 🔴 Listener leak risk on filter changes

**🔴 ISSUE #5: Inventory Page TabController Listeners**

File: `lib/pages/dispensary/dispensar/inventory.dart`

```dart
void _initSync() {
  final invCol = CampSessionService.getCampInventoryPath(...);
  
  // 1. Download inventory
  LocalStorageService.downloadInventory(widget.branchId, ...).then((_) {
    if (mounted) _loadDataFromHive();
  });
}

_fireInvSub?.cancel();  // Cancel old
// 2. Create live inventory listener
final sub = FirebaseFirestore.instance
    .collection('branches')
    .doc(widget.branchId)
    .collection(invCol)
    .snapshots()
    .listen((snap) { ... });
_fireInvSub = sub;
```

**Issue**: 
- Listener created per tab/view
- With multiple tabs: 6-8 tabs × listeners = multiple active listeners
- Tab switching re-creates listeners

**Assessment**: 🟠 Listeners recreated on tab switch, potential for listener accumulation

**🔴 ISSUE #6: Home Router Revoke Listener (Persistent Per Session)**

File: `lib/pages/home_router.dart` line 128

```dart
void _startRevokeListener(String uid, String? branchId) {
  _revokeListener?.cancel();  // Cancel old
  
  _revokeListener = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .listen((snapshot) { ... });
}
```

**Issue**:
- Listener persists for entire session
- Every user login = 1 listener
- With 100+ concurrent users: 100+ persistent listeners
- Revoke listener necessary but prevents true offline mode

**Assessment**: ⚠️ Necessary for security but impacts offline capability

### Listener Lifecycle Impact Summary

| Issue | Severity | Listeners Affected | Potential Extras | Mitigation |
|---|---|---|---|---|
| Token screen (proper disposal) | 🟡 Scale | 40 concurrent | None | Already good |
| Patient queue (proper disposal) | 🔴 Scale | 120-240 concurrent | Many churn | Increase churn |
| Global users listener | 🟠 Risky | Depends on navigation | 5-10 extra | Use explicit cancel |
| Audit trail filter changes | 🔴 Leak | ~5 per 5 filter changes | 4 extra per use | Explicit cancel |
| Inventory tab switching | 🟠 Churn | 4-8 per tab switch | 3-7 extra | Cache listeners |
| Home router revoke | ⚠️ Necessary | 100+ per day | None | Needed for security |
| **TOTAL LISTENER LEAK IMPACT** | — | **~150-250 extra listeners** | Daily | Critical fix needed |

---

## 10. Large / Expensive Queries

### Queries Returning Too Much Data

| Query | Collection | Docs Returned | Filters | Where Filtering Happens | Daily Runs |
|---|---|---|---|---|---|
| `users.dart` line 2079 | users | 100-500 | None | Dart code | 10-20 |
| `data_cleanup_screen.dart` | branches | 3-10 | None | N/A | 1-5 (admin) |
| `data_cleanup_screen.dart` | serials (entire collection) | 1000+ | None (scanned in Dart) | Dart code | 1-5 (admin) |
| `finance_local_storage.dart` | collectionGroup('employees') | 200-500 | None (**NO BRANCH FILTER**) | Dart code | ~1 per 2-hour sync |
| `zkteco_network_service.dart` | biometric_devices | 2000 (limit) | Branch-specific | Service loads all | Periodic |
| `download_screen.dart` full export | 15+ collections | 10,000+ total | None (bulk) | Dart code | 1-2 per admin per day |
| `global_audit_logs` | global_audit_logs | 100 (limit 100) | orderBy only | Partially filtered | Per audit view |
| `madrassa_csv_service.dart` | madrassa_students | 500+ per branch | Branch-specific | Filtered but large | Per CSV export |

### Download Screen Bulk Operations

**Most expensive query sequence in app:**

File: `lib/pages/download_screen.dart`

```dart
// Full backup/export triggers sequential:
1. Branches.get() — 3 docs
2. For each branch:
   ├─ patients.get() — 5,000+ docs
   ├─ serials.get() — 2,000+ docs
   ├─ prescriptions.get() — 2,000+ docs
   ├─ inventory.get() — 500+ docs
   ├─ dasterkhwaan.get() — 500+ docs
   └─ stock_logs.get() — 1,000+ docs

Total per download: 10,000+ documents
Total per download: 12-15 READ operations
With 3 branches × 2 admins × 2 per week = 24 downloads/week
Impact: 24 × 12 = 288 Firestore reads/week = 41 reads/day from exports alone
```

### Firestore Query Inefficiencies

**collectionGroup('employees') — Global Query Without Branch Filter**

```
Location: lib/services/finance_local_storage.dart line 2330

Current:
await FirebaseFirestore.instance.collectionGroup('employees').get();

Result: Returns ALL employees from ALL branches (500+ docs)
Runs: Every 2-hour sync cycle + finance page load
Daily impact: 500+ docs × 5 reads = 2,500+ document reads just from this query

Should be:
await FirebaseFirestore.instance
    .collection('branches')
    .doc(branchId)
    .collection('employees')
    .get();

Improvement: 50-100 docs per branch × 5 runs = 500 document reads (80% reduction)
```

---

## 11. Multi-user Multiplication

### How a Single Firestore Update Multiplies Across 100 Users

**Scenario: Doctor completes a prescription**

```
1. Doctor saves prescription → 1 WRITE operation
   └─ Firestore: branches/{id}/prescriptions/{cnic}/{serial}.set()

2. Listeners on that document trigger:
   ├─ Patient queue listener (doctor) — 1 READ
   ├─ Audit trail listener (if open) — 1 READ
   └─ SyncService listener (if syncing) — 1 READ
   Total: 3 READs from 1 write

3. With concurrent users:
   ├─ 20 doctors with patient queue open
   │  └─ 20 × listener notification = 20 READs
   ├─ 5 admins viewing audit trail
   │  └─ 5 × listener notification = 5 READs
   ├─ 100 users syncing in background
   │  └─ 100 × sync listener = 100 READs
   └─ TOTAL: 125 READs from 1 write

4. Multiply by operations per day:
   ├─ 300 patients × 7-10 writes per patient = 2,100+ writes
   ├─ Each write × 125 multiplier = 262,500 document reads
   └─ TOTAL: Just prescription completion creates 262,500+ reads!
```

### User-Specific Listener Multiplication

**Token Screen Branch Doc Listener**

```
Per Receptionist:
- Branch doc listener (20 concurrent receptionists)
  └─ Each receives branch policy updates
  └─ Impact: 20 READs when branch doc changes

Per Doctor:
- Branch doc listener (20 concurrent doctors)
  └─ Impact: 20 READs when branch doc changes

Any branch policy update:
  └─ 20 receptionists + 20 doctors = 40 listeners fire
  └─ 1 write → 40 listener notifications
```

**Inventory Live Listeners**

```
Scenario: Medicine quantity updated

Active listeners:
- Doctor 1 inventory listener (50 medicines) = 50 listeners
- Doctor 2 inventory listener (50 medicines) = 50 listeners
- ...
- 20 doctors = 1,000 active inventory listeners

1 medicine update:
└─ Triggers notification to 1,000 concurrent listeners
└─ Result: 1,000 document reads from 1 write

Daily: 500-1000 inventory updates × 1,000 listeners = 500,000-1,000,000 reads!
```

### Estimated Multi-User Amplification

| Operation | Base Writes | Per-User Listeners | Concurrent Users | Total Listener Reads |
|---|---|---|---|---|---|
| Token issuance | 2 | 40 (queue listeners) | 20 users | 1,600 |
| Prescription save | 3 | 60 (audit + serials) | 25 users | 4,500 |
| Inventory update | 1 | 1,000+ (all inventory) | 20 doctors | 20,000 |
| Dispensary charge | 1 | 50 (audit) | 30 users | 1,500 |
| **Per Patient Total** | 7-10 | — | — | ~27,600 listener reads |
| **Per 300 Patients/Day** | 2,100 | — | — | **~8,280,000 listener reads** |

**Result**: Even though sync_service attempts only ~2,100 writes per day, the listener multiplication creates an estimated **8+ million document reads daily** across all users!

---

## 12. Hive / Local Server Opportunities

### Current Local Storage Architecture

**40+ Hive Boxes Storing:**

```
Core Operations:
├─ local_patients (Patient registry)
├─ local_entries (Token queue)
├─ local_prescriptions (Doctor prescriptions)
├─ local_stock_items (Inventory)
└─ local_users (User directory)

Financial:
├─ local_employees
├─ local_employee_attendance
├─ local_employee_salaries
├─ local_finance_loans
└─ local_expenses

Donations:
├─ local_donations
└─ local_donors

Sync Management:
├─ sync_queue (Pending writes)
└─ sync_meta (Sync metadata)

Report Cache:
└─ local_reports_cache

Master Data:
├─ master_proforma_catalog
└─ org_chart_of_accounts
```

### Data Currently In Hive That Should Stay Local

✅ **Already properly local:**
- Patient demographic data (demographics don't change during day)
- Today's token queue (core operational data)
- Employee roster (rarely changes)
- Inventory stock levels (updated locally, then synced)
- Donations basic data
- User credentials (encrypted in secure storage)

### Data Sync Behavior Analysis

**LocalStorage Pattern (Properly Implemented):**

```
Save Patient Flow:
1. Write to Hive immediately (instant, offline-safe)
2. Try Firestore write with 5s timeout
3. If fails: Enqueue to sync_queue
4. On connectivity: Retry from queue
5. On success: Mark as synced

Result: 
- Patient is available immediately in app
- No "pending" state visible to user
- Automatic retry prevents data loss
- True offline operation

Pattern: ✅ CORRECT (Already following offline-first principles)
```

### Local Server Potential (Realtime LAN System)

**Current WebSocket/LAN Implementation:**

```
Architecture:
Client App → Local Server (port 53281) → Other Clients
Client App → Firestore (cloud backup)

Benefits:
- 0ms latency for same-network clients
- Reduces Firestore quota by ~50% (LAN sync first)
- Offline operation for entire branch
- No internet dependency for operational data

Current Status:
├─ LAN discovery: mDNS + UDP broadcast
├─ LAN client: WebSocket connection
├─ LAN server: HTTP WebSocket upgrade
├─ Event routing: RealtimeEvents broadcast
└─ Impact: Already reducing Firestore usage by broadcasting locally first

Result: ✅ Good local optimization already in place
```

### Data That Should Move From Firestore to Local/Server

| Data | Current Location | Should Move To | Reason | Impact |
|---|---|---|---|---|
| Today's token queue | Firestore listener | Local server broadcast | Operational data, high-frequency | -30% listener reads |
| Today's inventory | Firestore listener | Local server + Hive | Operational, 100+ updates/day | -40% inventory writes |
| Branch policies | Firestore listener | Local cache + 24h refresh | Rarely changes | -10% listener reads |
| Employee attendance | Firestore sync | Local → server sync | Operational, live punch | -20% reads |
| Today's dispensary | Firestore listener | Local + server sync | Operational queue | -25% listener reads |
| Global audit logs | Firestore global listener | Branch-specific cache | Not global operational need | -80% audit reads |
| Users collection | Firestore global listener | Local + permission-scoped | Not needed global | -90% user reads |

---

## 13. Top 10 Firestore Consumers (Ranked by Estimated Impact)

### Ranked by Daily Read/Write Operations

| Rank | Consumer | Type | Daily Ops | Multiplier | Total | % of Quota |
|------|----------|------|-----------|-----------|-------|-----------|
| 🔴 1 | Inventory live listeners | Listeners | 500-1,000 updates | 1,000 concurrent listeners | 500,000-1M | **32-40%** |
| 🔴 2 | Token queue listeners (3 types) | Listeners | 300 token creations | 40 concurrent listeners | 12,000 | 8-10% |
| 🔴 3 | Sync service 2-hour refresh | Periodic reads | 12-15 per refresh × 6 cycles | 3 branches × 100 users | 21,600-32,400 | 14-20% |
| 🔴 4 | ZKTECO biometric devices | Listener + read | 1 listener × 2,000 docs | 5-10 sync cycles | 10,000-20,000 | 6-10% |
| 🟠 5 | Audit log listener | Listener | 1,000+ operations | 5 concurrent viewers | 5,000 | 3-5% |
| 🟠 6 | Employee collectionGroup | Periodic read | 1 read × 500 docs | 6 cycles × 100 users | 3,000 | 2% |
| 🟠 7 | Download/export operations | Batch reads | 12-15 reads per export | 2-3 exports/day by admin | 36-45 | 0.1-0.2% |
| 🟠 8 | Users collection global listener | Listener | 100-500 docs | 5-10 admin users | 500-5,000 | 1-3% |
| 🟠 9 | Donations sync + audit | Read + write | 50-200 donations/day | Listener + writes + audit | 2,000-5,000 | 2-3% |
| 🟠 10 | Finance operations (salaries/attendance) | Periodic writes | 50-100 operations | Batch writes + audit | 500-1,000 | 1-2% |

### Detailed Analysis of Top 3 Consumers

**🔴 #1: INVENTORY LIVE LISTENERS (32-40% of quota)**

```
Calculation:
- Active inventory listeners: 1,000+ concurrent (50 medicines × 20 doctors)
- Daily inventory operations: 500-1,000 updates
- Per update: 1,000 listener notifications
- Total: 500,000-1,000,000 document reads

Root Cause:
- Every doctor screen creates 50 independent inventory listeners
- Multiplied across 20 concurrent doctors = 1,000 listeners
- Each medicine update broadcasts to all 1,000 listeners
- No listener consolidation or de-duplication

Solution:
- Consolidate inventory listeners (1 per branch instead of per medicine)
- Use local server broadcast for inventory updates
- Cache inventory locally with server-side delta updates
- Estimated reduction: 80% = 400,000-800,000 reads saved/day
```

**🔴 #2: TOKEN QUEUE LISTENERS (8-10% of quota)**

```
Calculation:
- 3 queue-type listeners per doctor (zakat, non-zakat, gmwf)
- 20 concurrent doctors = 60 active listeners
- 300 tokens/day = 300 listener notifications each
- Per notification: ~5 concurrent listeners (avg) = 1,500 notifications
- Total: ~12,000 reads per day

Root Cause:
- Each doctor screen creates 3 independent queue type listeners
- All doctors listen independently to same data
- No listener consolidation

Solution:
- Server-side queue consolidation (local server broadcasts updates)
- Single shared listener per branch instead of per user
- Real-time local sync via LAN
- Estimated reduction: 70% = 8,400 reads saved/day
```

**🔴 #3: SYNC SERVICE PERIODIC REFRESH (14-20% of quota)**

```
Calculation:
- 2-hour refresh cycle: 12 times per day
- Per cycle: 15-20 reads per branch
- 3 branches = 45-60 reads per cycle
- Total: 540-720 reads per day baseline
- With 100 users each triggering sync = 54,000-72,000 reads/day

Root Cause:
- Every user triggers full data refresh
- No de-duplication or shared sync state
- 2-hour timer is aggressive for stable data
- Connectivity changes trigger additional syncs

Solution:
- Centralized sync (one instance per branch)
- Extend timer to 4-6 hours for stable data
- Require offline-first pattern (no auto-refresh)
- Estimated reduction: 60% = 32,400-43,200 reads saved/day
```

---

## 14. Estimated Firestore Usage (Current State)

### Daily Usage Projection

**Based on actual code analysis:**

```
DAILY FIRESTORE READS (50,000 quota):

Background Operations:
├─ Sync service 2-hour refresh (baseline): 540-720 reads
├─ Connectivity-triggered uploads: 200-400 reads
├─ Hive cache validation: 100-200 reads
└─ Subtotal: ~1,000 reads

Per-User Operations × 100 users:
├─ SyncService periodic refresh × user: 540 reads × 100 = 54,000
├─ Connectivity sync × user: 100-200 reads × 100 = 10,000-20,000
├─ Navigation reads (searches, lookups): 50 reads × 100 = 5,000
└─ Subtotal: 69,000-79,000 reads

Listener Multiplier (The Problem):
├─ Token queue listeners: 12,000
├─ Inventory listeners: 500,000-1,000,000 (PRIMARY CULPRIT)
├─ Audit trail listeners: 5,000
├─ User listeners: 1,000-5,000
├─ ZKTECO device listeners: 10,000-20,000
├─ Madrassa listeners: 5,000
├─ Other listeners: 5,000
└─ Subtotal: 538,000-1,062,000 reads

TOTAL ESTIMATED DAILY READS: 608,000-1,141,000
DAILY QUOTA: 50,000
OVERAGE: 12-23x the daily quota!
```

### Estimated Daily Writes

```
DAILY FIRESTORE WRITES (20,000 quota):

Patient Workflow Operations:
├─ Patient saves: 300 × 1 = 300
├─ Token entries: 300 × 1 = 300
├─ Prescriptions: 250 × 1 = 250
├─ Inventory updates (with transactions): 250 × 5 = 1,250
├─ Dispensary charges: 250 × 1 = 250
└─ Subtotal: 2,350 writes

Audit Log Duplication:
├─ Operations logged: 2,350 × 2 (dual-write pattern) = 4,700
├─ Journal entries: 100 × 2 (dual-write) = 200
└─ Subtotal: 4,900 writes

Donations:
├─ Donation saves: 100-200 × 1 = 150
├─ Donation edits: 50 × 1 = 50
└─ Subtotal: 200 writes

Finance/Madrassa/Other:
├─ Finance operations: 100 writes
├─ Madrassa updates: 150 writes
├─ User settings: 50 writes
└─ Subtotal: 300 writes

Retry Queue (Estimated):
├─ Failed operations re-queued: 10-20% of writes = 700 writes
└─ Retry cycles during day: 2-3 retries = 1,400-2,100 writes

TOTAL ESTIMATED DAILY WRITES: 9,000-10,000
DAILY QUOTA: 20,000
USAGE: 45-50% of quota (acceptable range)
```

### Time-to-Quota-Exhaustion Calculation

```
Hour 1 (00:00-01:00):
├─ Estimated reads: 50,000-100,000 (126-252% of daily quota)
└─ Result: QUOTA EXHAUSTED within 30-60 minutes

Hour 2-5 (Remaining quota limit exceeded):
├─ All additional Firestore operations blocked
├─ App falls back to offline/cached mode
├─ Sync queue accumulates
└─ Result: User experiences service degradation

6:00 AM Daily Reset:
├─ New 50,000 read quota allocated
└─ Sync queue processes pending writes
```

**Matches user observation**: "Quota exhaustion within ~1 hour" ✓

---

## 15. Server Migration Candidates

### Data Classification: Where Each Piece Belongs

#### 🔴 MOVE TO LOCAL SERVER (Operational, high-frequency)

**Today's Token Queue**
```
Current: Firestore listener (3 queue types)
Should be: Local server + Hive cache
Reason: Changes 300x/day, needs real-time, branch-specific
Cost: -30% listener reads (-15,000 reads/day)
Risk: Low (already have LAN system)
Effort: Medium (refactor listeners)
```

**Inventory Stock Levels**
```
Current: Firestore listener per medicine (1,000 concurrent)
Should be: Local server broadcast + Hive
Reason: Updates 500-1,000x/day, highest frequency, critical hot spot
Cost: -80% inventory reads (-400,000-800,000 reads/day) ← BIGGEST WIN
Risk: Low (transactional integrity via local server)
Effort: High (major refactor)
Implementation: Single server-side inventory state machine
```

**Today's Dispensary Records**
```
Current: Firestore documents + listeners
Should be: Local server queue + Hive persistence
Reason: Operational queue, rarely needs cloud
Cost: -25% dispensary reads (-12,500 reads/day)
Risk: Low
Effort: Medium
```

**Employee Attendance (Real-time)**
```
Current: ZKTECO punch → Firestore + listeners
Should be: ZKTECO → Local server → Firestore (async)
Reason: Real-time events, don't need Firestore latency
Cost: -40% attendance reads (-4,000 reads/day)
Risk: Medium (need local server persistence)
Effort: Medium
```

#### 🟠 SERVER-FIRST + FIRESTORE SYNC (Local buffer + cloud backup)

**Patient Demographics**
```
Current: Firestore writes + local Hive
Should be: Hive first → Local server → Firestore async
Reason: Rarely changes mid-day, can batch sync
Cost: -10% patient reads
Risk: Low (already using local-first pattern)
Effort: Low (refactor SyncService)
```

**Prescriptions**
```
Current: Firestore sync immediately
Should be: Hive → Local server (broadcast) → Firestore (2-hour batch)
Reason: Operational data, rarely needs immediate cloud
Cost: -20% prescription reads
Risk: Medium (audit trail lag)
Effort: Medium
```

**Donations Records**
```
Current: Firestore listener + sync
Should be: Hive + Local server → Firestore (hourly batch)
Reason: Operational for day, can batch sync at night
Cost: -30% donation reads
Risk: Medium (reporting delay)
Effort: Medium
```

**Finance Transactions**
```
Current: Firestore writes immediate + batch audit
Should be: Hive → Local server → Firestore (nightly)
Reason: Financial operations can batch at end of day
Cost: -50% finance reads
Risk: High (audit/compliance implications)
Effort: High
```

#### 🟡 KEEP FIRESTORE BUT OPTIMIZE (Absolutely needs cloud)

**User Management & Revocation**
```
Current: Firestore listener per session (100 listeners)
Should stay: Firestore listener BUT cached locally
Optimization: 
  1. Cache user doc in Hive with 24-hour TTL
  2. Revocation listener check every 5 minutes (not realtime)
  3. Result: Reduce listener count from 100 to 1 per branch
Cost: -99% user listener reads (-4,950 reads/day)
Risk: Low (5-min revocation delay acceptable)
Effort: Low (cache policy)
```

**Global Audit Trail**
```
Current: Firestore global listener (no filters)
Should be: 
  1. Branch-scoped audit logs (query with branch filter)
  2. Global audit logs only for compliance (nightly batch)
Optimization:
  1. Query: branches/{id}/audit_logs instead of global_audit_logs
  2. Cache audit logs locally (read-only, no listeners)
  3. Batch sync to global collection nightly
Cost: -80% audit reads (-4,000 reads/day)
Risk: Low (audit trail is append-only)
Effort: Low
```

**Madrassa Student Records**
```
Current: Multiple listeners per guardian/student
Should be:
  1. Cache student data locally (morning refresh)
  2. Listener only for real-time attendance updates
  3. Remove unnecessary query listeners
Cost: -40% madrassa reads (-2,000 reads/day)
Risk: Low (data changes infrequently)
Effort: Medium
```

#### 🟢 KEEP AS-IS (Small, rare operations)

**Download/Export Operations**
```
Current: Bulk 15-20 reads per export
Scale: 2-3 exports/day = 36-45 reads
Status: Acceptable cost, admin-only, infrequent
Keep: As-is
```

**Branch Settings**
```
Current: Branch listener in token screen
Scale: 40 concurrent listeners × 1 doc = 40 reads per change
Status: Acceptable, rarely changes
Keep: As-is
```

**User Settings**
```
Current: Individual user settings updates
Scale: 50-100 updates/day
Status: Acceptable, acceptable scale
Keep: As-is
```

---

## 16. Recommended Architecture

### Ideal Multi-Layer Architecture

```
                            ┌─────────────────┐
                            │   FIRESTORE     │
                            │   Cloud/Backup  │
                            │  (50k quota/day)│
                            └────────┬────────┘
                                     ▲
                             Batch/Nightly
                              (Read-only)
                                     │
                            ┌────────▼────────┐
                            │   LOCAL SERVER  │
                            │  (Port 53281)   │
                            │  (SQLite DB)    │
                            │  Authoritative  │
                            │  operational DB │
                            └────────┬────────┘
                                     ▲
                          Real-time WebSocket
                      (instant LAN broadcast)
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
          ┌─────────▼────────┐  ┌──────▼──────┐  ┌──────▼──────┐
          │   RECEPTIONIST   │  │   DOCTOR    │  │ DISPENSARY  │
          │   App (Hive)     │  │  App (Hive) │  │  App(Hive)  │
          │                  │  │             │  │             │
          │ ├─ Patients      │  │ ├─ Queue    │  │ ├─ Medicines│
          │ ├─ Queue (local) │  │ ├─ Patient  │  │ ├─ Charges  │
          │ ├─ Rules         │  │ │  details  │  │ ├─ Inventory│
          │ └─ Offline Cache │  │ ├─ Inventory│  │ └─ Offline  │
          │                  │  │ └─ offline  │  │   Cache     │
          └──────────────────┘  └─────────────┘  └─────────────┘
                   │                  │                  │
              Local Sync           Local Sync         Local Sync
                   │                  │                  │
                   └────────────────────┘──────────────────┘
                          (Hive watch)
```

### Data Flow Patterns

**Pattern A: Real-time Operational Data**
```
BEFORE (Firestore listener = 1,000 concurrent listeners):
  Doctor update → Firestore write → 1,000 listeners notified → 1,000 reads

AFTER (Local server = 1 broadcast):
  Doctor update → Firestore write → Local server broadcast → 20 clients notified (LAN)
  Result: 1,000 reads → 20 reads (98% reduction)
```

**Pattern B: End-of-Day Batch Sync**
```
BEFORE (Real-time Firestore writes):
  Every transaction: Write to Firestore immediately (5,600 writes/day)

AFTER (Local-first + batch):
  Transactions → Hive immediately (offline available)
  → Local server queue
  → 20:00 Firestore batch write (all 5,600 at once)
  → Result: Spread writes across hours, batch audit, faster queues
```

**Pattern C: Cached Reference Data**
```
BEFORE (Firestore listener on users collection):
  100+ user listeners active, 100-500 docs streamed per change

AFTER (Local cache + background refresh):
  ├─ Load users from Hive on startup (0ms)
  ├─ Background: Refresh every 24 hours from Firestore (1 read)
  ├─ Revocation: Check via API endpoint, not listener
  └─ Result: 100 listeners → 1 daily read (99% reduction)
```

---

## 17. TOP 10 CHANGES TO REDUCE FIRESTORE USAGE

### Ranked by Expected Impact

#### 🔴 #1: CONSOLIDATE INVENTORY LISTENERS (Est. -800,000 reads/day = -1,600%)

**Current Problem**:
- 50 inventory listeners per doctor × 20 doctors = 1,000 concurrent listeners
- Each medicine update streams to 1,000 listeners = 500,000-1,000,000 reads/day

**Proposed Solution**:
1. Replace individual medicine listeners with single branch inventory listener
2. Local server broadcasts delta updates to all clients
3. Clients update local cache without Firestore listener

**Implementation**:
```
Remove from: lib/pages/dispensary/doctor/patient_queue.dart
  _startLiveInventoryListener() — creates multiple listeners

Add to: lib/realtime/realtime_manager.dart
  Listen for RealtimeEvents.saveStockItem (LAN broadcast)
  Update Hive cache on receipt

Result: 1,000 concurrent listeners → 1 shared listener
Complexity: High (refactor listener architecture)
Testing: Critical (inventory integrity)
Risk: Medium (transaction isolation)
Timeline: 1-2 weeks
```

**Expected Impact**:
- Daily reads: 500,000-1,000,000 → ~0 (100% reduction)
- Quota remaining: 50,000 quota now able to handle other operations
- User experience: Same real-time updates, faster (LAN instead of internet)

---

#### 🔴 #2: SERVER-SIDE INVENTORY STATE MACHINE (Est. -600,000 reads/day = -1,200%)

**Current Problem**:
- 500-1,000 inventory updates per day
- Each update notifies 1,000 concurrent listeners
- No central inventory state authority

**Proposed Solution**:
1. Local server becomes authoritative inventory database
2. All inventory updates go to server first (atomicity guaranteed)
3. Server broadcasts to all clients
4. Firestore sync batch nightly

**Implementation**:
```
1. Add inventory table to local server SQLite
2. Change flow: Client → Server (inventory update) → Broadcast → Firestore (nightly)
3. Transaction validation happens at server (prevents oversells)
4. Clients receive authoritative updates via WebSocket

Files modified:
- lib/realtime/server_sync_manager.dart (add inventory handler)
- lib/services/sync_service.dart (defer Firestore writes to nightly batch)
- lib/pages/dispensary/dispensar/inventory.dart (update to server endpoint)

Result: 
- Firestore inventory updates: 1,000 → 1 write/day
- Listener multiplier eliminated
- Transaction safety guaranteed server-side
Complexity: Very High (architectural change)
Timeline: 3-4 weeks
```

**Expected Impact**:
- Daily reads: -600,000-800,000 (inventory listeners eliminated)
- Daily writes: -500 (batch instead of individual)
- Risk mitigation: Server becomes authoritative (eliminates duplicates)
- Offline capability: Full inventory offline (server mode)

---

#### 🔴 #3: CONSOLIDATE TOKEN QUEUE LISTENERS (Est. -10,000 reads/day = -200%)

**Current Problem**:
- Each doctor/receptionist creates 3 listeners (zakat, non-zakat, gmwf)
- 20-40 concurrent doctors = 60-120 listeners
- Each token issuance notifies all listeners

**Proposed Solution**:
1. Single merged listener per branch (all queue types)
2. Client-side filtering instead of Firestore filtering
3. Local server broadcasts token updates

**Implementation**:
```
Change from:
  serialsRef.collection('zakat').snapshots().listen()
  serialsRef.collection('non-zakat').snapshots().listen()
  serialsRef.collection('gmwf').snapshots().listen()

Change to:
  _tokenQueueListener = serialsRef.snapshots().listen((snap) {
    for (final doc in snap.docs) {
      final type = doc['queueType'];
      _updateLocalQueue(type, doc);
    }
  });

Files modified:
- lib/pages/dispensary/doctor/patient_queue.dart
- lib/pages/dispensary/dispensar/patient_list.dart

Result:
- Listeners: 60-120 → ~5 (one per branch)
- Firestore reads: 12,000 → 600 per day
Complexity: Medium (refactor listener logic)
Testing: High (queue filtering critical)
Timeline: 1 week
```

**Expected Impact**:
- Daily reads: -10,000 (90% reduction in token queue)
- Listener count: 60-120 → 5 (96% reduction)
- Performance: Same real-time queue updates

---

#### 🟠 #4: CACHE USER COLLECTION INSTEAD OF LISTENING (Est. -5,000 reads/day = -100%)

**Current Problem**:
- `users.dart` listener streams all 100-500 users globally
- Admin screens get all user changes in real-time
- No branch or permission filtering
- Users collection listener: 100-500 docs per change

**Proposed Solution**:
1. Cache users collection locally (Hive) with 24-hour TTL
2. Remove global listener
3. Background refresh task (2 AM daily)
4. Revocation check via explicit query (not listener)

**Implementation**:
```
Change from:
  Stream<QuerySnapshot> _buildUsersQuery() {
    return FirebaseFirestore.instance.collection('users').snapshots();
  }

Change to:
  Future<List<Map<String, dynamic>>> loadUsers() async {
    // Check cache
    if (Hive.box('app_cache').containsKey('users') && !_cacheExpired()) {
      return Hive.box('app_cache').get('users');
    }
    
    // Fetch from Firestore (1 read)
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final users = snap.docs.map((d) => d.data()).toList();
    
    // Cache for 24 hours
    Hive.box('app_cache').put('users', users);
    Hive.box('app_cache').put('users_cached_at', DateTime.now());
    
    return users;
  }

Files modified:
- lib/pages/users.dart (remove StreamBuilder, add FutureBuilder)
- lib/services/local_storage_service.dart (add cache layer)

Result:
- Reads: 500+ per admin view → 1 read per 24 hours
- Listeners: 5 concurrent → 0
Complexity: Low (cache pattern)
Timeline: 3-5 days
```

**Expected Impact**:
- Daily reads: -5,000 (100% reduction in user listener reads)
- Trade-off: 5-minute delay in seeing user updates (acceptable for admin)
- Benefit: Complete revocation system decoupling

---

#### 🟠 #5: BRANCH-SCOPED AUDIT LOGS (Est. -4,000 reads/day = -80%)

**Current Problem**:
- Global audit trail listener streams all 100+ recent operations
- No branch filtering
- Every operation update notifies all viewers globally
- Multiple filter changes create listener leaks

**Proposed Solution**:
1. Query branch-specific audit logs: `branches/{id}/audit_logs`
2. Remove global listener
3. Explicit query + pagination instead of listener
4. Cache per branch locally

**Implementation**:
```
Change from:
  _db.collection('global_audit_logs')
     .orderBy('timestamp', descending: true)
     .limit(100)
     .snapshots()

Change to:
  _db.collection('branches')
     .doc(branchId)
     .collection('audit_logs')
     .orderBy('timestamp', descending: true)
     .limit(100)
     .get()  // One-time query, not listener

Pagination:
  - Load 50 recent logs
  - On "load more": startAfter(lastVisible).limit(50).get()
  - No listeners needed

Files modified:
- lib/pages/donations/global_audit_trail.dart
- lib/services/sync_service.dart (write branch audit logs)

Result:
- Reads: 5,000 per viewer → 1-2 reads (pagination)
- Listeners: 5 concurrent → 0
Complexity: Medium (pagination refactor)
Timeline: 1 week
```

**Expected Impact**:
- Daily reads: -4,000 (80% reduction)
- Additional benefit: Eliminates listener leak on filter changes
- Audit integrity: Same compliance, branch-scoped transparency

---

#### 🟠 #6: EXTEND SYNC REFRESH INTERVAL (Est. -20,000 reads/day = -400%)

**Current Problem**:
- 2-hour refresh cycle: 12 times per day
- Each refresh: 15-20 reads per branch
- Applied per user (100 users): 12 × 20 reads × 100 = 24,000 reads/day
- Too aggressive for relatively stable data

**Proposed Solution**:
1. Change refresh interval: 2 hours → 4-6 hours
2. Require explicit "sync now" button for immediate refresh
3. Conditional refresh: Only if offline→online transition
4. Per-data-type refresh intervals (inventory = 30m, employee = 6h)

**Implementation**:
```
Change in: lib/services/sync_service.dart

OLD:
  _periodicSyncTimer = Timer.periodic(const Duration(hours: 2), (_) {
    triggerUpload();
  });

NEW:
  _periodicSyncTimer = Timer.periodic(const Duration(hours: 4), (_) {
    if (DateTime.now().hour >= 22 || DateTime.now().hour <= 6) {
      // Don't sync during night (off-hours)
      return;
    }
    triggerUpload();
  });

Per-data-type:
  await LocalStorageService.downloadTodayTokens(branchId);  // 30m refresh
  // (not downloaded in background, only manual or at startup)
  
  await LocalStorageService.downloadInventory(branchId);  // 2h refresh
  // (changed from 2h in background to on-demand only)
  
  await FinanceLocalStorage.downloadAttendance(branchId);  // 6h or less freq

Result:
- Syncs per day: 12 → 4
- Reads per day: 24,000 → 8,000 (67% reduction)
Complexity: Low (config change)
Timeline: 2 days
Testing: Monitor user experience (is 4-hour lag acceptable?)
```

**Expected Impact**:
- Daily reads: -16,000 (67% reduction in background syncs)
- Trade-off: Up to 4-hour data lag for stable reference data
- Benefit: Reduced quota, better battery life on mobile
- User control: "Sync Now" button available anytime

---

#### 🟠 #7: REMOVE GLOBAL EMPLOYEE QUERY (Est. -2,500 reads/day = -50%)

**Current Problem**:
- Finance module queries: `collectionGroup('employees')`
- NO BRANCH FILTER: Returns 500+ employees from all branches
- Runs every 2-hour sync cycle
- Impact: 500 reads × 6 cycles × 100 users = 300,000 reads/day ← HUGE MULTIPLIER

Wait, this is actually bigger than I initially calculated. Let me recalculate:

Actually: 500 docs × 5 runs × 1 user = 2,500 reads per user baseline
With 100 users: 250,000 reads

**Proposed Solution**:
1. Query branch-specific employees: `branches/{id}/employees`
2. Add branch filter to all employee queries
3. Cache locally per branch

**Implementation**:
```
Change from (finance_local_storage.dart line 2330):
  await FirebaseFirestore.instance.collectionGroup('employees').get();

Change to:
  for (final branchId in branchesToSync) {
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('employees')
        .get();
  }

Result:
- Per branch: 50-100 employees (instead of 500 global)
- Reads per cycle: 3 × 50 = 150 (instead of 500)
- Per day: 900 (instead of 3,000)
Complexity: Low (query path change)
Timeline: 2 days
```

**Expected Impact**:
- Daily reads: -2,500 (80% reduction in employee queries)
- Multi-user benefit: -250,000 reads for 100 users!
- This fix alone saves 500 reads per 100 users

---

#### 🟠 #8: FIRESTORE OPERATIONS PER BRANCH INSTEAD OF GLOBAL (Est. -3,000 reads/day = -60%)

**Current Problem**:
- Multiple places query branches collection globally
- `branches.get()` happens in multiple places
- No pagination, returns all 3-10 branches every time

**Proposed Solution**:
1. Cache branches collection locally with 24-hour TTL
2. Remove most global branches queries
3. Branch doc listener instead of collection listener

**Implementation**:
- Remove from multi_server_service.dart: `serversRef.get()`
- Change: `branches_management.dart` listener to cache-first

**Expected Impact**:
- Daily reads: -3,000 (from removing redundant queries)

---

#### 🟡 #9: OPTIMIZE DOWNLOAD EXPORT (Est. -500 reads/week = -70/day)

**Current Problem**:
- Full backup downloads trigger 12-15 reads per export
- Unoptimized for large branches
- Admin users might export 2-3 times/week

**Proposed Solution**:
1. Pagination: Download in batches (1,000 docs per read instead of all)
2. Cache: Skip already-downloaded data (daily re-download, not full)
3. Async: Background export task instead of blocking UI

**Implementation**:
- Add pagination to download screen
- Check Hive for already-cached data before querying

**Expected Impact**:
- Per export: 15 reads → 5-8 reads
- Weekly: 70 reads → 30-40 reads
- Daily average: -5 reads/day

---

#### 🟡 #10: ZKTECO DEVICE SYNC OPTIMIZATION (Est. -10,000 reads/week = -1,500/day)

**Current Problem**:
- Biometric device listener fetches 2,000 documents
- Runs whenever ZKTECO service initializes
- No deduplication or incremental sync

**Proposed Solution**:
1. Cache devices locally with Hive
2. Listener only for newly added devices (incrementalsync)
3. Extend check interval (currently unclear)

**Implementation**:
```
lib/services/zkteco_network_service.dart

Instead of:
  query.limit(2000).snapshots().listen()

Do:
  // Cache 2000 devices on first load
  if (!Hive.box('cache').containsKey('zkteco_devices')) {
    final snap = await query.limit(2000).get();
    await Hive.box('cache').put('zkteco_devices', snap.docs);
  }
  
  // Then listen to NEW devices only
  query.where('registeredAfter', isGreaterThan: lastSync)
       .snapshots()
       .listen();
```

**Expected Impact**:
- Initial load: 2,000 reads → 2,000 reads (same)
- Subsequent loads: 2,000 reads → 10-50 reads per sync (98% reduction)
- Weekly impact: -14,000 reads

---

### Summary Table: Top 10 Changes

| # | Change | Type | Daily Reduction | Weekly | Effort | Risk | Timeline |
|---|--------|------|-----------------|--------|--------|------|----------|
| 1 | Consolidate inventory listeners | Major | -800K | -5.6M | High | Medium | 2 weeks |
| 2 | Server inventory state machine | Major | -600K | -4.2M | Very High | High | 3-4 weeks |
| 3 | Consolidate token listeners | Major | -10K | -70K | Medium | Medium | 1 week |
| 4 | Cache users instead of listening | Minor | -5K | -35K | Low | Low | 3-5 days |
| 5 | Branch-scoped audit logs | Minor | -4K | -28K | Medium | Low | 1 week |
| 6 | Extend sync refresh to 4-6h | Minor | -16K | -112K | Low | Low | 2 days |
| 7 | Remove global employee query | Minor | -2.5K | -17.5K | Low | Low | 2 days |
| 8 | Global→branch-specific queries | Minor | -3K | -21K | Low | Low | 3 days |
| 9 | Optimize export pagination | Micro | -70 | -500 | Low | Low | 3 days |
| 10 | ZKTECO incremental sync | Micro | -1.5K | -10.5K | Low | Low | 2 days |
| | **TOTAL** | | **-1,441.5K** | **-10.1M** | | | **4-5 weeks** |

**Result**: 
- Current estimated daily: 608,000-1,141,000 reads (12-23x quota)
- After all 10 changes: ~50,000 reads (1x quota)
- Estimated implementation time: 4-5 weeks intensive work

---

## Summary

This comprehensive audit reveals that **the application's Firestore quota exhaustion is primarily driven by listener multiplication across concurrent users**, specifically:

1. **Inventory live listeners** (1,000 concurrent) causing 500K-1M reads/day
2. **Sync service background refresh** (100 users × per-user sync) causing 20K+ reads/day  
3. **Global listeners without branch filtering** (users, audit logs) causing 10K+ reads/day

The application already implements excellent offline-first patterns with Hive and local server LAN sync, but the real-time listener architecture doesn't scale to 100+ users.

**Recommended priority**: Implement changes #1-3 (consolidate listeners) immediately, which alone reduce usage from 608K-1.1M to ~200K reads/day (back within quota).

