package com.example.finance_app.utils

import com.example.finance_app.models.SmsTransaction
import java.security.MessageDigest
import java.util.regex.Pattern

object SmsParser {
    private val amountRe = Pattern.compile("(?:Rs\\.?|INR|₹)\\s?([\\d,]+\\.?\\d*)", Pattern.CASE_INSENSITIVE)
    private val typeDebitRe = Pattern.compile("\\b(debited|debit|spent|paid|withdrawn|purchase|payment|charged|used\\s+for|txn\\s+of|transaction\\s+of|sent\\s+to|sent)\\b", Pattern.CASE_INSENSITIVE)
    private val typeCreditRe = Pattern.compile("(?:\\bcredited\\b|\\breceived\\b|\\bdeposited\\b|\\brefund\\b|\\bcashback\\b|\\bcredit\\s+(?:of|to|with|in)\\b|\\bcredited\\s+with\\b|\\bcredit\\b(?!\\s*(?:card|limit|line|score|points|rating|facility|account)))", Pattern.CASE_INSENSITIVE)
    private val acctRe = Pattern.compile("(?:a/c|acct|account|card|ac)(?:\\s+no\\.?|\\s+num\\.?|\\s+number)?[\\s\\*xX]*(\\d{3,4})", Pattern.CASE_INSENSITIVE)
    private val merchantRe = Pattern.compile("(?:\\bat\\b|\\bto\\b|\\btowards\\b|\\bfrom\\b|\\bby\\b)\\s+([A-Za-z0-9@\\-_ &]{2,40}?)(?:\\s+on|\\s+via|\\s+ref|\\s+upi|[.\\n,]|$)", Pattern.CASE_INSENSITIVE)
    private val iciciMerchantRe = Pattern.compile("\\bon\\s+\\d{1,2}-[A-Za-z]{3}-\\d{2,4}\\s+on\\s+([A-Za-z0-9@\\-_ &]{2,40}?)(?:\\.|\\s+avl|\\s+limit|\\s+if\\b|$)", Pattern.CASE_INSENSITIVE)
    private val balanceRe = Pattern.compile("(?:avl\\.?\\s*bal(?:ance)?|available bal(?:ance)?|bal(?:ance)?[\\s:]*)[\\s:]+(?:Rs\\.?|INR|₹)\\s?([\\d,]+\\.?\\d*)", Pattern.CASE_INSENSITIVE)
    private val upiRefRe = Pattern.compile("(?:upi\\s+ref(?:erence)?(?:\\s+no)?|ref\\s+no|txn\\s+id)[\\s:]*(\\d{12})", Pattern.CASE_INSENSITIVE)

    private val nonTransactionRe = Pattern.compile(
        "\\b(one[- ]time password|one[- ]time passcode|otps?|verification code|secret\\.? do not disclose|never share|do not share|valid for \\d+ min)\\b|" +
        "\\b(increase limit|spending power|for free|pre[- ]approved|apply now|upgrade (?:your )?limit|loan offer|eligible for|enjoy more spending power)\\b|" +
        "\\b(ensure sufficient balance|maintain balance|will be debited on|scheduled for|scheduled on|reminder for|is due on|due on|auto debit reminder|payment due|upcoming payment)\\b",
        Pattern.CASE_INSENSITIVE
    )

    private val categoryKeywords = mapOf(
        "cat_food" to listOf("swiggy", "zomato", "dominos", "pizza", "kfc", "mcdonalds", "restaurant", "cafe", "coffee", "starbucks", "swish", "munchmart", "eatery", "bakery"),
        "cat_grocery" to listOf("bigbasket", "blinkit", "zepto", "dmart", "grofers", "jiomart", "supermarket", "grocery", "instamart", "avenue e commer"),
        "cat_transport" to listOf("uber", "ola", "rapido", "metro", "irctc", "railway", "redbus", "petrol", "fuel", "parking", "toll"),
        "cat_shopping" to listOf("amazon", "flipkart", "myntra", "meesho", "nykaa", "ajio", "decathlon", "croma", "vijaysales"),
        "cat_entertainment" to listOf("netflix", "prime", "hotstar", "disney", "spotify", "youtube", "bookmyshow", "pvr", "inox"),
        "cat_health" to listOf("apollo", "pharmeasy", "1mg", "hospital", "clinic", "doctor", "pharmacy", "medical"),
        "cat_utilities" to listOf("electricity", "water", "gas", "bescom", "tata power"),
        "cat_telecom" to listOf("airtel", "jio", "bsnl", "vodafone", "recharge", "broadband", "dth"),
        "cat_subscription" to listOf("subscription", "chatgpt", "openai", "github", "adobe", "microsoft"),
        "cat_financial" to listOf("emi", "loan", "interest", "late fee", "bounce", "penal", "credit card bill", "cred")
    )

