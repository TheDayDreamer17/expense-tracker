package com.example.finance_app.receivers

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import com.example.finance_app.MainActivity
import com.example.finance_app.db.AppDatabase
import com.example.finance_app.models.SmsTransaction
import com.example.finance_app.utils.SmsParser
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class SmsReceiver : BroadcastReceiver() {
    companion object {
        const val CHANNEL_ID = "finance_app_native_sms"
        const val NOTIFICATION_ID = 9999
        
        // Static callback registered by MainActivity
        var onSmsTransactionListener: ((SmsTransaction) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages.isNullOrEmpty()) return

            val sender = messages[0].displayOriginatingAddress ?: ""
            val timestamp = messages[0].timestampMillis
            val body = messages.joinToString("") { it.displayMessageBody ?: "" }

            val parsed = SmsParser.parse(sender, body, timestamp) ?: return

            // Run database insert on a background coroutine
            CoroutineScope(Dispatchers.IO).launch {
                val db = AppDatabase.getDatabase(context)
                val rowId = db.smsTransactionDao().insert(parsed)
                
                // If it is successfully inserted (rowId != -1, i.e., not a duplicate)
                if (rowId != -1L) {
                    // 1. Notify the app if it's currently running
                    CoroutineScope(Dispatchers.Main).launch {
                        onSmsTransactionListener?.invoke(parsed)
                    }

                    // 2. Show notification
                    showNotification(context, parsed)
                }
            }
        }
    }

    private fun showNotification(context: Context, tx: SmsTransaction) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SMS Transaction Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifies when new expense SMS is parsed"
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Intent to launch MainActivity when tapped
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("action", "sms_import")
            putExtra("sms_id", tx.id)
            putExtra("amount", tx.amount)
            putExtra("merchant", tx.merchant ?: "Unknown")
            putExtra("type", tx.type)
            putExtra("smsRaw", tx.smsRaw)
            putExtra("sender", tx.sender)
            putExtra("suggestedCategory", tx.suggestedCategory)
            putExtra("accountLast4", tx.accountLast4)
            if (tx.balance != null) putExtra("balance", tx.balance)
            if (tx.upiRef != null) putExtra("upiRef", tx.upiRef)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            tx.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val amountStr = "₹%.2f".format(tx.amount)
        val text = "Tap to review $amountStr at ${tx.merchant ?: "Unknown"}"

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("New Transaction Detected")
            .setContentText(text)
            .setSmallIcon(context.resources.getIdentifier("ic_launcher", "mipmap", context.packageName))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val notificationId = tx.id.hashCode() and 0x7FFFFFFF
        notificationManager.notify(notificationId, notification)
    }
}
