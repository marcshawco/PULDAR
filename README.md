# PULDAR

> **Offline-first budgeting for people who want speed, privacy, and daily clarity.**

PULDAR is a native iOS budgeting app that turns plain-English expense entry and receipt scans into structured transactions on-device. It combines fast capture, simple budget allocation, local-first storage, and optional privacy-friendly support tooling.

Examples:

- `spent 45 at whole foods`
- `mom sent me 200`
- `paid 176 for insurance`

No form-heavy flow. No required backend. No cloud AI parsing.

---

## What PULDAR Does

PULDAR is built around three jobs:

1. **Capture spending quickly**
   - plain-English input
   - receipt scanning with Apple camera/document scanning + OCR
   - merchant/category cleanup on-device

2. **Keep budgets understandable**
   - three budget groups:
     - **Fundamentals** for needs
     - **Fun** for wants
     - **Future** for savings and debt
   - allocation presets:
     - `50/30/20`
     - `60/20/20`
     - `Custom`

3. **Keep users engaged daily**
   - dashboard with bucket balances
   - Home Screen widgets for remaining balances
   - history filters and exports

---

## Product Highlights

### On-Device AI Capture

- parses merchant, amount, category, and transaction type from natural text
- supports receipt scanning with Vision/VisionKit OCR
- improves merchant and total extraction for real receipts
- keeps parsing local to the device

### Clear Budgeting Model

- three-budget system:
  - **Fundamentals**
  - **Fun**
  - **Future**
- monthly income setup:
  - direct monthly income
  - hourly pay + hours/week estimate
- enforced `100%` allocation before saving
- recurring expenses and rollover budgeting included for everyone
- overspend and remaining-state visibility

### Daily Utility

- donut chart views for:
  - `Spent`
  - `Remaining`
  - `Breakdown`
- bucket progress rows
- monthly remaining summary
- Home Screen widget support for glanceable balances

### History and Data Portability

- month-based history view
- category, merchant, date, amount, grouping, and sort filters
- entry export support in both:
  - `CSV`
  - `JSON`
- settings-level snapshot and all-data exports in JSON
- optional automatic monthly CSV export
- full device backup in JSON

### Apple Wallet Import Readiness

- FinanceKit-ready scaffolding for Apple Wallet account import
- explicit eligibility gating for:
  - supported iPhone / iOS
  - FinanceKit framework availability
  - Apple-granted entitlement
- import provenance stored on expenses:
  - source
  - external transaction ID
  - external account ID
  - imported timestamp
- duplicate protection for repeated imports
- graceful fallback to manual entry, receipt scan, and export/import flows when FinanceKit is unavailable

### Local Support Tooling

- optional on-device diagnostic logs
- disabled by default
- user can export logs manually when support is needed
- no automatic upload

---

## Access Model

PULDAR is currently free to the public.

- no paywall
- no trial
- no subscription purchase flow
- no usage cap on AI-powered entries

### Included For Everyone

- unlimited plain-English entries
- receipt scanning
- recurring expenses
- rollover budgets
- CSV / JSON exports
- full JSON backup
- widgets
- optional local diagnostics export

---

## Privacy and AI Boundary

PULDAR is intentionally local-first:

- transaction parsing happens **on-device**
- budget math happens in app code, **not** in the AI
- core data is stored locally with SwiftData
- lightweight state is stored with UserDefaults / iCloud key-value sync where appropriate

### Important Disclaimer

PULDAR is **not financial advice**.

Its AI is used strictly for:

- parsing receipt text
- parsing plain-English expense input
- categorizing transactions

It is **not** used to provide:

- investment recommendations
- debt payoff strategies
- portfolio advice
- financial planning advice

This boundary is intentional for both product clarity and legal safety.

---

## Sync and Multi-Device Behavior

PULDAR is designed to stay local-first while still supporting multi-device use:

- SwiftData data attempts to sync through CloudKit when available
- local fallback is used if CloudKit is unavailable
- budget settings and category customizations sync through iCloud key-value storage
- conflict handling uses timestamp-based last-write-wins for synced settings
- sync writes are debounced for efficiency

Current sync-related surfaces include:

- expenses
- recurring expenses
- monthly income
- rollover preference
- budget allocation percentages
- custom categories
- renamed categories

### Apple Wallet Import Fallback

When FinanceKit is unavailable or not yet approved for the app bundle, PULDAR falls back cleanly to:

