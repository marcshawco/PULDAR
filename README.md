# PULDAR

> **Local-first AI budgeting for people who want speed, clarity, and control.**

PULDAR is an iOS app that turns natural-language money input into structured, categorized transactions in seconds, fully on-device.

Examples:

- `spent 45 at whole foods`
- `grandma gave me 50 for lunch`
- `i put 200 into bitcoin`

No cloud parsing. No latency-heavy round-trips. No waiting.

---

## Why PULDAR

Most budgeting apps force users to manually fill forms, select categories, and fight slow UX. PULDAR removes that friction with:

- **Natural input** instead of form-first data entry
- **On-device AI** for private, low-latency parsing
- **Opinionated bucket budgeting** that is easy to understand at a glance
- **Fast feedback loops** for daily spending decisions

---

## Product Highlights

### AI Expense Capture (On-Device)

- Parses merchant, amount, category, and transaction type from plain English
- Handles credits/reductions (refunds, reimbursements, gifts)
- Includes prompt guardrails for known misclassification patterns (e.g. investments)

### Budgeting That Stays Understandable

- Three core buckets:
  - **Fundamentals** (Needs)
  - **Fun** (Wants)
  - **Future You** (Savings / Debt)
- Presets and custom allocation:
  - `50/30/20`
  - `60/20/20`
  - `Custom`
- Enforced **100% total allocation** before save
- Overspend visibility with direct “Over by $X” signaling

### Dashboard Built for Decisions

- Donut chart modes: `Spent`, `Remaining`, `Breakdown`
- Center KPI emphasis (percent used)
- Per-bucket spend/remaining rows
- Monthly “Remaining This Month” summary
- Free AI usage indicator for clear plan limits

### History That Scales

- Month selector
- Advanced filter/sort sheet:
  - Category
  - Date range
  - Amount range
  - Merchant search
  - Group by day/category/merchant
  - Sort by newest/largest/A-Z
- Inline transaction management with swipe-to-delete

### Settings and Personalization

- Income modes:
  - Monthly
  - Hourly + hours/week (auto monthly estimate)
- Theme controls:
  - System
  - Light
  - Dark
- Custom categories and bucket mapping
- Safe destructive controls (delete-all with confirmation)

---

## Pro Strategy

PULDAR uses a single, simple unlock:

- **PULDAR Pro (Lifetime): $4.99**
- Product ID: `puldar_pro_lifetime`

Pro includes:

- Recurring expenses
- Rollover budgets
- Export and backup features
- Expanded high-usage workflows

Free includes local model download and metered AI entries.

---

## Privacy & Data Principles

PULDAR is built with a local-first architecture:

- LLM parsing is performed **on device**
- Budget math is performed **in app**, not by AI
- Transactions are stored locally with SwiftData
- Lightweight state and feature flags use UserDefaults
- No required backend to use core budgeting features

---

## Performance Engineering

PULDAR is optimized for “instant-feel” interaction.

Implemented optimizations:

1. **Persistent LLM parse cache**
   - Repeated inputs can return instantly
2. **Monthly budget status cache**
   - Avoids recomputing the same month snapshot
3. **Startup model warm-up**
   - Prepares model at launch to reduce first-use delay
4. **Higher MLX cache budget**
   - Improves generation smoothness under active use

This project intentionally favors responsiveness over minimal app footprint.

---

## Technical Architecture

### App Layer

- `ContentView` — root tab shell and service injection
- `DashboardView` — capture, budget state, and recent transactions
- `HistoryView` — analysis, filters, sorting, and entry management
- `SettingsView` — income/allocation/preferences/paywall access

### Domain Services

- `LLMService` — model lifecycle, prompting, generation, parse extraction, parse cache
- `BudgetEngine` — all financial math, allocation, overspend/remaining, monthly cache
- `CategoryManager` — built-in and custom category mapping
- `StoreKitManager` — product load, purchase, entitlement restore/listening
- `UsageTracker` — free-tier usage limits and weekly window logic

### Persistence

- SwiftData models:
  - `Expense`
  - `RecurringExpense`
- UserDefaults:
  - entitlement flags
  - usage counters
  - bucket percentages
  - theme mode
  - export/backup flags
  - model download state

---

## Stack

- **Language/UI:** Swift, SwiftUI
- **Persistence:** SwiftData
- **Monetization:** StoreKit 2
- **On-Device AI:** MLX, MLXLLM, MLXLMCommon, Tokenizers
- **Model:** `mlx-community/Qwen2.5-0.5B-Instruct-4bit`

---

## Getting Started

### Requirements

- macOS with full Xcode installed
- iOS simulator/device target (iOS 18+ recommended)

### Run

1. Open `PULDAR.xcodeproj`
2. Select scheme: `PULDAR`
3. Build and run

### StoreKit Testing

- Config file: `PULDAR/Resources/Products.storekit`
- Expected non-consumable: `puldar_pro_lifetime`

---

## Debug Log Triage

### Usually Simulator/Debug Noise

- `ASDErrorDomain Code=509 "No active account"`
- `App is being debugged, do not track this hang`
- `RTIInputSystemClient ... valid sessionID`
- `UIInputViewSetPlacementInvisible ...`
- `Snapshotting a view ... UIKeyboardImpl`

### Must Investigate

- CoreGraphics `NaN` / non-finite value warnings
- repeated AutoLayout conflicts from app-owned views
- persistence or migration load failures

---

## Quality Checklist

Before release, verify:

- First-launch model flow and warm-start behavior
- Keyboard entry/dismiss UX on every input surface
- Free-tier usage counting and reset windows
- Pro purchase + restore flow
- Overspend/remaining correctness across buckets
- Swipe-to-delete on Home and History
- Hourly income estimate math
- Filter/sort/group consistency in History
- Export/backup gating and unlocked flow

---

## Product Direction

Near-term focus:

- Keep interactions fluid under heavy transaction history
- Improve AI recategorization/edit ergonomics
- Strengthen backup/restore flows for device migration
- Continue reducing input-to-commit latency

---

## Repo Status

This codebase is actively iterated with strong emphasis on:

- Performance
- Clarity of financial state
- Reliable local-first behavior
- High polish iOS UX
