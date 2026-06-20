# 🪐 Orbit

A premium, feature-rich personal finance tracking and budgeting application for Android, built with **Flutter**, **Riverpod**, and **SQLite**. Inspired by Realbyte\'s Money Manager, it is supercharged with native SMS transaction auto-detection, customizable AI financial advisory, and automated savings calculators.

---

## ✨ Core Features Explained

### 1. 📲 SMS Intelligence & Automated Transaction Parsing
- **Auto-Parsing Engine**: Detects incoming transaction SMS texts from Indian banks (SBI, HDFC, ICICI, Axis, PNB, Paytm, etc.). It extracts the transaction amount, type (Debit vs. Credit), card/account identification, and merchant name.
- **Smart Bottom Sheet**: Automatically prompts a pre-filled transaction verification sheet immediately after transaction detection for seamless manual override and saving.
- **Self-Learning Merchant Mapping**: Learns from manual re-categorizations. For example, if you change a transaction merchant `Zomato` to the `Food & Dining` category, future Zomato transactions will automatically pre-select `Food & Dining`.
- **Missing Card Auto-Creation**: If an SMS transaction belongs to a credit card not registered in the app, it prompts a dialog asking to create it with custom name-editing. Includes a 5-time decline threshold, after which the card prompt is ignored.

### 2. 💳 Accounts & Credit Card Separation
- **Visual Distinction**: The Dashboard splits liquid wealth from card liabilities:
  - **Standard Accounts**: Cash, Bank, and Investment accounts display positive active balances.
  - **Credit Cards**: Displays card details, **Outstanding Balance**, **Available Limit**, and a visual progress bar indicating card limit utilization.
- **Suffix Account Mapping**: Link specific physical accounts to unique 3-4 digit suffixes (e.g., `907` for ICICI, `2063` for Axis) under Account Settings. The SMS engine uses this mapping to resolve transactions directly to the correct account.
- **Custom Spending Warning Limits**: Set custom outstanding balance warning limits on credit cards. If manual transaction logging or incoming SMS parsing pushes outstanding card balances past this threshold, the app triggers a warning popup before saving.

### 3. 📂 Hierarchical Category Trees & Deletion Panels
- **Nested Category Structure**: Seeded parent-child categories (e.g., Parent `⚡ Utilities` has children `Electricity`, `Water`, `Internet/WiFi`, `Mobile Recharge`).
- **Category Budget Warning**: Warns the user with a confirmation prompt when an expense pushes monthly category spending past 80% of its set budget limit.
- **Safe Deletion Panel**: A category manager in settings allows deleting categories. To avoid database foreign-key constraint failures, it safely updates all historical transactions in that category to fallback buckets (`Miscellaneous / Other Expense` or `Other Income`) prior to record deletion.

### 4. 🧠 Conversational AI Financial Copilot
- **Financial History Context**: Offers a private AI chat copilot with access to your account balances and your last 60 days of transactional history.
- **Predictive Monthly Budget Alerts**: Mathematical burn-rate calculation projects monthly spend against user-set limits and calls the AI to generate a descriptive insight alert (warning or encouragement).
- **Customizable AI Settings**: Change AI settings inside a custom bottom sheet modal in Settings:
  - **AI Provider Support**: Switch between **Google Gemini**, **OpenAI**, **Anthropic**, or a **Custom API Endpoint** (e.g., local Ollama / Local AI endpoints).
  - **Auto-Configuring Model Parameters**: Tapping a provider auto-populates optimal default models (`gemini-1.5-flash` for Gemini, `gpt-4o-mini` for OpenAI, `claude-3-5-sonnet-20240620` for Anthropic, and `default` for Custom).
  - **Custom Endpoints**: Allows setting a custom backend URL and custom auth keys.

### 5. 🎯 Money Bifurcation Splits & Savings Calculators
- **Split Allocation Guide**: Visualizes wealth bifurcation splits such as **50/30/20 Rule** (Standard), **70/20/10 Rule** (Aggressive/Tight), or **Custom Split** configurations. Enter a monthly income to dynamically see allocations and a stacked color-coded bar chart.
- **Monthly Bifurcation Reminders**: Let users toggle recurring reminders on the 1st of every month to allocate their funds.
- **SIP / Savings Goal Calculator**: Calculates the monthly SIP required to reach a specific target savings amount at a given annual interest rate over a chosen month duration. Easily save calculation results directly as active savings goals with pre-filled parameters.
- **Emergency Fund Calculator**: Automatically calculates average monthly expenses from your real SQLite database history, computes a 3-12 months emergency fund recommendation, and allows creating a target emergency goal with a single tap.

### 6. 🔄 Subscriptions Alerts & Top Actions
- **Dashboard Alert Bar**: Displays subscription payment notifications prominently on the Dashboard home page 5/4/3/2/1 days before expiration with a direct 'Pay Now' action.
- **Unused Subscription Detection**: Highlights subscriptions that have not registered transaction charges recently, encouraging users to cancel wasted plans.

### 7. 📈 Net Worth, Trips & Financial Health Score
- **Trip Tracker**: Groups travel expenses and provides per-trip budget statistics.
- **Financial Health Score**: Scores user status (0-100) based on metrics like savings rate, emergency buffer size, and active debt ratios, providing concrete improvement guides.
- **Investment Promo Popups**: Increments app launches in SharedPreferences. On the 3rd app launch, it displays a feature promo dialog prompting the user to log their FD, Mutual Fund, Gold, and Stock assets under Net Worth records.

---

## 🛠️ Tech Stack & Architecture

- **Frontend Framework**: Flutter 3.x (Dart)
- **State Management**: Riverpod (Notifier & Providers)
- **Local Database**: SQLite (`sqflite`)
- **Visualizations & Charts**: `fl_chart`
- **SMS Listeners**: Native Android receiver + `telephony`
- **Animation System**: `flutter_animate` (fade-ins, sliding actions)
- **AI Integrations**: `http` REST client payloads supporting custom models + `google_generative_ai`

---

## 🚀 Getting Started

### Prerequisites
- Install Flutter SDK: [flutter.dev/get-started](https://flutter.dev/get-started)
- Android SDK installed (API level 21+)

### Installation & Run

1. Clone this repository:
   ```bash
   git clone https://github.com/TheDayDreamer17/smart-money-manager.git
   ```
2. Navigate to the project directory:
   ```bash
   cd smart-money-manager/finance_app
   ```
3. Get Flutter dependencies:
   ```bash
   flutter pub get
   ```
4. Connect an Android device (with developer mode enabled) or emulator, and run the project:
   ```bash
   flutter run
   ```

---

## 📄 License
This project is licensed under the MIT License.
