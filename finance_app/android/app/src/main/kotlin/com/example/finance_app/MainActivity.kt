package com.example.finance_app

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import com.example.finance_app.db.AppDatabase
import com.example.finance_app.models.SmsTransaction
import com.example.finance_app.receivers.SmsReceiver
import com.example.finance_app.utils.SmsParser
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.finance_app/sms_methods"
    private val EVENT_CHANNEL = "com.example.finance_app/sms_events"

    private var eventSink: EventChannel.EventSink? = null
    private var launchTransaction: Map<String, Any?>? = null
    private var smsReceiver: SmsReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        smsReceiver = SmsReceiver()
        val filter = IntentFilter("android.provider.Telephony.SMS_RECEIVED").apply {
            priority = 999
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(smsReceiver, filter)
        }
    }

    override fun onStop() {
        super.onStop()
        smsReceiver?.let {
            unregisterReceiver(it)
            smsReceiver = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent != null && intent.getStringExtra("action") == "sms_import") {
            val txMap = mapOf(
                "id" to intent.getStringExtra("sms_id"),
                "amount" to intent.getDoubleExtra("amount", 0.0),
                "merchant" to intent.getStringExtra("merchant"),
                "type" to intent.getStringExtra("type"),
                "smsRaw" to intent.getStringExtra("smsRaw"),
                "sender" to intent.getStringExtra("sender"),
                "suggestedCategory" to intent.getStringExtra("suggestedCategory"),
                "accountLast4" to intent.getStringExtra("accountLast4"),
                "balance" to if (intent.hasExtra("balance")) intent.getDoubleExtra("balance", 0.0) else null,
                "upiRef" to intent.getStringExtra("upiRef"),
                "isCreditCard" to intent.getBooleanExtra("isCreditCard", false),
                "cardName" to intent.getStringExtra("cardName"),
                "timestamp" to System.currentTimeMillis()
            )

            // Cache it for subsequent MethodChannel queries on resume or launch
            launchTransaction = txMap

            // Also emit via event channel immediately if listening (e.g. app in foreground/background)
            eventSink?.let { sink ->
                CoroutineScope(Dispatchers.Main).launch {
                    sink.success(txMap)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Set up MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            val db = AppDatabase.getDatabase(applicationContext)
            
            when (call.method) {
                "getTransactions" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val list = db.smsTransactionDao().getAll()
                        val mapList = list.map { it.toMap() }
                        withContext(Dispatchers.Main) {
                            result.success(mapList)
                        }
                    }
                }
                "getRecentTransactions" -> {
                    val limit = call.argument<Int>("limit") ?: 10
                    CoroutineScope(Dispatchers.IO).launch {
                        val list = db.smsTransactionDao().getRecent(limit)
                        val mapList = list.map { it.toMap() }
                        withContext(Dispatchers.Main) {
                            result.success(mapList)
                        }
                    }
                }
                "deleteTransaction" -> {
                    val id = call.argument<String>("id")
                    if (id != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            db.smsTransactionDao().deleteById(id)
                            withContext(Dispatchers.Main) {
                                result.success(true)
                            }
                        }
                    } else {
                        result.error("BAD_ARGS", "Missing transaction ID", null)
                    }
                }
                "getLaunchTransaction" -> {
                    val tx = launchTransaction
                    launchTransaction = null // Consume it
                    result.success(tx)
                }
                "saveBackupToDownloads" -> {
                    val json = call.argument<String>("json")
                    val fileName = call.argument<String>("fileName")
                    if (json != null && fileName != null) {
                        val success = saveBackupToDownloads(applicationContext, json, fileName)
                        result.success(success)
                    } else {
                        result.error("BAD_ARGS", "Missing json or fileName", null)
                    }
                }
                "scanInbox" -> {
                    val months = call.argument<Int>("months") ?: 3
                    CoroutineScope(Dispatchers.IO).launch {
                        val list = scanInbox(applicationContext, months)
                        withContext(Dispatchers.Main) {
                            result.success(list)
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Set up EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    
                    // Register native broadcast handler callback
                    SmsReceiver.onSmsTransactionListener = { tx ->
                        CoroutineScope(Dispatchers.Main).launch {
                            events?.success(tx.toMap())
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    SmsReceiver.onSmsTransactionListener = null
                }
            }
        )
    }

    private fun scanInbox(context: Context, months: Int): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        val cutoff = System.currentTimeMillis() - (months.toLong() * 30L * 24L * 60L * 60L * 1000L)
        
        val uri = android.net.Uri.parse("content://sms/inbox")
        val projection = arrayOf("address", "body", "date")
        val selection = "date > ?"
        val selectionArgs = arrayOf(cutoff.toString())
        val sortOrder = "date DESC"
        
        try {
            val cursor = context.contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)
            cursor?.use { c ->
                val addressIdx = c.getColumnIndexOrThrow("address")
                val bodyIdx = c.getColumnIndexOrThrow("body")
                val dateIdx = c.getColumnIndexOrThrow("date")
                
                while (c.moveToNext()) {
                    val address = c.getString(addressIdx) ?: ""
                    val body = c.getString(bodyIdx) ?: ""
                    val date = c.getLong(dateIdx)
                    
                    val parsed = SmsParser.parse(address, body, date)
                    if (parsed != null) {
                        list.add(parsed.toMap())
                    }
                }
            }
        } catch (_: Exception) {}
        return list
    }

    private fun saveBackupToDownloads(context: Context, json: String, fileName: String): Boolean {
        return try {
            val resolver = context.contentResolver
            val contentValues = android.content.ContentValues().apply {
                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "application/json")
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, android.os.Environment.DIRECTORY_DOWNLOADS + "/SmartMoneyManager")
                }
            }

            var targetUri: android.net.Uri? = null
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                val projection = arrayOf(android.provider.MediaStore.MediaColumns._ID)
                val selection = "${android.provider.MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${android.provider.MediaStore.MediaColumns.RELATIVE_PATH} = ?"
                val selectionArgs = arrayOf(fileName, android.os.Environment.DIRECTORY_DOWNLOADS + "/SmartMoneyManager/")
                resolver.query(
                    android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    projection,
                    selection,
                    selectionArgs,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val id = cursor.getLong(cursor.getColumnIndexOrThrow(android.provider.MediaStore.MediaColumns._ID))
                        targetUri = android.content.ContentUris.withAppendedId(
                            android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                            id
                        )
                    }
                }
            }

            val finalUri: android.net.Uri? = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                targetUri ?: resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
            } else {
                val pubDir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)
                val smmDir = java.io.File(pubDir, "SmartMoneyManager")
                if (!smmDir.exists()) smmDir.mkdirs()
                val file = java.io.File(smmDir, fileName)
                android.net.Uri.fromFile(file)
            }

            if (finalUri != null) {
                if (finalUri.scheme == "file") {
                    val path = finalUri.path
                    if (path != null) {
                        java.io.File(path).writeText(json)
                    } else {
                        return false
                    }
                } else {
                    resolver.openOutputStream(finalUri, "wt")?.use { outputStream ->
                        outputStream.write(json.toByteArray())
                    }
                }
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