    fun parse(sender: String, body: String, timestamp: Long): SmsTransaction? {
        // Drop non-transaction messages (OTPs, promotional limit hikes, debit reminders)
        if (nonTransactionRe.matcher(body).find()) return null

        // Amount check
        val amtMatcher = amountRe.matcher(body)
        if (!amtMatcher.find()) return null
        val rawAmount = amtMatcher.group(1)?.replace(",", "") ?: return null
        val amount = rawAmount.toDoubleOrNull() ?: return null
        if (amount <= 0) return null

        // Type check
        val isDebit = typeDebitRe.matcher(body).find()
        val isCredit = typeCreditRe.matcher(body).find()
        if (!isDebit && !isCredit) return null

        val type = if (isDebit && isCredit) {
            val lower = body.lowercase()
            if (lower.contains("refund") || lower.contains("cashback") || lower.contains("credited")) "INCOME" else "EXPENSE"
        } else if (isDebit) {
            "EXPENSE"
        } else {
            "INCOME"
        }

        // Account/Card
        val acctMatcher = acctRe.matcher(body)
        val accountLast4 = if (acctMatcher.find()) acctMatcher.group(1) else null

        // Merchant
        val iciciMatcher = iciciMerchantRe.matcher(body)
        val merMatcher = merchantRe.matcher(body)
        var merchant = when {
            iciciMatcher.find() -> iciciMatcher.group(1)?.trim()
            merMatcher.find() -> merMatcher.group(1)?.trim()
            else -> null
        }

        if (merchant != null) {
            val clean = merchant.trim()
            val lower = clean.lowercase()
            if (clean.matches(Regex("^(?:inr|rs|₹)?\\s*[\\d,.]+$", RegexOption.IGNORE_CASE)) ||
                lower.contains("block") ||
                lower.contains("no.") ||
                lower.startsWith("avl") ||
                lower.startsWith("bal") ||
                clean.length < 2) {
                merchant = null
            } else {
                merchant = clean
            }
        }

        if (merchant == null || merchant.isEmpty()) {
            val lines = body.split("\n").map { it.trim() }
            for (i in lines.indices) {
                val line = lines[i]
                if (line.lowercase().contains("limit") || line.lowercase().contains("bal")) {
                    if (i > 0) {
                        val prevLine = lines[i - 1]
                        val lowerPrev = prevLine.lowercase()
                        val isDateTime = prevLine.contains(Regex("\\d{2}-\\d{2}-\\d{2}")) ||
                                         prevLine.contains(Regex("\\d{4}-\\d{2}-\\d{2}")) ||
                                         lowerPrev.contains("ist") ||
                                         lowerPrev.contains("gmt") ||
                                         lowerPrev.contains("pm") ||
                                         lowerPrev.contains("am")
                        val isCardOrSpent = lowerPrev.contains("card") ||
                                            lowerPrev.contains("spent") ||
                                            lowerPrev.contains("rs.") ||
                                            lowerPrev.contains("inr") ||
                                            lowerPrev.contains("₹")
                        if (!isDateTime && !isCardOrSpent && prevLine.isNotEmpty() && prevLine.length > 2) {
                            merchant = prevLine
                            break
                        }
                    }
                }
            }
        }

        // Balance
        val balMatcher = balanceRe.matcher(body)
        val balance = if (balMatcher.find()) balMatcher.group(1)?.replace(",", "")?.toDoubleOrNull() else null

        // UPI Ref
        val upiMatcher = upiRefRe.matcher(body)
        val upiRef = if (upiMatcher.find()) upiMatcher.group(1) else null

        // Suggested category
        val categoryText = merchant ?: body
        val category = detectCategory(categoryText)

        // Unique ID from hash of body + timestamp to differentiate separate transactions with identical bodies
        val id = hashString("$body|$timestamp")

        val lowerBody = body.lowercase()
        val lowerSender = sender.lowercase()
        val isCreditCard = lowerBody.contains("credit card") ||
                lowerBody.contains("spent on card") ||
                lowerBody.contains("card ending") ||
                lowerSender.contains("card") ||
                lowerSender.contains("crd") ||
                (lowerBody.contains("card") && type == "EXPENSE")

        var cardName: String? = null
        if (isCreditCard) {
            cardName = when {
                lowerSender.contains("sbi") || lowerBody.contains("sbi") -> "SBI Card"
                lowerSender.contains("hdfc") || lowerBody.contains("hdfc") -> "HDFC Card"
                lowerSender.contains("icici") || lowerBody.contains("icici") -> "ICICI Card"
                lowerSender.contains("axis") || lowerBody.contains("axis") -> "Axis Card"
                lowerSender.contains("scapia") || lowerBody.contains("scapia") -> "Scapia Federal Card"
                else -> "Credit Card"
            }
        }

        return SmsTransaction(
            id = id,
            amount = amount,
            type = type,
            merchant = merchant,
            accountLast4 = accountLast4,
            balance = balance,
            suggestedCategory = category,
            smsRaw = body,
            sender = sender,
            timestamp = timestamp,
            upiRef = upiRef,
            isCreditCard = isCreditCard,
            cardName = cardName
        )
    }

    private fun detectCategory(text: String): String {
        val lower = text.lowercase()
        for ((cat, keywords) in categoryKeywords) {
            for (kw in keywords) {
                if (lower.contains(kw)) {
                    return cat
                }
            }
        }
        return "cat_other_exp"
    }

    private fun hashString(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
