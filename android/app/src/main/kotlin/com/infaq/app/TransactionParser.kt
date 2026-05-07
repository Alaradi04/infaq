package com.infaq.app

import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.regex.Pattern

data class ParsedTransaction(
    val amountValue: Double,
    val balanceValue: Double?,
    val merchant: String,
    val timestampMillis: Long,
    val transactionType: String,
    val matchedIncomeKeyword: String?,
    val matchedExpenseKeyword: String?,
    val reasonForTypeDecision: String,
)

object TransactionParser {
    private val amountPattern = Pattern.compile("""(?:BHD|BD|USD)\s*([0-9]+(?:\.[0-9]{1,3})?)""", Pattern.CASE_INSENSITIVE)
    private val balancePattern = Pattern.compile(
        """(?:avail(?:able)?\s*bal(?:ance)?|balance)\s*(?:is|:)?\s*(?:BHD|BD|USD)\s*([0-9]+(?:\.[0-9]{1,3})?)""",
        Pattern.CASE_INSENSITIVE,
    )
    private val merchantAtPattern = Pattern.compile("""\bat\s+([A-Za-z0-9 &+\-_.]+?)(?:\s+on\s+|\s+@|\s+ref\.|\.)""", Pattern.CASE_INSENSITIVE)
    private val yyyySlashPattern = Pattern.compile("""(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2})""")
    private val ddmmyyyyPattern = Pattern.compile("""(\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2})""")
    private val ddSlashAtPattern = Pattern.compile("""(\d{2}/\d{2})\s*@\s*(\d{2}:\d{2})""", Pattern.CASE_INSENSITIVE)
    private val monthTextPattern = Pattern.compile("""([A-Za-z]{3,9})\s+(\d{1,2}),\s*(\d{2}:\d{2})""")

    private val incomeKeywords = listOf(
        "received",
        "credited by",
        "credited from",
        "deposited",
        "salary",
        "transfer received",
        "account was credited by",
    )
    private val expenseKeywords = listOf(
        "debited",
        "debit card",
        "debit",
        "purchase",
        "spent",
        "paid",
        "card transaction",
        "thank you for using your debit card",
        "thank you for using bbk card",
        "payment made",
        "transferred to",
        "sent to",
        "credited to",
        "was credited to iban ending",
        "bill payment",
        "pos",
    )
    private val expenseOverrideKeywords = listOf(
        "debited",
        "debit card",
        "debit",
        "purchase",
        "spent",
        "card transaction",
        "thank you for using your debit card",
        "thank you for using bbk card",
        "pos",
    )
    private val incomeContextKeywords = listOf(
        "received from",
        "was credited by",
        "credited by",
        "credited from",
        "account was credited by",
    )
    private val expenseContextKeywords = listOf(
        "transferred to",
        "sent to",
        "payment to",
        "payment made",
        "debited",
        "paid",
        "at ",
    )

    fun parse(
        title: String?,
        body: String,
        sourcePackage: String?,
        postTime: Long,
    ): ParsedTransaction? {
        val raw = buildString {
            if (!title.isNullOrBlank()) append(title).append(" ")
            append(body)
        }.trim()
        if (raw.isEmpty()) return null

        val amount = extractAmount(raw) ?: return null
        val balance = extractBalance(raw)
        val typeDecision = detectTransactionType(raw)
        val merchant = extractMerchant(raw, title)
        val ts = extractTimestamp(raw, postTime)
        return ParsedTransaction(
            amountValue = amount,
            balanceValue = balance,
            merchant = merchant,
            timestampMillis = ts,
            transactionType = typeDecision.transactionType,
            matchedIncomeKeyword = typeDecision.matchedIncomeKeyword,
            matchedExpenseKeyword = typeDecision.matchedExpenseKeyword,
            reasonForTypeDecision = typeDecision.reason,
        )
    }

    fun makeId(rawBody: String, timestampMillis: Long, amountValue: Double): String {
        val seed = "$rawBody|$timestampMillis|$amountValue"
        val digest = MessageDigest.getInstance("SHA-256").digest(seed.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }.substring(0, 24)
    }

    private fun extractAmount(text: String): Double? {
        val m = amountPattern.matcher(text)
        while (m.find()) {
            val amount = m.group(1)?.toDoubleOrNull() ?: continue
            val start = m.start()
            val contextStart = maxOf(0, start - 30)
            val context = text.substring(contextStart, start).lowercase(Locale.getDefault())
            // Never treat balances/references/endings as transaction amount.
            val blocked = listOf(
                "ref", "reference",
                "date", "time", "tel", "phone", "avail bal", "available balance", "balance"
            ).any { context.contains(it) }
            if (!blocked) return amount
        }
        return null
    }

    private fun extractBalance(text: String): Double? {
        val m = balancePattern.matcher(text)
        return if (m.find()) m.group(1)?.toDoubleOrNull() else null
    }

    private data class TypeDecision(
        val transactionType: String,
        val matchedIncomeKeyword: String?,
        val matchedExpenseKeyword: String?,
        val reason: String,
    )

