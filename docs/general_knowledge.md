# 🪐 Orbit: General Knowledge & Feature Guide

Welcome to the Orbit general knowledge guide. This document provides a user-centric description of the application's features, workflows, and core concepts to help users and stakeholders understand what the application does and how to interact with it.

---

## 📖 App Concept & Philosophy

**Orbit** is a premium, personal finance tracking and budgeting application designed for Android. The naming "Orbit" is inspired by the concept of financial systems revolving around you. Instead of requiring you to manually track every coffee, bus ride, or utility payment, Orbit places the user at the center of a self-updating financial ecosystem. It automates data ingestion using native SMS transaction parsing, provides intelligent context-aware financial advice via an integrated AI Copilot, and guides financial planning through interactive tools and calculators.

---

## 📲 Core Feature Catalog & User Workflows

### 1. Onboarding & Backup Restore
- **Fresh Install Prompt**: Upon first launch, Orbit checks for existing database contents. If it is a fresh install, the app displays a welcoming dialog offering to restore data from a previous JSON backup file.
- **Biometric Security**: Users can toggle PIN lock and Biometric Authentication (Fingerprint / Face ID) from the Settings screen. When enabled, Orbit secures the application entry point and prompts the user with an authentication lock screen.

### 2. SMS Intelligence & Automated Transaction Parsing
*Orbit dramatically reduces manual entry friction by listening for transaction notifications and parsing SMS text messages.*
- **Supported Senders**: Detects incoming texts from major Indian banks and payment networks (SBI, HDFC, ICICI, Axis, PNB, Kotak, Paytm, PhonePe, GPay, etc.).
- **Automatic Entity Extraction**: The app parses:
  - **Transaction Amount** (extracts ₹/Rs/INR numerical figures).
  - **Transaction Type** (Debit/Expense vs. Credit/Income).
  - **Account/Card Association** (typically matching the last 3-4 digits of the account number).
  - **Merchant Name** (resolves transaction targets using smart preposition matching like "at", "to", "towards").
- **Verification Bottom Sheet**: Immediately after an SMS is parsed, a custom pre-filled transaction verification sheet slides up. The user can verify the category and note, edit details, or save/discard the transaction.
- **Self-Learning Merchant Mapping**: If a user updates a transaction from merchant `X` (e.g., `Zomato`) to a category (e.g., `Food & Dining`), Orbit remembers this mapping. Future transactions from `Zomato` automatically default to `Food & Dining`.
- **Missing Card Auto-Creation**: If an SMS refers to a credit card last-4 combination not yet registered, the app prompts the user to create it on the spot. If the user declines 5 times, Orbit stops prompting for that specific card to prevent spamming.

### 3. Accounts & Credit Card Separation
*Orbit enforces a clear boundary between standard positive assets (checking, savings, investments) and outstanding debt liabilities (credit cards).*
- **Dashboard Separation**:
  - **Standard Accounts** (Cash, Bank, Investments): Display active positive balances contributing to net worth.
  - **Credit Cards**: Rendered with **Outstanding Balance**, **Available Limit**, and a color-coded utilization bar (outstanding vs total limit).
- **Suffix Account Mapping**: Users can input the last 3-4 digits of their physical account/card numbers in Settings. When an SMS arrives matching those digits, Orbit automatically logs the transaction to the correct account.
- **Spend Limits & Warnings**: Users can define spending warning thresholds for credit cards. If an added transaction pushes the outstanding card balance beyond this threshold, a warning popup is shown before saving.

### 4. Hierarchical Category Trees & Safe Deletion
- **Parent-Child Taxonomy**: Orbit comes pre-seeded with nested category trees (e.g., Parent `⚡ Utilities` contains child nodes like `Electricity`, `Water`, `Internet/WiFi`, `Mobile Recharge`).
- **Safe Deletion Panel**: Deleting a category can historically break transactions. Orbit manages this by transferring all transactions mapped to a deleted category to safe fallback groups (`Miscellaneous` for expenses, or `Other Income` for earnings) before deleting the category record.
- **Category Budget Threshold Warnings**: Setting a monthly budget for a category alerts the user with a confirmation modal once transaction entries exceed 80% of the set threshold.

### 5. Conversational AI Financial Copilot
- **Contextual Awareness**: The AI Copilot has secure local read access to your active account balances and the last 60 days of transactional history.
- **Interactive Chat**: You can ask Orbit's copilot questions like:
  - *"How much did I spend on food this month?"*
  - *"Am I on track to meet my savings goal?"*
  - *"Give me a summary of my credit card utilization."*
- **Burn-Rate Alerts**: Mathematical logic evaluates your monthly expenditure velocity. If your burn rate indicates you'll overshoot your overall budget, the dashboard displays a warning banner. Tap the banner to open an AI analysis of your spending bottlenecks.

### 6. Money Bifurcation Splits
- **Bifurcation Calculator**: Visualizes popular budget allocation rules:
  - **50/30/20 Rule**: 50% Needs, 30% Wants, 20% Savings.
  - **70/20/10 Rule**: 70% Needs, 20% Savings, 10% Wants.
  - **Custom Rule**: Define your own customized percentages.
- **Stacked Progress Charts**: Visualizes splits dynamically based on your entered monthly income.
- **Monthly Allocation Reminders**: Configurable push notifications on the 1st of every month nudge the user to distribute salary deposits across savings, investment, and checking pots.

### 7. Financial Planning Calculators
- **SIP (Systematic Investment Plan) Calculator**: Input target savings goals, interest rates, and timelines. Orbit calculates the monthly contribution required to hit the target. Results can be converted into active, trackable **Savings Goals** in the app with one tap.
- **Emergency Fund Calculator**: Computes your average monthly spend dynamically from real SQLite transaction records. Suggests emergency fund sizes covering 3, 6, or 12 months, and allows quick creation of a target emergency savings goal.

### 8. Subscriptions Tracker & Dashboard Actions
- **Dashboard Countdown Action Bar**: Subscriptions expiring in 5 days or less appear as high-priority warning cards on your dashboard home screen with immediate access to a "Pay Now" button.
- **Unused Subscription Detection**: Analyzes your monthly transactions. If a subscription hasn't registered a debit transaction in the last 45 days, the app marks it as "Unused" and suggests canceling it.

### 9. Net Worth & Promo Milestones
- **Launch Milestones**: Orbit tracks user launches in SharedPreferences. On the 3rd launch, the app triggers a net-worth promotion popup prompting the user to track long-term assets (Mutual Funds, Gold, Stocks, Fixed Deposits) to display an accurate total Net Worth chart.

### 10. Gamification (Streaks & Badges)
- **No-Spend Streak**: Tracks consecutive days without recording expenses.
- **Savings Streak**: Tracks consecutive months with a positive savings rate.
- **Badges**: Unlocks badges (e.g., "Frugal Master", "Super Saver") based on streaks to encourage healthy financial habits.
