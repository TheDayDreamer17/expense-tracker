# 💰 Smart Money Manager

A feature-rich personal finance tracker for Android built with Flutter — inspired by Realbyte's Money Manager, with intelligent SMS transaction detection.

## ✨ Key Features

- 📲 **SMS Intelligence** — Auto-detects bank/UPI transaction messages, parses amount, merchant & category, and shows a pre-filled popup
- 📊 **Dashboard** — Balance overview, income vs expense charts, recent transactions
- 💳 **Multi-Account** — Cash, Bank, Credit Card, Loan, Investment
- 📁 **Categories** — Custom income/expense categories with sub-categories
- 💼 **Trip Tracker** — Tag expenses to trips, view per-trip summaries
- 🎯 **Goals** — Savings goals with timeline predictions
- 💳 **Subscriptions** — Track and get alerted on unused subscriptions
- 📈 **Net Worth** — Track assets (FD, MF, Stocks, Gold) vs liabilities
- 🧠 **Health Score** — Financial health score with actionable insights
- 🔔 **Reminders** — Monthly income reminder on 1st of month
- 🎮 **Gamification** — Streaks, badges, monthly summaries
- 🔐 **Security** — PIN + Fingerprint lock
- 💾 **Backup** — Export/import JSON file (save anywhere manually)

## 🛠️ Tech Stack

- **Framework**: Flutter 3.x (Dart)
- **Database**: SQLite via `sqflite`
- **State**: Riverpod
- **Charts**: fl_chart
- **SMS**: telephony + flutter_sms_inbox

## 🚀 Getting Started

```bash
# 1. Install Flutter: https://docs.flutter.dev/get-started/install/windows
# 2. Clone repo
git clone https://github.com/TheDayDreamer17/smart-money-manager.git
cd smart-money-manager/finance_app

# 3. Get dependencies
flutter pub get

# 4. Run on Android device
flutter run
```

## 📁 Project Structure

```
finance_app/
├── lib/
│   ├── core/
│   │   ├── db/          # SQLite database helper
│   │   ├── models/      # Data models
│   │   ├── providers/   # Riverpod state providers
│   │   ├── services/    # SMS, notifications, backup
│   │   └── utils/       # Formatters, helpers
│   └── features/        # Screens by feature
└── android/             # Android-specific (SMS native module)
```

## 📄 License
MIT
