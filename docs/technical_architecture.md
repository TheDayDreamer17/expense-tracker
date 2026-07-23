# 🪐 Orbit: Technical Architecture & Debugging Guide

This document describes the technical architecture of the **Orbit** personal finance tracking application. It details directory structures, SQLite schemas, the native-to-flutter SMS transaction parsing engine, state management, AI helper systems, and concrete debugging recommendations.

---

## 📂 Project Directory Structure

Orbit follows a hybrid structure of clean architecture layers combined with feature-sliced modules:

```text
lib/
├── main.dart                 # Application entry point, configures app-level observers
├── app.dart                  # Core MaterialApp configuration and global shell/navigation layout
├── core/                     # Shared cross-cutting concerns
│   ├── db/                   # SQLite database configurations (DatabaseHelper)
│   ├── models/               # Domain data models (Transaction, Account, Category, etc.)
│   ├── providers/            # Shared Riverpod providers (Settings, Theme, Refresh triggers)
│   ├── services/             # Core platform and network utilities (AI, Notifications, SMS Methods)
│   └── utils/                # UI formatting, themes, regex rules (SmsParser, AppTheme)
├── features/                 # Modular, feature-sliced screens and business logic
│   ├── accounts/             # Account configuration, credit card setup
│   ├── auth/                 # Pin screen, biometric verification UI
│   ├── budget/               # Budgets and threshold tracking
│   ├── copilot/              # AI conversation panel
│   ├── dashboard/            # Home metrics, warning bars, action buttons
│   ├── goals/                # Savings goals & systematic bifurcation
│   ├── health_score/         # Debt ratios and financial score rules
│   ├── networth/             # FD, Mutual Funds, Stocks ledger
│   ├── reports/              # Visual spending distributions (fl_chart)
│   ├── settings/             # Backup triggers, provider API settings
│   ├── subscriptions/        # Active subscriptions and unused trackers
│   ├── transactions/         # Manual transaction entries
│   └── trips/                # Trip list and sub-budget trackers
└── widgets/                  # Shared UI widgets (custom cards, inputs, dialogs)
```

---

## 🗄️ Database Schemas & Seed Data

The app utilizes a local SQLite database (`sqflite` package) named `finance_app.db` (version 3) to persist data. Foreign key constraints are enforced with `PRAGMA foreign_keys = ON` on configuration.

### Tables Schema

| Table Name | Primary Key | Description | Relationships / Foreign Keys |
| :--- | :--- | :--- | :--- |
| `accounts` | `id` (TEXT) | Holds asset accounts (CASH, BANK, INVESTMENT) and credit cards (CREDIT_CARD). Includes columns for limits, payments, statement cycles. | None |
| `categories` | `id` (TEXT) | Seeded hierarchical category taxonomy (EXPENSE, INCOME, TRANSFER). | `parent_id` references `categories(id)` |
| `transactions` | `id` (TEXT) | Core transaction ledger entries (amount, type, date, notes, templates, recurrence rules). Includes columns tracking raw SMS data. | `account_id` -> `accounts(id)` <br> `category_id` -> `categories(id)` <br> `trip_id` -> `trips(id)` |
| `audit_logs` | `id` (TEXT) | Tracks modifications made to transactions for auditability. | `transaction_id` -> `transactions(id)` |
| `budgets` | `id` (TEXT) | Monthly budget target limits per category. | `category_id` -> `categories(id)` |
| `trips` | `id` (TEXT) | Trackable travel containers for grouping specific transaction expenses. | None |
| `goals` | `id` (TEXT) | Specific savings targets (SIP metrics, current vs target values). | None |
| `subscriptions`| `id` (TEXT) | Active subscriptions (amount, billing cycle, last used timestamp). | None |
| `net_worth_entries`| `id` (TEXT) | Manual logs for Stocks, Mutual Funds, Gold, and FDs. | None |
| `streaks` | `id` (TEXT) | Gamification counters (NO_SPEND, SAVING streaks). | None |
| `badges` | `id` (TEXT) | List of unlocked awards with timestamps. | None |
| `settings` | `key` (TEXT) | Flat key-value table storing basic app state and choices. | None |

> [!NOTE]
> Standard categories (like `cat_food`, `cat_grocery`, `cat_utilities`) are automatically pre-seeded inside `DatabaseHelper.getStandardCategories()` upon the initial SQLite configuration.

---

## 📲 Native SMS Parsing Architecture

The automatic parsing of SMS messages combines a background native Android receiver and a Flutter-side event pipeline.

### Android Native Layer (Kotlin)
- **`SmsReceiver.kt`**: Listens for the `android.provider.Telephony.SMS_RECEIVED` broadcast.
  - When an incoming SMS is caught, it passes the text body, sender ID, and timestamp to `SmsParser.parse()`.
  - If a transaction is parsed, it writes the transaction to a local **Room Database** (`AppDatabase.kt` / `SmsTransactionDao.kt`).
  - It triggers a system tray notification so the user can easily open the app directly.
  - It writes to the active `EventChannel` stream to trigger updates immediately if the application is running in the foreground.
