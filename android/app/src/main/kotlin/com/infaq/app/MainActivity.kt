package com.infaq.app

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "infaq/bank_notifications"
    private val prefsName = "infaq_bank_notifications"
    private val pendingKey = "pending_transactions"
    private val recentKey = "recent_notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationListenerSettings" -> {
                        openNotificationListenerSettings()
                        result.success(true)
                    }
                    "isNotificationListenerEnabled" -> {
                        result.success(isNotificationListenerEnabled())
                    }
                    "getPendingBankTransactions" -> {
                        result.success(getPendingTransactions())
                    }
                    "clearSyncedBankTransactions" -> {
                        val ids = (call.arguments as? List<*>)?.mapNotNull { it?.toString() } ?: emptyList()
                        val remaining = clearSynced(ids)
                        result.success(remaining)
                    }
                    "getRecentRawBankNotifications" -> {
                        result.success(getRecentNotifications())
                    }
                    "setBankNotificationDebugMode" -> {
                        val enabled = call.arguments as? Boolean ?: false
                        prefs().edit().putBoolean("debug_collect_all_raw_notifications", enabled).apply()
                        result.success(true)
                    }
                    "getBankNotificationDebugState" -> {
                        result.success(getDebugState())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openNotificationListenerSettings() {
        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val expected = ComponentName(this, BankNotificationListenerService::class.java).flattenToString()
        return enabled.split(":").any { it.equals(expected, ignoreCase = true) }
    }

    private fun prefs() = getSharedPreferences(prefsName, MODE_PRIVATE)

    private fun readJsonArray(key: String): JSONArray {
        val raw = prefs().getString(key, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun getPendingTransactions(): List<Map<String, Any?>> {
        val arr = readJsonArray(pendingKey)
        val out = mutableListOf<Map<String, Any?>>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            out.add(jsonToMap(o))
        }
        return out
    }

    private fun getRecentNotifications(): List<Map<String, Any?>> {
        val arr = readJsonArray(recentKey)
        val out = mutableListOf<Map<String, Any?>>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            out.add(jsonToMap(o))
        }
        return out
    }

    private fun clearSynced(ids: List<String>): Int {
        if (ids.isEmpty()) return readJsonArray(pendingKey).length()
        val idSet = ids.toSet()
        val src = readJsonArray(pendingKey)
        val keep = JSONArray()
        for (i in 0 until src.length()) {
            val o = src.optJSONObject(i) ?: continue
            val id = o.optString("id")
            if (!idSet.contains(id)) keep.put(o)
        }
        prefs().edit().putString(pendingKey, keep.toString()).apply()
        return keep.length()
    }

    private fun getDebugState(): Map<String, Any?> {
        val p = prefs()
        val pending = readJsonArray(pendingKey)
        return mapOf(
            "listenerEnabled" to isNotificationListenerEnabled(),
            "pendingCount" to pending.length(),
            "lastParserError" to p.getString("last_parser_error", null),
            "lastParsedResult" to p.getString("last_parsed_result", null),
            "lastDuplicateDecision" to p.getString("last_duplicate_decision", null),
            "lastTransactionSyncStatus" to p.getString("last_transaction_sync_status", null),
            "lastSupabaseInsertError" to p.getString("last_supabase_insert_error", null),
            "lastAiEnrichmentStatus" to p.getString("last_ai_enrichment_status", null),
            "geminiQuotaStatus" to p.getString("gemini_quota_status", null),
            "recentNotificationsCount" to readJsonArray(recentKey).length(),
            "ignoredNonFinancialNotificationsCount" to p.getInt("ignored_non_financial_notifications_count", 0),
            "lastIgnoredNotificationReason" to p.getString("last_ignored_notification_reason", null),
            "debugCollectAllRawNotifications" to p.getBoolean("debug_collect_all_raw_notifications", false),
        )
    }

    private fun jsonToMap(o: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = o.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            val v = o.opt(k)
            map[k] = if (v == JSONObject.NULL) null else v
        }
        return map
    }
}
