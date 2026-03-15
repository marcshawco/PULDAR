# FinanceKit Integration Plan

This document describes the FinanceKit rollout structure for PULDAR.

## Goal

Allow users to optionally import Apple Wallet financial data into PULDAR while preserving the app's:

- privacy-first positioning
- offline-first behavior
- local budgeting model
- supportability without a central user database

## Eligibility Gating

PULDAR gates FinanceKit behind all of the following:

1. supported iPhone / iOS version
2. FinanceKit framework availability in the toolchain
3. Apple-granted FinanceKit entitlement for the app bundle

If any of those fail, the app must not expose a broken connection flow. Instead it should:

- explain why Apple Wallet sync is unavailable
- keep manual entry, receipt scanning, and CSV/JSON portability as the fallback

## UX Flow

The current user-facing surface is in Settings under `Apple Wallet Sync`.

Planned rollout:

1. user opens Settings
2. app shows current eligibility status
3. user taps `Connect Apple Wallet Accounts` or `Sync Apple Wallet Transactions`
4. if entitlement / API is not available yet:
   - show a clear explanation
   - do not start a dead-end authorization flow
5. if fully available in production:
   - request Apple Wallet authorization
   - preview import counts
   - allow user to confirm import

## Data Model Changes

`Expense` now supports import provenance:

- `source`
- `externalTransactionID`
- `externalAccountID`
- `importedAt`

This allows:

- deduplication across repeated syncs
- distinguishing manual, receipt, and Apple Wallet entries
- preserving provenance in JSON export / backup files

## Sync / Import Architecture

The import pipeline is intentionally split from the authorization layer.

### Authorization Layer

Owned by `FinanceKitManager`.

Responsibilities:

- determine availability
- check entitlement gating
- drive UX state
- eventually request FinanceKit authorization

### Import Layer

Also coordinated by `FinanceKitManager`, but modeled around app-owned transaction snapshots:

- `ImportedTransactionCandidate`
- `ImportPreview`
- `ImportResult`

Responsibilities:

- normalize imported transactions
- deduplicate against existing `Expense.externalTransactionID`
- map imported items into PULDAR expenses
- mark imported source metadata
- save locally through SwiftData

## Conflict / Duplication Strategy

PULDAR should treat Apple Wallet imports as append-or-ignore:

- same `externalTransactionID` => duplicate, do not reinsert
- missing external ID => skip or require fallback normalization rules before import

This keeps repeated syncs safe.

## Fallback Behavior

If FinanceKit is unavailable, PULDAR should continue offering:

- manual text entry
- receipt scanning
- CSV export
- JSON export / backup
- local budgeting and widget flows

The app should never lock core budgeting behind FinanceKit availability.

## Diagnostics

FinanceKit-related failures should be logged only through the optional local diagnostics system.

Recommended categories:

- `financekit.availability`
- `financekit.authorization`
- `financekit.sync`
- `financekit.import`

These logs stay on-device unless the user explicitly exports them.
