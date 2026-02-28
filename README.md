# PULDAR

PULDAR is an iOS-first, on-device budgeting app that turns natural language into categorized expenses.

Example input:

- `spent 45 at whole foods`
- `grandma gave me 50 for lunch`
- `I put 200 into bitcoin`

The app parses the input locally using an on-device LLM, assigns merchant + amount + category + budget bucket, and updates monthly budget progress instantly.

---

## Core Product Goals

- Fast local-first expense capture
- Zero cloud dependency for parsing and budget math
- Clear monthly bucket budgeting (`Fundamentals`, `Fun`, `Future You`)
- Free tier with upgrade to Pro for power features

---

## Feature Set

### 1) Dashboard (Home)

- Donut chart with toggle modes:
  - `Spent`
  - `Remaining`
  - `Breakdown`
- Center stat focus (e.g., `Used 83%`)
- Bucket rows with:
  - Spent vs budget
  - Left amount
  - Overspend highlight + `Over by $X` badge
- Monthly summary row:
  - `Remaining This Month` when funds are available
  - Overspent state handling when above total monthly capacity
- AI input counter:
  - Weekly free AI usage indicator (`X free AI entries left`)

### 2) Natural Language Expense Input

- On-device LLM parsing to JSON:
  - merchant
  - amount
  - category
  - transaction type (`expense` or `credit`)
- Investment-aware prompt behavior:
  - terms like `bitcoin`, `btc`, `S&P500`, `ETF`, `stock` map to investment-style categories
- Credit/reduction support:
  - refunds/gifts/reimbursements can reduce spent totals

### 3) Budget Engine

- Pure Swift budget math (no AI math)
- Bucket percentage allocations with presets:
  - `50/30/20`
  - `60/20/20`
  - `Custom`
- 100% allocation enforcement on save
- Monthly overspend detection
- Optional rollover logic (Pro-gated)
- Variable income support:
  - static monthly income
  - hourly pay + hours/week derived monthly estimate
  - income transactions for month-specific variance

### 4) History

- Month selector
- Filter + sort sheet (clean main screen):
  - Category
  - Date range
  - Min/max amount
  - Merchant search
  - Group by: day / category / merchant
  - Sort by: newest / largest / A-Z
- Compact summary card + entries list
- Swipe-to-delete transactions
- Edit transaction support

### 5) Settings

- Income mode: monthly or hourly
- Bucket slider allocation + live dollar values
- Appearance mode:
  - System Default
  - Light
  - Dark
- Custom category management (add/edit bucket assignment)
- Pro gating sections (single upgrade path):
  - recurring expenses
  - rollover budgets
  - exports
  - local backup/export
- Danger zone:
  - delete all expenses with confirmation

### 6) Paywall / Monetization

- Lifetime Pro unlock: `$4.99`
- Product ID: `puldar_pro_lifetime`
- Free plan includes model download + limited AI entries
- Pro unlock adds:
  - unlimited entries flow
  - recurring expenses
  - rollover budgets
  - export/backup features

---

## Privacy Model

- Expense parsing runs on-device (MLX/Qwen local model)
- Core data storage is local (SwiftData)
- Local settings/counters stored in `UserDefaults`
- No required cloud roundtrip for parsing/budget calculations

---

## Technical Architecture

### UI Layer (SwiftUI)

- `ContentView` hosts tab shell + root services in environment
- `DashboardView` handles capture, budget progress, and recent transactions
- `HistoryView` handles historical analysis and management
- `SettingsView` handles income/budget preferences, paywall entry points, and app controls

### Domain Services

- `LLMService`
  - model lifecycle
  - prompt construction
  - token generation + JSON extraction
  - parse caching
- `BudgetEngine`
  - income resolution
  - bucket allocation
  - overspend/remaining computation
  - monthly status caching
- `CategoryManager`
  - built-in + custom category display mapping
- `StoreKitManager`
  - product loading
  - purchase flow
  - entitlement restoration/listening
- `UsageTracker`
  - weekly free usage window + remaining count

### Persistence

- SwiftData models:
  - `Expense`
  - `RecurringExpense`
- Lightweight app state (`UserDefaults`):
  - entitlement flags
  - usage counters
  - slider percentages
  - theme mode
  - auto-export markers
  - model download flags

---

## Performance Strategy (Snappy UX)

PULDAR intentionally favors local caching and warm startup behavior.

### Implemented speed-ups

1. **Persistent LLM parse cache**
- Repeated/near-identical natural-language inputs can return instantly
- Stored in `UserDefaults` with bounded cache size

2. **Monthly budget status cache**
- Reuses computed bucket status snapshots for the same month/dataset
- Invalidates when relevant financial settings change

3. **Startup model warm-up**
- Model load kicks off on app launch (one-time per launch)
- Reduces first input latency

4. **Higher MLX GPU cache budget**
- Increased local MLX cache limit for smoother generation path
- App size/memory tradeoff intentionally accepted for responsiveness

---

## On-Device LLM Details

- Model ID: `mlx-community/Qwen2.5-0.5B-Instruct-4bit`
- Frameworks:
  - `MLX`
  - `MLXLLM`
  - `MLXLMCommon`
  - `Tokenizers`
- Strict JSON output contract parsed into `LLMExpenseResult`
- Regex fallback path for malformed model output

---

## Build & Run

### Requirements

- macOS with full Xcode installed (not only Command Line Tools)
- iOS 18+ target environment (recommended)
- Apple ID/test setup for StoreKit testing if validating purchase flows

### Run locally

1. Open `PULDAR.xcodeproj` in Xcode
2. Select `PULDAR` scheme
3. Run on simulator or device

### StoreKit testing

- StoreKit config file: `PULDAR/Resources/Products.storekit`
- Product expected: `puldar_pro_lifetime`

---

## Common Debug Logs (What to Ignore vs Fix)

### Usually benign in simulator/debug

- `ASDErrorDomain Code=509 "No active account"`
  - StoreKit environment/account issue in simulator; not necessarily app logic failure
- `App is being debugged, do not track this hang`
  - profiler/debugger noise marker
- `RTIInputSystemClient ... valid sessionID`
- `UIInputViewSetPlacementInvisible ...`
- `Snapshotting a view ... UIKeyboardImpl`

These frequently appear during keyboard and debug sessions. Prioritize user-visible behavior over raw simulator log noise.

### Must fix when seen

- `NaN` / non-finite CoreGraphics warnings from app math/layout
- persistent AutoLayout constraint conflicts in app-owned UI
- failed persistence saves / migration errors

---

## Migration & Data Safety

- App includes recovery logic for known SwiftData migration validation failures
- On unrecoverable `NSCocoaErrorDomain 134110` migration path, store reset fallback is in place to recover app boot
- Export/backup features are provided to reduce data-loss risk across device changes

---

## UX Standards in This Project

- Immediate feedback on financial state changes
- Clear visual overspend signaling
- Frictionless edit/delete for bad AI parses
- Keyboard handling should never trap the user
- History should prioritize entries visibility over heavy controls

---

## Suggested QA Checklist

- First-launch model flow (with/without Wi-Fi)
- Warm-start launch speed
- First keyboard open latency
- Free-tier decrement/reset behavior
- Pro unlock + restore purchases
- Overspent and remaining math correctness
- Swipe-to-delete in both Home recent list and History list
- Hourly income conversion (`hourly * hours/week * 52 / 12`)
- History filters/sorts/grouping consistency
- Export gating and unlocked export path

---

## Project Status

Active iteration with heavy product/UX tuning. Performance, keyboard flow, and visual clarity are treated as release-critical.
