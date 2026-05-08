package com.infaq.app

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

class BankNotificationListenerService : NotificationListenerService() {
    private val tag = "INFAQ_BANK_LISTENER"
    private val prefsName = "infaq_bank_notifications"
    private val pendingKey = "pending_transactions"
    private val recentKey = "recent_notifications"
    private val debugCollectAllRawKey = "debug_collect_all_raw_notifications"

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            val pkg = sbn.packageName ?: ""
            val notification = sbn.notification ?: return
            val extras = notification.extras

            val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
            val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
            val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
            val subText = extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty()
            val summaryText = extras?.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString().orEmpty()
            val postTime = sbn.postTime

            Log.d(tag, "notification received")
            Log.d(tag, "sourcePackage=$pkg postTime=$postTime")
            Log.d(tag, "title=$title")

            val fullBody = listOf(title, text, bigText, subText, summaryText)
                .filter { it.isNotBlank() }
                .joinToString(" ")
                .trim()
            val known = isKnownFinancialNotification(pkg, title, fullBody)
            val ignoredReason = if (known) null else ignoredReason(pkg, title, fullBody)
            Log.d(tag, "isKnownFinancialNotification=$known")
            if (!known) {
                Log.d(tag, "ignored reason=$ignoredReason")
                incrementIgnoredNonFinancial(ignoredReason ?: "unknown")
                if (isDebugCollectAllRawEnabled()) {
                    saveRecentRaw(
                        JSONObject()
                            .put("sourcePackage", pkg)
                            .put("title", title)
                            .put("text", text)
                            .put("bigText", bigText)
                            .put("subText", subText)
                            .put("summaryText", summaryText)
                            .put("postTime", postTime)
                            .put("combinedBody", fullBody)
                            .put("ignored", true)
                            .put("ignoredReason", ignoredReason ?: "unknown")
                    )
                }
                return
            }
            saveRecentRaw(
                JSONObject()
                    .put("sourcePackage", pkg)
                    .put("title", title)
                    .put("text", text)
                    .put("bigText", bigText)
                    .put("subText", subText)
                    .put("summaryText", summaryText)
                    .put("postTime", postTime)
                    .put("combinedBody", fullBody)
                    .put("ignored", false)
            )

            if (fullBody.isBlank()) {
                writeDebug("last_parser_error", "empty combined body")
                Log.d(tag, "parser failed: empty combined body")
                return
            }

            val parsed = TransactionParser.parse(
                title = title,
                body = fullBody,
                sourcePackage = pkg,
                postTime = postTime,
            )

            if (parsed == null) {
                writeDebug("last_parser_error", "no amount/type detected")
                Log.d(tag, "parser failed: no amount/type detected")
                return
            }
            val sourceType = detectSourceType(pkg, title, fullBody)
            val sourcePriority = sourcePriority(sourceType)
            val fingerprint = buildDuplicateFingerprint(
                amountValue = parsed.amountValue,
                transactionType = parsed.transactionType,
                merchant = parsed.merchant,
                timestampMillis = parsed.timestampMillis,
                rawBody = fullBody,
            )

            val id = TransactionParser.makeId(fullBody, parsed.timestampMillis, parsed.amountValue)
            val payload = JSONObject()
                .put("id", id)
                .put("amountValue", parsed.amountValue)
                .put("amountCurrency", parsed.amountCurrency)
                .put("balanceValue", parsed.balanceValue)
                .put("balanceCurrency", parsed.balanceCurrency)
                .put("merchant", parsed.merchant)
                .put("referenceNumber", parsed.referenceNumber)
                .put("detectedBank", parsed.detectedBank)
                .put("timestampMillis", parsed.timestampMillis)
                .put("transactionType", parsed.transactionType)
                .put("rawTitle", title)
                .put("rawBody", fullBody)
                .put("sourcePackage", pkg)
                .put("sourceType", sourceType)
                .put("sourcePriority", sourcePriority)
                .put("duplicateFingerprint", fingerprint)
                .put("detectedAtMillis", System.currentTimeMillis())
                .put("syncStatus", "pending")
                .put("aiStatus", "not_started")

