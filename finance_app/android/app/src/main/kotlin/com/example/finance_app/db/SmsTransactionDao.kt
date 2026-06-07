package com.example.finance_app.db

import androidx.room.*
import com.example.finance_app.models.SmsTransaction

@Dao
interface SmsTransactionDao {
    @Query("SELECT * FROM sms_transactions ORDER BY timestamp DESC")
    fun getAll(): List<SmsTransaction>

    @Query("SELECT * FROM sms_transactions ORDER BY timestamp DESC LIMIT :limit")
    fun getRecent(limit: Int): List<SmsTransaction>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    fun insert(transaction: SmsTransaction): Long

    @Delete
    fun delete(transaction: SmsTransaction)

    @Query("DELETE FROM sms_transactions WHERE id = :id")
    fun deleteById(id: String)
}
