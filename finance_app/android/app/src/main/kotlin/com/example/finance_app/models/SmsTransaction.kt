package com.example.finance_app.models

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "sms_transactions")
data class SmsTransaction(
    @PrimaryKey val id: String, // SHA-256 hash of smsRaw to prevent duplicates
    val amount: Double,
    val type: String, // "EXPENSE" | "INCOME"
    val merchant: String?,
    val accountLast4: String?,
    val balance: Double?,
    val suggestedCategory: String,
    val smsRaw: String,
    val sender: String,
    val timestamp: Long,
    val upiRef: String?,
    val isCreditCard: Boolean,
    val cardName: String?
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "amount" to amount,
            "type" to type,
            "merchant" to merchant,
            "accountLast4" to accountLast4,
            "balance" to balance,
            "suggestedCategory" to suggestedCategory,
            "smsRaw" to smsRaw,
            "sender" to sender,
            "timestamp" to timestamp,
            "upiRef" to upiRef,
            "isCreditCard" to if (isCreditCard) 1 else 0,
            "cardName" to cardName
        )
    }
}