    private fun detectTransactionType(text: String): TypeDecision {
        val l = text.lowercase(Locale.getDefault())
        val matchedIncomeKeyword = incomeKeywords.firstOrNull { l.contains(it) }
        val matchedExpenseKeyword = expenseKeywords.firstOrNull { l.contains(it) }
        val matchedExpenseOverride = expenseOverrideKeywords.firstOrNull { l.contains(it) }
        val matchedIncomeContext = incomeContextKeywords.firstOrNull { l.contains(it) }
        val matchedExpenseContext = expenseContextKeywords.firstOrNull { l.contains(it) }

        // 1) Debit/card purchase keywords override everything.
        if (matchedExpenseOverride != null) {
            return TypeDecision(
                transactionType = "expense",
                matchedIncomeKeyword = matchedIncomeKeyword,
                matchedExpenseKeyword = matchedExpenseOverride,
                reason = "expense override keyword matched",
            )
        }

        // 2) "received from"/"was credited by" signals incoming funds.
        if (matchedIncomeContext != null && matchedExpenseContext == null) {
            return TypeDecision(
                transactionType = "income",
                matchedIncomeKeyword = matchedIncomeContext,
                matchedExpenseKeyword = matchedExpenseKeyword,
                reason = "income context matched with no outbound context",
            )
        }

        // 4) Both income and expense language: inspect direction context.
        if (matchedIncomeKeyword != null && matchedExpenseKeyword != null) {
            val isOutbound = matchedExpenseContext != null || l.contains("credited to iban ending")
            val isInbound = matchedIncomeContext != null || l.contains("received from")
            if (isOutbound && !isInbound) {
                return TypeDecision(
                    transactionType = "expense",
                    matchedIncomeKeyword = matchedIncomeKeyword,
                    matchedExpenseKeyword = matchedExpenseKeyword,
                    reason = "mixed keywords with outbound transfer context",
                )
            }
            if (isInbound) {
                return TypeDecision(
                    transactionType = "income",
                    matchedIncomeKeyword = matchedIncomeKeyword,
                    matchedExpenseKeyword = matchedExpenseKeyword,
                    reason = "mixed keywords with inbound receive context",
                )
            }
            return TypeDecision(
                transactionType = "expense",
                matchedIncomeKeyword = matchedIncomeKeyword,
                matchedExpenseKeyword = matchedExpenseKeyword,
                reason = "mixed keywords but no clear inbound context",
            )
        }

        if (matchedIncomeKeyword != null) {
            return TypeDecision(
                transactionType = "income",
                matchedIncomeKeyword = matchedIncomeKeyword,
                matchedExpenseKeyword = null,
                reason = "income keyword matched",
            )
        }

        if (matchedExpenseKeyword != null) {
            return TypeDecision(
                transactionType = "expense",
                matchedIncomeKeyword = null,
                matchedExpenseKeyword = matchedExpenseKeyword,
                reason = "expense keyword matched",
            )
        }

        return TypeDecision(
            transactionType = "expense",
            matchedIncomeKeyword = null,
            matchedExpenseKeyword = null,
            reason = "defaulted to expense due to unknown context",
        )
    }

    private fun extractMerchant(text: String, title: String?): String {
        val l = text.lowercase(Locale.getDefault())
        if (l.contains("talabat")) return "TALABAT"
        if (l.contains("fawri+")) return "Fawri+"
        if (l.contains("benefitpay") || l.contains("benefit") || l.contains("fawri") || l.contains("iban")) {
            return "Transfer/Fawri+"
        }
        val at = merchantAtPattern.matcher(text)
        if (at.find()) {
            val raw = at.group(1)?.trim().orEmpty()
            if (raw.isNotEmpty()) {
                val upper = raw.uppercase(Locale.getDefault())
                if (upper.contains("TALABAT")) return "TALABAT"
                return upper.split("  ").first().trim()
            }
        }
        if (!title.isNullOrBlank()) return title.trim()
        return "Bank transaction"
    }

    private fun extractTimestamp(text: String, fallbackMillis: Long): Long {
        yyyySlashPattern.matcher(text).let { m ->
            if (m.find()) {
                val date = m.group(1)
                val fmt = SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.getDefault())
                fmt.timeZone = TimeZone.getDefault()
                val parsed = runCatching { fmt.parse(date ?: "") }.getOrNull()
                if (parsed != null) return parsed.time
            }
        }
        ddmmyyyyPattern.matcher(text).let { m ->
            if (m.find()) {
                val date = m.group(1)
                val fmt = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault())
                fmt.timeZone = TimeZone.getDefault()
                val parsed = runCatching { fmt.parse(date ?: "") }.getOrNull()
                if (parsed != null) return parsed.time
            }
        }
        ddSlashAtPattern.matcher(text).let { m ->
            if (m.find()) {
                val d = m.group(1) ?: return@let
                val t = m.group(2) ?: return@let
                val cal = Calendar.getInstance()
                val year = cal.get(Calendar.YEAR)
                val fmt = SimpleDateFormat("yyyy/dd/MM HH:mm", Locale.getDefault())
                val parsed = runCatching { fmt.parse("$year/$d $t") }.getOrNull()
                if (parsed != null) return parsed.time
            }
        }
        monthTextPattern.matcher(text).let { m ->
            if (m.find()) {
                val mon = m.group(1) ?: return@let
                val day = m.group(2) ?: return@let
                val hhmm = m.group(3) ?: return@let
                val year = Calendar.getInstance().get(Calendar.YEAR)
                val fmt = SimpleDateFormat("MMM dd yyyy HH:mm", Locale.ENGLISH)
                val parsed = runCatching { fmt.parse("${mon.take(3)} ${day.padStart(2, '0')} $year $hhmm") }.getOrNull()
                if (parsed != null) return parsed.time
            }
        }
        return fallbackMillis
    }
}

