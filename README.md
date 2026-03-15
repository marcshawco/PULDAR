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
- rollover budgeting for Pro users
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
- export support in both:
  - `CSV`
  - `JSON`
- full device backup in JSON

### Local Support Tooling

- optional on-device diagnostic logs
- disabled by default
- user can export logs manually when support is needed
- no automatic upload

---

## Pricing Model

PULDAR uses a trial-first subscription model:

- **14-day free trial**
- **$4.99/month**
- **$49.99/year**

Product IDs:

- `puldar_pro_monthly`
- `puldar_pro_yearly`

Users who decline the trial still get a restricted freemium experience.

### Pro Includes

- unlimited entries
- recurring expenses
- rollover budgets
- full export workflows
- higher-usage budgeting workflows

### Free Includes

- onboarding
- on-device model download
- limited AI-powered entries
- manual budgeting flow
- restricted but usable core experience

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

---

## Diagnostics and Support

Because PULDAR does not rely on a central user database, support tooling is built into the app:

- optional local diagnostic logging
- exportable diagnostics bundle
- current budget state included in diagnostics export
- user-controlled sharing flow

This helps investigate issues like:

- incorrect budget math
- unexpected subscription state
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
- `PaywallView` — trial-first subscription UI
- `AppOnboardingView` — first-run onboarding

### Core Services

- `LLMService` — model lifecycle, prompting, parse extraction, parse cache
- `BudgetEngine` — financial math, allocation, rollover, cached month state
- `CategoryManager` — canonical/custom category mapping
- `StoreKitManager` — subscriptions, restore, entitlement listening
- `UsageTracker` — free-tier usage tracking
- `DiagnosticLogger` — optional local support logging
- `WidgetBudgetSnapshotStore` — widget snapshot publishing

### Persistence

- SwiftData:
  - `Expense`
  - `RecurringExpense`
- UserDefaults / iCloud KVS:
  - usage state
  - theme
  - allocation settings
  - diagnostics preference
  - category settings

---

## Apple Frameworks and Stack

- **UI:** SwiftUI
- **Persistence:** SwiftData
- **Subscriptions:** StoreKit 2
- **Widgets:** WidgetKit
- **Receipt OCR / scan:** Vision + VisionKit
- **Cloud sync:** CloudKit + NSUbiquitousKeyValueStore
- **On-device AI:** MLX, MLXLLM, MLXLMCommon, Tokenizers
- **Model:** `mlx-community/Qwen2.5-0.5B-Instruct-4bit`

---

## Getting Started

### Requirements

- macOS with full Xcode installed
- iOS target with modern SwiftUI / SwiftData support
- iOS 18+ recommended for the current app experience

### Run

1. Open [PULDAR.xcodeproj](/Users/astral/Documents/PROJECTS/XCODE/PULDAR/PULDAR.xcodeproj)
2. Select the `PULDAR` scheme
3. Build and run

### StoreKit Testing

- local config: `PULDAR/Resources/Products.storekit`
- expected products:
  - `puldar_pro_monthly`
  - `puldar_pro_yearly`

Note: actual introductory trial behavior still needs to be configured in App Store Connect / Xcode StoreKit configuration, not just in app copy.

### iCloud / CloudKit

To test cross-device sync on real devices, make sure:

- the bundle has the correct iCloud capability
- CloudKit is enabled in signing/capabilities
- the correct iCloud container is provisioned for the app

---

## Known Development Notes

### Usually Harmless During Local Debugging

- `ASDErrorDomain Code=509 "No active account"`
- `App is being debugged, do not track this hang`
- `Message from debugger: killed`

These are usually simulator/debugger environment messages rather than app logic failures.

### Areas Worth Validating Before Release

- onboarding → paywall → freemium fallback
- monthly and yearly subscription purchase flow
- restore purchases
- widget rendering and refresh timing
- receipt scanning on real receipts
- multi-device iCloud sync behavior
- CSV / JSON export output
- diagnostic export flow

---

## Current Product Direction

Near-term priorities:

- keep expense capture fast and trustworthy
- keep budgeting understandable at a glance
- improve multi-device reliability
- make support feasible without compromising privacy
- strengthen the daily-use loop with widgets and smooth capture UX
