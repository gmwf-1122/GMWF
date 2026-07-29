<p align="center">
  <img src="assets/logo/gmwf.png" alt="GMWF Logo" width="120" />
</p>

# 🕌 Gulzar Madina Welfare Foundation (GMWF)
### Integrated Enterprise Welfare & Institution Management Platform

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/firebase-%23039BE5.svg?style=for-the-badge&logo=firebase)](https://firebase.google.com)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Web%20%7C%20Android%20%7C%20iOS-blue?style=for-the-badge)](https://flutter.dev/multi-platform)
[![Release](https://img.shields.io/badge/Release-v1.2.5-brightgreen?style=for-the-badge)](https://github.com/gmwf-1122/GMWF)
[![License](https://img.shields.io/badge/License-Proprietary-red.svg?style=for-the-badge)](LICENSE)

A production-grade, multi-platform **Flutter application** purpose-built for the Gulzar Madina Welfare Foundation. GMWF digitally orchestrates the foundation's entire operational ecosystem—spanning **medical dispensaries**, **educational institutions (Madrassa & School)**, **community kitchens (Dasterkhwaan)**, **financial auditing**, **biometric attendance**, **pre-authentication security**, and **automated multi-device session tracking**—with offline-first reliability and real-time synchronization.

---

## 🚀 Latest Updates in v1.2.5

### 🛡️ Pre-Authentication Security & Visitor Telemetry
* **Pre-Login Access Logging** (`pre_login_security_service.dart`): Captures public IP address, persistent device fingerprint UUID (`dev_uuid`), OS version, browser signature, and connection details **before** credentials are typed.
* **Security Audit Trail**: Writes launch events to Firestore collections `security_access_logs` and `app_visitors` to audit unauthorized access attempts to organization portals.
* **Pre-Flight Access Restrictions**: Foundation for enforcing IP subnet and device hardware whitelisting.

### 📱 User & Active Device Session Tracking
* **Platform & Hardware Identification** (`device_info_service.dart`): Automatically detects whether logged-in users are accessing via **Windows Desktop**, **Web (Chrome, Edge, Safari, Firefox)**, **Android**, or **iOS**.
* **Device Name vs Hardware Model Separation**: Accurately distinguishes **Device / PC Name** (e.g. `Ans-kun`) from **Hardware / OS Model** (e.g. `Windows 11 Pro PC`).
* **Visual Badges & Session Cards**: Renders color-coded platform badges ([device_badge_widget.dart](file:///e:/GMWF/gmwf/lib/widgets/device_badge_widget.dart)) across User Management list views and dedicated **Active Device & Session** cards on User Profile screens ([user_detail_screen.dart](file:///e:/GMWF/gmwf/lib/pages/user_detail_screen.dart)).

### ⚡ Centralized Auto-Updater Engine
* **GitHub & Cloud Release Integration** (`auto_update_service.dart`): Connects to GitHub Releases ([`gmwf-1122/GMWF`](https://github.com/gmwf-1122/GMWF)) and Firestore (`app_config/version`) to monitor application updates.
* **In-App Update Modal** ([update_dialog_widget.dart](file:///e:/GMWF/gmwf/lib/widgets/update_dialog_widget.dart)): Prompts users with version diffs (e.g., `v1.2.4 ➔ v1.2.5`), release notes, mandatory update rules, and one-click download/install triggers.
* **Inno Setup Production Installer** ([GMWFSetup.iss](file:///e:/GMWF/gmwf/GMWFSetup.iss)): Fully synchronized production build installer script (`GMWF_Setup_1_2_5.exe`).

---

## 🏛️ Foundation Operations & Modules

### 🏫 School & Madrassa Management System
A comprehensive academic portal for the foundation's educational institutions:
- **Student Enrollment & Profiles** — CNIC/B-Form demographic tracking, class assignment, and academic records.
- **Report Cards & Evaluation** — Customizable report cards (`parent_report_card.dart`), exam grading, and student progress metrics.
- **Daily Academic Logs & Monthly Reports** — Real-time logging of student attendance, Quran Hifz progress, behavioral notes, and monthly evaluations.
- **Guardian & Parent Portal** — Dedicated parent screen (`madrassa_guardian_screen.dart`) allowing parents to view live attendance, academic progress, and fee statuses.
- **Holiday & Term Scheduling** — Academic calendar management for branch-specific or organization-wide breaks.

### 🏥 Dispensary & Medical Services
The core medical module managing patient lifecycles across foundation branches:
- **Patient Registration** — Demographics, contact information, and medical history.
- **Token Queue System** — Digital receptionist queue management.
- **Doctor Consultation** — Clinical notes, diagnosis, and electronic prescriptions.
- **Dispensary Fulfillment** — Prescription-linked medicine dispensing with inventory deductions.
- **Biometric Integration** — Networked ZKTeco biometric device manager (`zkteco_network_service.dart`) for staff attendance.

### 🍲 Dasterkhwaan (Community Kitchen)
Dedicated meal distribution and pantry logistics:
- **Food Token Issuance** — Daily meal token generation and tracking.
- **Kitchen Management** — Cooking session logging with ingredient stock deduction.
- **Pantry Inventory** — Stock tracking for 60+ pantry items with carry-over logic for leftover food.
- **Daily Audit History** — Comprehensive log of meals cooked and food served.

### 💰 Financials, Donations & Credit Chain
Audited financial workflow for foundation funds:
- **Multi-Category Donations** — Split tracking for Masjid, Madrassa, Dispensary, Dasterkhwaan, and General funds.
- **Cash & Goods Contributions** — monetary ledgering and in-kind valuation tracking.
- **Chain of Custody** — Approval flows: Office Boy ➔ Manager ➔ Chairman with credit ledger audit trails.
- **Branded Receipts & Sharing** — A5 PDF receipt generation with WhatsApp integration and Excel export capabilities.

### 👥 Workforce, Payroll & HR
- **Staff Directory** — Employee profiles, contracts, and branch assignments.
- **Payroll Ledger** — Base salary tracking, allowance ledgers, and payment history.
- **Employee Attendance** — Digital timecards and biometric device sync.

---

## ⚡ Technical Architecture

### Offline-First Hybrid Architecture
```text
  [ Local Hive Storage ] ◄─────► [ LAN WebSocket Sync ] ◄─────► [ Firebase Firestore ]
    (Primary Persistence)           (Local Real-time Hub)           (Cloud Global State)
```

- **Primary Persistence**: Hive local storage ensures zero-downtime execution even without internet.
- **LAN Real-time Hub**: WebSockets synchronize clinic and institution devices on the local network.
- **Cloud Source of Truth**: Asynchronous queued sync to Cloud Firestore.

---

## 🛠️ Tech Stack & Dependencies

| Layer | Technology |
|:--|:--|
| **Framework** | Flutter (Dart `^3.10.1`) |
| **Local Persistence** | Hive (NoSQL) |
| **Cloud Backend** | Firebase (Auth, Firestore, Storage) |
| **Auto-Updater** | GitHub Releases API + Inno Setup (`GMWFSetup.iss`) |
| **Security & Devices** | `device_info_plus`, `connectivity_plus`, `network_info_plus` |
| **Networking** | WebSockets (TCP), HTTP, mDNS, UDP |
| **PDF & Printing** | `pdf` + `printing` |
| **UI Components** | FontAwesome Icons, Google Fonts, FL Chart |

---

## 👥 Organizational Roles

| Role | Operational Scope |
|:--|:--|
| **Chairman** | Global executive oversight, donation auditing, financial exports |
| **CEO** | Aggregate branch performance metrics & strategic overview |
| **HQ Manager** | Cross-branch credit ledgers and multi-branch management |
| **Branch Manager** | Localized operations, credit approval, staff transfers |
| **Supervisor** | Inventory approval and request orchestration |
| **Doctor** | Consultation, prescriptions, patient medical records |
| **Receptionist** | Token queue management & patient registration |
| **Dispenser** | Prescription fulfillment & medicine inventory |
| **Teacher / Admin** | Student enrollment, report cards, daily academic logs |
| **Guardian / Parent** | Parent portal for attendance, progress, and student reports |
| **Kitchen Staff** | Dasterkhwaan cooking sessions & pantry stock management |

---

## 📦 How to Build, Package & Publish Releases

### 1. Build Windows Executable
```bash
flutter build windows --release
```

### 2. Compile Inno Setup Installer
Open [GMWFSetup.iss](file:///e:/GMWF/gmwf/GMWFSetup.iss) in Inno Setup Compiler and click **Compile** to generate:
```text
installer/GMWF_Setup_1_2_5.exe
```

### 3. Publish Release on GitHub
1. Go to **GitHub ➔ [`gmwf-1122/GMWF`](https://github.com/gmwf-1122/GMWF) ➔ Releases ➔ Draft a new release**.
2. Tag: `v1.2.5` | Title: `Release v1.2.5`.
3. Attach `GMWF_Setup_1_2_5.exe` to the release assets and publish.
4. All installed client applications will automatically detect the new release and offer one-click updating!

---

## 🗺️ Future Roadmap & Upcoming Updates

- [ ] **School Module Expansion**: Automated class scheduling, grading weightage matrices, and online fee collection ledgers.
- [ ] **Advanced Geo-IP & Subnet Rule Engine**: Configurable organization IP whitelist rules to block unauthorized non-office launches.
- [ ] **LAN Host Auto-Failover**: Dynamic leader election for receptionist LAN WebSocket servers.

---

## 📄 License

© 2026 **Gulzar Madina Welfare Foundation (GMWF)**. All rights reserved.

This software is the exclusive property of GMWF. Unauthorized copying, distribution, or modification is strictly prohibited. See the [LICENSE](LICENSE) file for details.