- **`SmsParser.kt`**: Extracts key metrics using pre-defined regular expressions matching transaction styles of Indian banking systems:
  - **Amount**: `(?:Rs\.?|INR|₹)\s?([\d,]+\.?\d*)`
  - **Debit**: `\b(debited|debit|spent|paid|withdrawn|purchase|payment)\b`
  - **Credit**: `\b(credited|credit|received|deposited|refund|cashback)\b`
  - **Account suffix**: `(?:a/c|acct|account|card|ac)(?:\s+no\.?|\s+num\.?|\s+number)?[\s\*xX]*(\d{3,4})`
  - **Merchant**: Extracted using preposition bounds like "at", "to", "towards" and checked against standard category keyword lists.

### Communication Bridges (Channels)
- **MethodChannel** (`com.example.finance_app/sms_methods`): 
  - `getTransactions`: Fetches all transactions parsed natively.
  - `getRecentTransactions`: Fetches recent transactions (limited size).
  - `deleteTransaction`: Deletes a transaction from the native database.
  - `scanInbox`: Initiates a query on the Android content provider to search historical inbox messages for transaction notifications.
  - `saveBackupToDownloads`: Invokes Android platform IO to dump database states directly into the user's Downloads directory.
- **EventChannel** (`com.example.finance_app/sms_events`):
  - Streams real-time parsed transaction objects to the foreground Dart stream when an SMS arrives.

### Flutter Parsing Layer (Dart)
- **`sms_parser.dart`**: Implements matching logic identical to `SmsParser.kt` for parsing inbox dumps fetched via MethodChannel scans.

---

## 🧠 State Management & AI Copilot

### State Architecture
Orbit uses **Riverpod** for application state:
- **`settingsProvider`**: A `NotifierProvider` storing configuration values (biometrics, API credentials, default accounts). Saves states directly into the SQLite `settings` table or `SharedPreferences`.
- **`themeModeProvider`**: Listens to settings adjustments to swap light and dark visual themes.
- **`refreshProvider`**: An integer state incremented to force database refreshes across dashboards when transactions are added or removed.

### AI Financial Assistant (`AiService`)
- **System Prompt**: Defines Orbit as a helpful financial co-pilot with local context access.
- **History Compilation**: Before shipping prompt requests, the service queries SQLite for all account balances and formatting logs of the user's last 60 days of transactions into a concise Markdown summary.
- **API Payloads**: Sends request maps directly to endpoint providers. Supported providers and model mapping logic:
  - **Gemini**: Integrates using `google_generative_ai` packages (`gemini-1.5-flash`).
  - **OpenAI**: Sends payload maps via standard REST clients to `https://api.openai.com/v1/chat/completures` (`gpt-4o-mini`).
  - **Anthropic**: Rest payloads to `https://api.anthropic.com/v1/messages` (`claude-3-5-sonnet-20240620`).
  - **Custom Endpoints**: Allows customized server addresses and request templates.

---

## 🔄 Automated Backup Lifecycle
Orbit contains a self-triggering automated backup loop built into database insert/update/delete wrapper endpoints.
1. **Trigger**: Any modification on SQLite tables via `DatabaseHelper` calls `_triggerAutoBackup()`.
2. **Debounce**: A 5-second delay is initialized. If multiple modifications occur consecutively, the delay resets, debouncing operations.
3. **Serialization**: The system queries all tables and maps them into a single consolidated JSON structure.
4. **Platform Execution**: Calls `saveBackupToDownloads` over the method channel to dump the JSON string into `orbit_backup.json` inside the device's public Downloads directory.

---

## 🛠️ Debugging & Troubleshooting Guide

When debugging features or fixing issues, consult this list of recommendations:

### 1. Simulating SMS Transactions (Emulator testing)
To test SMS parsing on an emulator, use the Android Debug Bridge (ADB) to inject SMS broadcasts:
```bash
adb shell am broadcast -a android.provider.Telephony.SMS_RECEIVED --es "pdus" "07919132050031f00b919132547698f00000000000000000210a040b0c0d0e0f074465617220437573746f6d65722c204163637420585839303720697320646562697465642077697468205273203432352e3030206f6e2030352d4a756e2d323620746f7761726473205a6f6d61746f2e"
```
Alternatively, log in to the emulator's control panel via telnet and run:
```bash
sms send +1234567890 "Dear Customer, Acct XX907 is debited with Rs 425.00 on 05-Jun-26 towards Zomato. UPI:071908363245"
```

### 2. Inspecting the Local Database
To view active tables and run SQL statements during runtimes:
- Connect the device to Android Studio.
- Open the **App Inspection** tab on the bottom toolbar.
- Select the running package name (`com.example.finance_app`).
- Select the `finance_app.db` SQLite database to view table structures, schemas, and live rows.

### 3. Debugging Method Channel issues
If platform channels are failing or throwing `MissingPluginException`:
- Verify that the channel names (`com.example.finance_app/sms_methods` and `com.example.finance_app/sms_events`) match exactly in Dart and Kotlin.
- Ensure that the binary execution loops match. Stop the application, clean the build cache using `flutter clean`, run `flutter pub get`, and rebuild the application onto the target hardware.

### 4. Adjusting Verbose Log Filters
Inspect native log messages inside Android Studio Logcat or by running:
```bash
adb logcat -s OrbitSMS:V FlutterActivity:I
```
This filters for incoming SMS listener reports and parsing exceptions on the native Kotlin end.
