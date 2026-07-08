<p align="center">
  <img src="assets/logo/gmwf.png" alt="GMWF Logo" width="120" />
</p>

# 🕌 Gulzar Madina Welfare Foundation (GMWF)
### Integrated Welfare Operations Platform

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/firebase-%23039BE5.svg?style=for-the-badge&logo=firebase)](https://firebase.google.com)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20iOS-blue?style=for-the-badge)](https://flutter.dev/multi-platform)
[![License](https://img.shields.io/badge/License-Proprietary-red.svg?style=for-the-badge)](LICENSE)

A production-grade **Flutter application** purpose-built for the Gulzar Madina Welfare Foundation. GMWF digitally manages the foundation's entire operational ecosystem—from **medical dispensaries** and **community kitchens (Dasterkhwaan)** to **donation tracking** and **financial auditing**—all under a single unified platform with offline-first reliability and real-time multi-device synchronization.

---

## 🏛️ Foundation Operations

GMWF is not a single-purpose app. It is a **comprehensive welfare management system** covering every operational vertical of the foundation:

### 🏥 Dispensary & Medical Services
The core medical module manages the full patient lifecycle across multiple branches:
- **Patient Registration** — CNIC-based records with complete demographics
- **Token Queue System** — Digital queue management for receptionists
- **Doctor Consultation** — Patient history, prescriptions, and clinical notes
- **Dispensary Fulfillment** — Prescription-linked medicine dispensing with real-time inventory tracking
- **Medicine Inventory** — Stock management with approval workflows for inventory adjustments and edit requests

### 🍲 Dasterkhwaan (Community Kitchen)
A dedicated module for the foundation's free food service:
- **Food Token Issuance** — Daily meal token generation and tracking by office boys
- **Kitchen Management** — Full cooking session logging, with ingredient deduction from stock
- **Pantry Inventory** — 60+ default stock items (vegetables, grains, spices, dairy, meat) with add/adjust/carry-forward
- **Carry-Over Logic** — Leftover food from previous days is automatically carried to the next day's stock
- **Daily History** — Per-date audit trail of tokens issued, meals cooked, and food served

### 💰 Donations & Financial Accountability
A multi-layered donation recording and auditing system with a full credit chain:
- **Multi-Category Recording** — Donations split into **Jamia/Masjid** and **GMWF** funds, with GMWF further broken into Dasterkhwaan, Dispensary, Madrisa, and General sub-categories
- **Cash & Goods Support** — Record monetary donations (Cash, Cheque, Bank Deposit) or in-kind goods contributions (with estimated valuation)
- **Donation Subtypes** — Construction, Maintenance, Iftar, Zakat, Sadqa Wajiba, Sadqa/Atyaat, General
- **Credit Ledger & Chain of Custody** — Office Boy → Manager → Chairman approval flow with full audit trail
- **PDF Receipt Generation** — Professionally branded A5 donation receipts with QR codes
- **WhatsApp Integration** — One-tap thank-you message and receipt sharing via WhatsApp
- **Excel Export** — Chairman-level ledger export for external auditing

### 🎓 Madrassa & Education Services
A complete academic management system for the foundation's educational institutions:
- **Student Enrollment** — Dynamic student profiles, class assignment, and enrollment workflows
- **Daily logs & Monthly Reports** — Attendance sheets, academic logging, and behavior reports (`daily_log_view.dart`, `monthly_report_view.dart`)
- **Holiday Management** — Schedule holidays and academic breaks globally or branch-specifically
- **Guardian Portal** — Dedicated `MadrassaGuardianScreen` allowing parents to track their child's attendance, reports, and fees

### 👥 HR, Payroll & Employee Management
Integrated workforce management to streamline foundation personnel operations:
- **Employee Directory** — Centralized staff records containing roles, active branches, and contract details
- **Salary Ledger & Payroll** — Dynamic tracking of salary payments, payment history, and payroll ledgers
- **Employee Attendance** — Digital attendance register for staff clock-in/clock-out tracking
- **Branch Transfers** — Record and orchestrate employee relocations between foundation branches
- **Audit Logs** — System-wide logger tracking sensitive financial modifications and profile updates

### 📊 Executive Dashboards
Role-specific dashboards for organizational leadership:
- **Chairman Portal** — Global overview of all branches with KPI cards (revenue, patients, food tokens served, donations), branch performance tables, and donation auditing
- **CEO Dashboard** — Aggregate operational metrics and branch comparison
- **HQ Manager View** — Multi-branch oversight with cross-branch credit ledger monitoring
- **Branch Manager View** — Localized branch performance with patient cards and operational metrics
- **Supervisor Portal** — Localized branch oversight, inventory approvals, and request management

---

## ⚡ Technical Architecture

### Offline-First Hybrid Sync

The system uses a three-tier hybrid architecture engineered for zero-downtime clinic operations:

```text
  [ Local Hive Storage ] ◄─────► [ LAN WebSocket Sync ] ◄─────► [ Firebase Firestore ]
    (Primary Persistence)           (Local Real-time Hub)           (Cloud Global State)
```

- **Every write hits Hive first** — the app is fully usable without internet
- **LAN WebSocket sync** keeps all clinic devices in lockstep over the local network
- **Firestore uploads are async and queued** — cloud is the source of truth but never blocks the UI

### 📡 LAN Network Topology

A dedicated always-on device runs the **LAN Hub**, decoupling server logic from any staff workstation:

```
                    ┌─────────────────────┐
                    │   Dedicated Server  │
                    │  (always-on device) │
                    │  WebSocket :53281   │
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
     Receptionist           Doctor             Dispenser
      (client)             (client)            (client)
```

**Discovery methods** (first to succeed wins):
| Method | Speed |
|:--|:--|
| mDNS (`_gmwftoken._tcp`) | ~1–2s |
| UDP Broadcast | ~2–3s |
| Subnet Scan (batches of 25) | Fallback |

### 🔄 Smart Reconnection
When a device reconnects, the server sends only **missed data** to that specific socket — no full re-sync, no broadcast storm.

---

## 👥 Organizational Roles

| Role | Responsibility | Data Scope |
|:--|:--|:--|
| **Chairman** | Executive oversight, donation auditing, Excel exports | Global Firestore — all branches |
| **CEO** | Operational metrics, branch performance comparison | Global Firestore — all branches |
| **HQ Manager** | Multi-branch management, credit ledger oversight | Cross-branch Firestore views |
| **Branch Manager** | Localized operations, credit approval, staff management | Single branch — LAN + Firestore |
| **Supervisor** | Inventory approval, edit request management | Branch-level oversight |
| **Doctor** | Patient consultation, prescriptions, clinical notes | Active tokens + patient history |
| **Receptionist** | Patient registration, token issuance, queue management | Token queue + patient records |
| **Dispenser** | Medicine fulfillment, stock tracking | Prescription queue + inventory |
| **Office Boy** | Food token issuance, donation collection, credit handoffs | Dasterkhwaan + Donations |
| **Kitchen Staff** | Cooking sessions, food logging, pantry management | Dasterkhwaan kitchen operations |
| **Server** | Dedicated LAN hub orchestration | WebSocket server + bridge sync |

---

## 🛠️ Tech Stack

| Layer | Technology |
|:--|:--|
| **Framework** | Flutter (Dart) |
| **Local Storage** | Hive (NoSQL, high-performance) |
| **Cloud Backend** | Firebase (Auth, Firestore, Storage) |
| **Real-time Sync** | WebSockets (raw TCP), mDNS, UDP |
| **State Management** | Provider, RxDart |
| **PDF Generation** | `pdf` + `printing` packages |
| **Design System** | Custom DS with role-based theming |
| **Charts** | FL Chart |
| **Typography** | Google Fonts + Noori Nastaliq (Urdu) |

---

## 📁 Key Module Structure

```
lib/
├── Pages/
│   ├── dispensary/
│   │   ├── receptionist/     # Patient registration + token queue
│   │   ├── doctor/           # Consultation + prescriptions
│   │   └── dispensar/        # Medicine dispensing + inventory
│   ├── dasterkhwaan/
│   │   ├── kitchen.dart      # Cooking sessions + pantry management
│   │   ├── office_boy.dart   # Token issuance + donation recording
│   │   └── stock.dart        # Food stock management
│   ├── donations/
│   │   ├── donations_screen.dart    # Main donations UI
│   │   ├── donations_form.dart      # Multi-category donation form
│   │   ├── donations_dashboard.dart # Analytics + charts
│   │   ├── credit_ledger.dart       # Chain-of-custody ledger
│   │   └── donations_shared.dart    # Design system + PDF + messaging
│   ├── madrassa/
│   │   ├── views/                   # Academic log, reports, oversight
│   │   ├── dialogs/                 # Student registration & enrollment
│   │   ├── providers/               # State management for courses and marks
│   │   └── madrassa_dashboard.dart  # Portal for teacher/admin dashboard
│   ├── chairman_screen.dart         # Executive portal
│   ├── ceo_screen.dart              # CEO dashboard
│   ├── manager_screen.dart          # HQ Manager view
│   ├── branch_manager_screen.dart   # Branch-level management
│   └── admin_screen.dart            # System administration
├── services/
│   ├── firestore_service.dart       # Primary write gateway (Hive + LAN + Firestore)
│   ├── sync_service.dart            # Client-side Firestore uploader
│   ├── local_storage_service.dart   # Hive box management
│   ├── donations_local_storage.dart # Donations offline persistence
│   ├── finance_local_storage.dart   # Salaries and financial records
│   └── auth_service.dart            # Firebase Auth + role-based routing
├── realtime/                        # LAN server, discovery, WebSocket management
├── models/                          # Patient, Token, Prescription, Inventory, Donation, Student, Log
├── theme/                           # Role-based theming + design tokens
└── widgets/                         # Shared UI components + dashboards
```

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK `>=3.10.1`
- Firebase project with Firestore, Auth, and Storage enabled
- Dedicated always-on device for LAN Server
- All clinic devices on the **same local network**

### Installation
```bash
# Clone the repository
git clone https://github.com/gmwf-dev/gmwf.git

# Install dependencies
flutter pub get

# Run code generation (Hive adapters)
flutter pub run build_runner build --delete-conflicting-outputs

# Launch the application
flutter run -d <device_id>
```

### Deployment Order
1. **Start the LAN Server device first** — it begins advertising on the network immediately
2. **Clinical staff devices** (Receptionist, Doctor, Dispenser) log in and auto-discover the server
3. **Executive users** (Chairman, CEO, Managers) connect directly via Firestore — no LAN needed

---

## 🔧 Key Design Decisions

- **Dedicated always-on server** — The LAN hub runs on its own device, independent of any staff member, eliminating instability from device sleep/logout/crash
- **Double-queue uploads** — Clients use `syncBox`, the server uses `server_sync_queue`; both upload to the same Firestore paths independently
- **No runtime Firestore reads** — After initial download, all reads come from Hive; Firestore is write-destination and initial-sync-source only
- **Targeted catch-up** — Reconnecting devices receive only missed data on their specific socket
- **Echo prevention** — `RealtimeManager` ignores messages carrying its own `_clientId`
- **Role-based theming** — Every role gets a distinct visual identity (colors, gradients, card styles) via the `RoleThemeScope` provider

---

## 📄 License

© 2026 **Gulzar Madina Welfare Foundation (GMWF)**. All rights reserved.

This software is the exclusive property of GMWF. Unauthorized copying, distribution, or modification is strictly prohibited. See the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <i>Built for the Gulzar Madina Welfare Foundation — Empowering welfare through technology.</i>
</p>