- manual text entry
- receipt scanning
- CSV export/import workflows
- JSON export/backup workflows

This keeps the core product usable without forcing a third-party bank aggregator.

---

## Diagnostics and Support

Because PULDAR does not rely on a central user database, support tooling is built into the app:

- optional local diagnostic logging
- exportable diagnostics bundle
- current budget state included in diagnostics export
- user-controlled sharing flow

This helps investigate issues like:

- incorrect budget math
- sync or configuration issues
- export failures
- recurring expense issues

without collecting user data by default.

---

## Technical Architecture

### Main Views

- `ContentView` — root shell, dependency injection, onboarding presentation
- `DashboardView` — capture flow, budget state, recent transactions
- `HistoryView` — filtering, grouping, exporting, deletion
- `SettingsView` — income, allocation, diagnostics, export, personalization
- `PaywallView` — legacy compatibility screen that now explains everything is included
- `AppOnboardingView` — first-run onboarding

### Core Services

- `LLMService` — model lifecycle, prompting, parse extraction, parse cache
- `BudgetEngine` — financial math, allocation, rollover, cached month state
- `CategoryManager` — canonical/custom category mapping
- `FinanceKitManager` — Apple Wallet import gating, import preview, deduplication scaffolding, fallback messaging
- `StoreKitManager` — legacy compatibility placeholder; no live purchase flow
- `UsageTracker` — legacy compatibility placeholder; entries are unlimited
- `DiagnosticLogger` — optional local support logging
- `WidgetBudgetSnapshotStore` — widget snapshot publishing

### Persistence

- SwiftData:
  - `Expense`
  - `RecurringExpense`
- UserDefaults / iCloud KVS:
  - theme
  - budget and allocation settings
  - diagnostics preference
  - category settings

---

## Apple Frameworks and Stack

- **UI:** SwiftUI
- **Persistence:** SwiftData
- **Widgets:** WidgetKit
- **Receipt OCR / scan:** Vision + VisionKit
- **Apple Wallet import:** FinanceKit-ready scaffolding
- **Cloud sync:** CloudKit + NSUbiquitousKeyValueStore
- **On-device AI:** MLX, MLXLLM, MLXLMCommon, Tokenizers
- **Model:** `mlx-community/Qwen2.5-0.5B-Instruct-4bit`

---

## Getting Started

### Requirements

- macOS with full Xcode installed
- iOS Simulator or iPhone running iOS 17.6 or later
- modern SwiftUI / SwiftData support

### Run

1. Open `PULDAR.xcodeproj`
2. Select the `PULDAR` scheme
3. Build and run

### Legacy StoreKit Config

- `PULDAR/Resources/Products.storekit` is intentionally empty.
- The file remains in the repo only as a compatibility artifact while all features stay unlocked.

### iCloud / CloudKit

To test cross-device sync on real devices, make sure:

- the bundle has the correct iCloud capability
- CloudKit is enabled in signing/capabilities
- the correct iCloud container is provisioned for the app

### FinanceKit / Apple Wallet Import

PULDAR now includes the product and data-model groundwork for Apple Wallet transaction import, but live account authorization still depends on Apple approving the FinanceKit entitlement for the production bundle.

Until that entitlement is active, the app will:

- show Apple Wallet sync status in Settings
- explain why live connection is unavailable
- preserve manual entry, receipt scanning, and export/import fallbacks

---

## Known Development Notes

### Usually Harmless During Local Debugging

- `ASDErrorDomain Code=509 "No active account"`
- `App is being debugged, do not track this hang`
- `Message from debugger: killed`

These are usually simulator/debugger environment messages rather than app logic failures.

### Areas Worth Validating Before Release

- onboarding and local model download flow
- recurring expense creation, toggling, deletion, and dashboard suggestions
- rollover math across month boundaries
- Apple Wallet eligibility and fallback messaging
- FinanceKit import deduplication once entitlement access is granted
- widget rendering and refresh timing
- receipt scanning on real receipts
- multi-device iCloud sync behavior
- CSV / JSON export output, including current-month snapshot contents
- diagnostic export flow

---

## Current Product Direction

Near-term priorities:

- keep expense capture fast and trustworthy
- keep budgeting understandable at a glance
- keep every core feature available without access gating
- improve multi-device reliability
- prepare Apple Wallet import without compromising privacy or fallback usability
- make support feasible without compromising privacy
- strengthen the daily-use loop with widgets and smooth capture UX