            writeDebug("last_parsed_result", payload.toString())
            writeDebug("last_parser_error", null)
            Log.d(tag, "rawBody=$fullBody")
            Log.d(tag, "extracted amount=${parsed.amountValue}")
            Log.d(tag, "extracted balance=${parsed.balanceValue}")
            Log.d(tag, "extracted transactionType=${parsed.transactionType}")
            Log.d(tag, "matchedIncomeKeyword=${parsed.matchedIncomeKeyword}")
            Log.d(tag, "matchedExpenseKeyword=${parsed.matchedExpenseKeyword}")
            Log.d(tag, "reasonForTypeDecision=${parsed.reasonForTypeDecision}")
            Log.d(tag, "finalTransactionType=${parsed.transactionType}")
            Log.d(tag, "extracted merchant=${parsed.merchant}")
            Log.d(tag, "extracted timestampMillis=${parsed.timestampMillis}")
            Log.d(tag, "parsed datetime=${formatTs(parsed.timestampMillis)}")
            Log.d(tag, "sourceType=$sourceType sourcePriority=$sourcePriority")
            Log.d(tag, "duplicateFingerprint=$fingerprint")
            Log.d(tag, "parsed payload=$payload")

            val decision = savePendingWithPriorityDedup(payload)
            writeDebug("last_duplicate_decision", decision)
            val saved = decision == "saved" || decision == "replaced_by_higher_priority"
            if (saved) {
                val size = readJsonArray(pendingKey).length()
                Log.d(tag, "saved to queue. queueSize=$size")
            } else {
                Log.d(tag, "duplicate decision=$decision")
            }
        } catch (e: Exception) {
            Log.e(tag, "listener error", e)
            writeDebug("last_parser_error", e.message ?: "unknown listener error")
        }
    }

    private fun savePendingWithPriorityDedup(payload: JSONObject): String {
        val arr = readJsonArray(pendingKey)
        val id = payload.optString("id")
        val amount = payload.optDouble("amountValue")
        val merchant = payload.optString("merchant")
        val rawBody = payload.optString("rawBody")
        val type = payload.optString("transactionType")
        val sourcePriority = payload.optInt("sourcePriority", 1)
        val ts = payload.optLong("timestampMillis")
        val fp = payload.optString("duplicateFingerprint")

        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (o.optString("id") == id) return "ignored_lower_priority_duplicate"
            val sameContent =
                o.optDouble("amountValue") == amount &&
                    o.optString("merchant") == merchant &&
                    o.optString("rawBody") == rawBody
            val similar = sameContent || isSimilarDuplicate(o, amount, type, merchant, ts, fp)
            if (!similar) continue
            val existingPriority = o.optInt("sourcePriority", 1)
            if (sourcePriority > existingPriority) {
                arr.put(i, payload)
                writeJsonArray(pendingKey, arr)
                return "replaced_by_higher_priority"
            }
            return "ignored_lower_priority_duplicate"
        }
        arr.put(payload)
        writeJsonArray(pendingKey, arr)
        return "saved"
    }

    private fun saveRecentRaw(notification: JSONObject) {
        val arr = readJsonArray(recentKey)
        val next = JSONArray()
        next.put(notification)
        for (i in 0 until arr.length()) {
            if (next.length() >= 10) break
            next.put(arr.optJSONObject(i))
        }
        writeJsonArray(recentKey, next)
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

    private fun writeJsonArray(key: String, arr: JSONArray) {
        prefs().edit().putString(key, arr.toString()).apply()
    }

    private fun writeDebug(key: String, value: String?) {
        prefs().edit().apply {
            if (value == null) remove(key) else putString(key, value)
        }.apply()
    }

    private fun formatTs(ts: Long): String {
        val f = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
        return f.format(Date(ts))
    }

    private fun isKnownFinancialNotification(sourcePackage: String, title: String, body: String): Boolean {
        val hay = "$title $body".lowercase(Locale.getDefault())
        val p = sourcePackage.lowercase(Locale.getDefault())
        val blockedAlways = setOf("com.whatsapp", "com.instagram.android", "com.android.systemui")
        if (blockedAlways.contains(p)) return false

        val financialKeywords = listOf(
            "bisb", "bahrain islamic bank", "bbk", "bank of bahrain and kuwait", "nbb",
            "national bank of bahrain", "ila", "ila bank", "bank abc", "al salam bank",
            "fawri+", "benefitpay", "benefit", "khaleeji bank", "kuwait finance house", "kfh",
            "ahli united bank", "aub", "hsbc bahrain", "standard chartered", "citibank bahrain"
        )
        val hasKeyword = financialKeywords.any { hay.contains(it) }
        if ((p == "com.google.android.apps.messaging" || p == "com.samsung.android.messaging") && !hasKeyword) {
            return false
        }

        val knownBankPackages = listOf(
            "com.bisb", "com.bbk", "com.nbb", "com.benefitpay", "com.bankabc", "com.ilabank",
            "com.alsalam", "com.kfh", "com.aub", "com.hsbc", "com.scb", "com.citi"
        )
        val packageLooksBank = knownBankPackages.any { p.contains(it) }
        return hasKeyword || packageLooksBank
    }

    private fun ignoredReason(sourcePackage: String, title: String, body: String): String {
        val p = sourcePackage.lowercase(Locale.getDefault())
        if (p == "com.whatsapp" || p == "com.instagram.android" || p == "com.android.systemui") {
            return "blocked package"
        }
        if (p == "com.google.android.apps.messaging" || p == "com.samsung.android.messaging") {
            return "messaging package without bank keywords"
        }
        return "unknown non-financial source"
    }

    private fun isDebugCollectAllRawEnabled(): Boolean {
        return prefs().getBoolean(debugCollectAllRawKey, false)
    }

    private fun incrementIgnoredNonFinancial(reason: String) {
        val p = prefs()
        val count = p.getInt("ignored_non_financial_notifications_count", 0) + 1
        p.edit()
            .putInt("ignored_non_financial_notifications_count", count)
            .putString("last_ignored_notification_reason", reason)
            .apply()
    }

    private fun detectSourceType(sourcePackage: String, title: String, body: String): String {
        val p = sourcePackage.lowercase(Locale.getDefault())
        val t = "$title $body".lowercase(Locale.getDefault())
        val isMessages = p.contains("messaging") || p.contains("messages") || p.contains("sms")
        val smsBankKeywords = listOf(
            "bisb", "bbk", "nbb", "ila", "benefit", "fawri+", "credited", "debit card", "account"
        )
        if (isMessages && smsBankKeywords.any { t.contains(it) }) return "sms_bank"
        if (!isMessages && (t.contains("benefitpay") || t.contains("benefit"))) return "benefit_app"
        return "bank_app"
    }

    private fun sourcePriority(sourceType: String): Int {
        return when (sourceType) {
            "sms_bank" -> 3
            "bank_app" -> 2
            "benefit_app" -> 1
            else -> 1
        }
    }

    private fun buildDuplicateFingerprint(
        amountValue: Double,
        transactionType: String,
        merchant: String,
        timestampMillis: Long,
        rawBody: String,
    ): String {
        val amountNorm = String.format(Locale.US, "%.3f", amountValue)
        val merchantNorm = merchant.lowercase(Locale.getDefault()).replace(Regex("[^a-z0-9]+"), "")
        val bodyNorm = rawBody.lowercase(Locale.getDefault()).replace(Regex("[^a-z0-9]+"), " ").trim()
        val bodyHash = TransactionParser.makeId(bodyNorm, timestampMillis, amountValue)
        val bucket = timestampMillis / (5 * 60 * 1000L)
        return "$amountNorm|$transactionType|$merchantNorm|$bucket|$bodyHash"
    }

    private fun isSimilarDuplicate(
        existing: JSONObject,
        amount: Double,
        type: String,
        merchant: String,
        ts: Long,
        fp: String,
    ): Boolean {
        if (existing.optString("duplicateFingerprint") == fp) return true
        val exAmount = existing.optDouble("amountValue")
        val exType = existing.optString("transactionType")
        val exMerchant = existing.optString("merchant").lowercase(Locale.getDefault())
        val exTs = existing.optLong("timestampMillis")
        val closeTs = kotlin.math.abs(exTs - ts) <= 5 * 60 * 1000L
        val sameCore = kotlin.math.abs(exAmount - amount) < 0.0009 &&
            exType == type &&
            closeTs
        if (!sameCore) return false
        val m = merchant.lowercase(Locale.getDefault())
        if ((m.contains("fawri") || m.contains("benefit")) &&
            (exMerchant.contains("fawri") || exMerchant.contains("benefit"))
        ) return true
        return exMerchant == m
    }
}

