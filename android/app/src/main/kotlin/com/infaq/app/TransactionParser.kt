package com.infaq.app

import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.regex.Pattern

data class ParsedTransaction(
    val amountValue: Double,
    val amountCurrency: String,
    val balanceValue: Double?,
    val balanceCurrency: String?,
    val merchant: String,
    val referenceNumber: String?,
    val detectedBank: String,
    val timestampMillis: Long,
    val transactionType: String,
    val matchedIncomeKeyword: String?,
    val matchedExpenseKeyword: String?,
    val reasonForTypeDecision: String,
)

object TransactionParser {
    private val amountPattern = Pattern.compile(
        """\b(BHD|BD|USD)\s*([0-9]+(?:\.[0-9]{1,3})?)\b""",
        Pattern.CASE_INSENSITIVE,
    )
    private val balancePattern = Pattern.compile(
        """(?:avail(?:able)?\s*bal(?:ance)?|a/c\s*bal|balance|bal|your\s+balance\s+is)\s*(?:is|:)?\s*(BHD|BD|USD)\s*([0-9]*\.?[0-9]{1,3})\b""",
        Pattern.CASE_INSENSITIVE,
    )
    private val merchantAtPattern = Pattern.compile("""\bat\s+([A-Za-z0-9 &+\-_.]+?)(?:\s+on\s+|\s+@|\s+ref\.|\.)""", Pattern.CASE_INSENSITIVE)
    private val yyyySlashPattern = Pattern.compile("""(\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2})""")
    private val ddmmyyyyPattern = Pattern.compile("""(\d{2}/\d{2}/\d{4})(?:\s+at)?\s+(\d{2}:\d{2})""", Pattern.CASE_INSENSITIVE)
    private val ddmmyyPattern = Pattern.compile("""(\d{2}/\d{2}/\d{2})(?:\s+at)?\s+(\d{2}:\d{2})""", Pattern.CASE_INSENSITIVE)
    private val ddSlashAtPattern = Pattern.compile("""(\d{2}/\d{2})\s*@\s*(\d{2}:\d{2})""", Pattern.CASE_INSENSITIVE)
    private val monthTextPattern = Pattern.compile("""([A-Za-z]{3,9})\s+(\d{1,2}),\s*(\d{2}:\d{2})""")
    private val referencePattern = Pattern.compile("""\bref[:\s]*([A-Za-z0-9]+)\b""", Pattern.CASE_INSENSITIVE)

    // --- KFH / ila structured templates (checked before generic amount heuristics) ---
    private val kfhCardPurchasePattern = Pattern.compile(
        """(?i)Dear\s+Customer,\s+you\s+have\s+a\s+purchase\s+on\s+your\s+card\s+\*+(\d{4})\s+at\s+(.+?)\s+for\s+(BHD|BD)\s*([0-9]+(?:\.[0-9]{1,3})?)\s+on\s+(\d{1,2})-([A-Za-z]{3})\s+(\d{2}:\d{2}(?::\d{2})?)(?:,|\s).*?Avail\s*bal\s+(BHD|BD)\s*([0-9]+(?:\.[0-9]{1,3})?)""",
        Pattern.DOTALL,
    )
    private val kfhFawriPlusCreditedToIbanPattern = Pattern.compile(
        """(?i)Dear\s+Customer,\s+Fawri\+\s+payment\s+(BHD|BD)\s*([0-9]+(?:\.[0-9]{1,3})?)\s*,\s*Ref\.\s*([A-Za-z0-9]+)\s+credited\s+to\s+IBAN\s+([A-Za-z0-9]+)\s+on\s+(\d{2}/\d{2}/\d{4})\s+at\s+(\d{2}:\d{2}(?::\d{2})?)""",
    )
    private val kfhFawriPlusReceivedFromIbanPattern = Pattern.compile(
        """(?i)Dear\s+Customer,\s+Fawri\+\s+payment\s+(BHD|BD)\s*([0-9]+(?:\.[0-9]{1,3})?)\s*,\s*Ref\.\s*([A-Za-z0-9]+)\s+received\s+from\s+IBAN\s+([A-Za-z0-9]+)\s+on\s+(\d{2}/\d{2}/\d{4})\s+at\s+(\d{2}:\d{2}(?::\d{2})?)""",
    )
    private val kfhFawriCreditedPattern = Pattern.compile(
        """(?i)Dear\s+Customer,\s+Fawri\s+payment\s+with\s+ref\.\s*([A-Za-z0-9]+)\s+received\s+from\s+([A-Za-z0-9]+)\s+(BHD|BD)\s*([0-9]+(?:\.[0-9]{1,3})?)\s+credited\s+to\s+your\s+([A-Za-z0-9*]+)\s+on\s+(\d{2}/\d{2}/\d{4})\s+at\s+(\d{2}:\d{2}(?::\d{2})?)""",
    )
    private val ilaCardPurchasePattern = Pattern.compile(
        """(?i)Success!\s*Purchase\s+at\s+(.+?)\s+using\s+card\s+\*+(\d{4})\s+for\s+(BHD|BD)\s*([0-9]+(?:\.[0-9]{1,3})?)\s+on\s+(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2}(?::\d{2})?)\s+debited\s+from.*?Balance\s+(BHD|BD)\s*([0-9]+(?:\.[0-9]{1,3})?)""",
        Pattern.DOTALL,
    )
    private val ilaFawriPlusTransferPattern = Pattern.compile(
        """(?i)Success!\s*Fawri\+\s+transfer\s+of\s+(BHD|BD)\s*([0-9]+(?:\.[0-9]{1,3})?)\s+from\s+IBAN\s+([A-Za-z0-9]+)\s+credited\s+to\s+BHD\s+Ac\s+on\s+(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2}(?::\d{2})?)\s+Ref\s+([A-Za-z0-9]+).*?Balance\s+(BHD|BD)\s*([0-9]+(?:\.[0-9]{1,3})?)""",
        Pattern.DOTALL,
    )

    private val incomeKeywords = listOf(
        "was credited by",
        "credited by",
        "received from",
        "from iban",
        "your account was credited",
        "received",
        "credited from",
        "deposited",
        "salary",
        "transfer received",
        "account was credited by",
    )
    private val expenseKeywords = listOf(
        "has been debited",
        "debited from your account",
        "using your debit card",
        "thank you for using bbk card",
        "payment of",
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

        tryParseKfhIlaTemplates(raw, title, sourcePackage, postTime)?.let { return it }

        val amountData = extractAmount(raw) ?: return null
        val balanceData = extractBalance(raw)
        val typeDecision = detectTransactionType(raw)
        val merchant = extractMerchant(raw, title)
        val referenceNumber = extractReference(raw)
        val detectedBank = detectBank(raw, title, sourcePackage)
        val ts = extractTimestamp(raw, postTime)
        return ParsedTransaction(
            amountValue = amountData.second,
            amountCurrency = amountData.first,
            balanceValue = balanceData?.second,
            balanceCurrency = balanceData?.first,
            merchant = merchant,
            referenceNumber = referenceNumber,
            detectedBank = detectedBank,
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

    private fun tryParseKfhIlaTemplates(
        raw: String,
        title: String?,
        sourcePackage: String?,
        postTime: Long,
    ): ParsedTransaction? {
        tryParseIlaFawriPlusTransfer(raw, postTime)?.let { return it }
        tryParseIlaCardPurchase(raw, postTime)?.let { return it }
        tryParseKfhFawriPlusCreditedToIban(raw, title, sourcePackage, postTime)?.let { return it }
        tryParseKfhFawriPlusReceivedFromIban(raw, title, sourcePackage, postTime)?.let { return it }
        tryParseKfhFawriCredited(raw, title, sourcePackage, postTime)?.let { return it }
        tryParseKfhCardPurchase(raw, title, sourcePackage, postTime)?.let { return it }
        return null
    }

    private fun tryParseIlaFawriPlusTransfer(raw: String, postTime: Long): ParsedTransaction? {
        val m = ilaFawriPlusTransferPattern.matcher(raw)
        if (!m.find()) return null
        val amount = m.group(2)?.toDoubleOrNull() ?: return null
        val cur = normalizeCurrency(m.group(1)?.uppercase(Locale.getDefault()) ?: "BHD")
        val ref = m.group(6) ?: return null
        val d = m.group(4) ?: return null
        val t = m.group(5) ?: return null
        val balCur = normalizeCurrency(m.group(7)?.uppercase(Locale.getDefault()) ?: "BHD")
        val bal = m.group(8)?.toDoubleOrNull()
        val ts = parseDdMmYyyyAndTime(d, t, postTime)
        return ParsedTransaction(
            amountValue = amount,
            amountCurrency = cur,
            balanceValue = bal,
            balanceCurrency = balCur,
            merchant = "Fawri+ transfer credited",
            referenceNumber = ref,
            detectedBank = "ila",
            timestampMillis = ts,
            transactionType = "income",
            matchedIncomeKeyword = "Fawri+ transfer credited",
            matchedExpenseKeyword = null,
            reasonForTypeDecision = "ila Fawri+ transfer template",
        )
    }

    private fun tryParseIlaCardPurchase(raw: String, postTime: Long): ParsedTransaction? {
        val m = ilaCardPurchasePattern.matcher(raw)
        if (!m.find()) return null
        var merchant = m.group(1)?.trim().orEmpty()
        if (merchant.isEmpty()) return null
        merchant = merchant.uppercase(Locale.getDefault()).split("  ").first().trim()
        val amount = m.group(4)?.toDoubleOrNull() ?: return null
        val cur = normalizeCurrency(m.group(3)?.uppercase(Locale.getDefault()) ?: "BHD")
        val d = m.group(5) ?: return null
        val t = m.group(6) ?: return null
        val balCur = normalizeCurrency(m.group(7)?.uppercase(Locale.getDefault()) ?: "BHD")
        val bal = m.group(8)?.toDoubleOrNull()
        val ts = parseDdMmYyyyAndTime(d, t, postTime)
        return ParsedTransaction(
            amountValue = amount,
            amountCurrency = cur,
            balanceValue = bal,
            balanceCurrency = balCur,
            merchant = merchant,
            referenceNumber = null,
            detectedBank = "ila",
            timestampMillis = ts,
            transactionType = "expense",
            matchedIncomeKeyword = null,
            matchedExpenseKeyword = "Purchase at",
            reasonForTypeDecision = "ila card purchase template",
        )
    }

    private fun tryParseKfhFawriPlusCreditedToIban(
        raw: String,
        title: String?,
        sourcePackage: String?,
        postTime: Long,
    ): ParsedTransaction? {
        val m = kfhFawriPlusCreditedToIbanPattern.matcher(raw)
        if (!m.find()) return null
        val amount = m.group(2)?.toDoubleOrNull() ?: return null
        val cur = normalizeCurrency(m.group(1)?.uppercase(Locale.getDefault()) ?: "BHD")
        val ref = m.group(3) ?: return null
        val d = m.group(5) ?: return null
        val t = m.group(6) ?: return null
        val ts = parseDdMmYyyyAndTime(d, t, postTime)
        return ParsedTransaction(
            amountValue = amount,
            amountCurrency = cur,
            balanceValue = null,
            balanceCurrency = null,
            merchant = "Fawri+ payment credited to IBAN",
            referenceNumber = ref,
            detectedBank = kfhDetectedBank(raw, title, sourcePackage),
            timestampMillis = ts,
            transactionType = "income",
            matchedIncomeKeyword = "credited to IBAN",
            matchedExpenseKeyword = null,
            reasonForTypeDecision = "KFH Fawri+ credited to IBAN template",
        )
    }

    private fun tryParseKfhFawriPlusReceivedFromIban(
        raw: String,
        title: String?,
        sourcePackage: String?,
        postTime: Long,
    ): ParsedTransaction? {
        val m = kfhFawriPlusReceivedFromIbanPattern.matcher(raw)
        if (!m.find()) return null
        val amount = m.group(2)?.toDoubleOrNull() ?: return null
        val cur = normalizeCurrency(m.group(1)?.uppercase(Locale.getDefault()) ?: "BHD")
        val ref = m.group(3) ?: return null
        val d = m.group(5) ?: return null
        val t = m.group(6) ?: return null
        val ts = parseDdMmYyyyAndTime(d, t, postTime)
        return ParsedTransaction(
            amountValue = amount,
            amountCurrency = cur,
            balanceValue = null,
            balanceCurrency = null,
            merchant = "Fawri+ payment received from IBAN",
            referenceNumber = ref,
            detectedBank = kfhDetectedBank(raw, title, sourcePackage),
            timestampMillis = ts,
            transactionType = "income",
            matchedIncomeKeyword = "received from IBAN",
            matchedExpenseKeyword = null,
            reasonForTypeDecision = "KFH Fawri+ received from IBAN template",
        )
    }

    private fun tryParseKfhFawriCredited(
        raw: String,
        title: String?,
        sourcePackage: String?,
        postTime: Long,
    ): ParsedTransaction? {
        val m = kfhFawriCreditedPattern.matcher(raw)
        if (!m.find()) return null
        val ref = m.group(1) ?: return null
        val amount = m.group(4)?.toDoubleOrNull() ?: return null
        val cur = normalizeCurrency(m.group(3)?.uppercase(Locale.getDefault()) ?: "BHD")
        val d = m.group(6) ?: return null
        val t = m.group(7) ?: return null
        val ts = parseDdMmYyyyAndTime(d, t, postTime)
        return ParsedTransaction(
            amountValue = amount,
            amountCurrency = cur,
            balanceValue = null,
            balanceCurrency = null,
            merchant = "Fawri payment received",
            referenceNumber = ref,
            detectedBank = kfhDetectedBank(raw, title, sourcePackage),
            timestampMillis = ts,
            transactionType = "income",
            matchedIncomeKeyword = "Fawri payment received",
            matchedExpenseKeyword = null,
            reasonForTypeDecision = "KFH Fawri credited template",
        )
    }

    private fun tryParseKfhCardPurchase(
        raw: String,
        title: String?,
        sourcePackage: String?,
        postTime: Long,
    ): ParsedTransaction? {
        val m = kfhCardPurchasePattern.matcher(raw)
        if (!m.find()) return null
        var merchant = m.group(2)?.trim().orEmpty()
        if (merchant.isEmpty()) return null
        merchant = merchant.uppercase(Locale.getDefault()).split("  ").first().trim()
        val amount = m.group(4)?.toDoubleOrNull() ?: return null
        val cur = normalizeCurrency(m.group(3)?.uppercase(Locale.getDefault()) ?: "BHD")
        val day = m.group(5)?.toIntOrNull() ?: return null
        val mon = m.group(6) ?: return null
        val timePart = m.group(7) ?: return null
        val balCur = normalizeCurrency(m.group(8)?.uppercase(Locale.getDefault()) ?: "BHD")
        val bal = m.group(9)?.toDoubleOrNull()
        val ts = parseDdMmmAndTime(day, mon, timePart, postTime)
        return ParsedTransaction(
            amountValue = amount,
            amountCurrency = cur,
            balanceValue = bal,
            balanceCurrency = balCur,
            merchant = merchant,
            referenceNumber = null,
            detectedBank = kfhDetectedBank(raw, title, sourcePackage),
            timestampMillis = ts,
            transactionType = "expense",
            matchedIncomeKeyword = null,
            matchedExpenseKeyword = "purchase on your card",
            reasonForTypeDecision = "KFH card purchase template",
        )
    }

    private fun kfhDetectedBank(raw: String, title: String?, sourcePackage: String?): String {
        val hay = "${title.orEmpty()} $raw ${sourcePackage.orEmpty()}".lowercase(Locale.getDefault())
        return if (hay.contains("kuwait finance") || hay.contains("kfh") || hay.contains("17221999")) {
            "KFH"
        } else {
            detectBank(raw, title, sourcePackage)
        }
    }

    private fun parseDdMmYyyyAndTime(date: String, time: String, fallbackMillis: Long): Long {
        val dparts = date.split("/")
        if (dparts.size != 3) return fallbackMillis
        val dd = dparts[0].toIntOrNull() ?: return fallbackMillis
        val mm = dparts[1].toIntOrNull() ?: return fallbackMillis
        val yyyy = dparts[2].toIntOrNull() ?: return fallbackMillis
        val hhmm = time.split(":")
        val h = hhmm.getOrNull(0)?.toIntOrNull() ?: return fallbackMillis
        val mi = hhmm.getOrNull(1)?.toIntOrNull() ?: return fallbackMillis
        val sec = hhmm.getOrNull(2)?.toIntOrNull() ?: 0
        val cal = Calendar.getInstance()
        cal.set(Calendar.YEAR, yyyy)
        cal.set(Calendar.MONTH, mm - 1)
        cal.set(Calendar.DAY_OF_MONTH, dd)
        cal.set(Calendar.HOUR_OF_DAY, h)
        cal.set(Calendar.MINUTE, mi)
        cal.set(Calendar.SECOND, sec)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun parseDdMmmAndTime(day: Int, monAbbr: String, time: String, fallbackMillis: Long): Long {
        val month = monthAbbrToCalendar(monAbbr) ?: return fallbackMillis
        val hhmm = time.split(":")
        val h = hhmm.getOrNull(0)?.toIntOrNull() ?: return fallbackMillis
        val mi = hhmm.getOrNull(1)?.toIntOrNull() ?: return fallbackMillis
        val sec = hhmm.getOrNull(2)?.toIntOrNull() ?: 0
        val ref = Calendar.getInstance()
        ref.timeInMillis = fallbackMillis
        val year = ref.get(Calendar.YEAR)
        val cal = Calendar.getInstance()
        cal.set(Calendar.YEAR, year)
        cal.set(Calendar.MONTH, month)
        cal.set(Calendar.DAY_OF_MONTH, day)
        cal.set(Calendar.HOUR_OF_DAY, h)
        cal.set(Calendar.MINUTE, mi)
        cal.set(Calendar.SECOND, sec)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun monthAbbrToCalendar(mon: String): Int? {
        return when (mon.take(3).lowercase(Locale.ENGLISH)) {
            "jan" -> Calendar.JANUARY
            "feb" -> Calendar.FEBRUARY
            "mar" -> Calendar.MARCH
            "apr" -> Calendar.APRIL
            "may" -> Calendar.MAY
            "jun" -> Calendar.JUNE
            "jul" -> Calendar.JULY
            "aug" -> Calendar.AUGUST
            "sep" -> Calendar.SEPTEMBER
            "oct" -> Calendar.OCTOBER
            "nov" -> Calendar.NOVEMBER
            "dec" -> Calendar.DECEMBER
            else -> null
        }
    }

    private fun extractAmount(text: String): Pair<String, Double>? {
        val m = amountPattern.matcher(text)
        while (m.find()) {
            val currency = m.group(1)?.uppercase(Locale.getDefault()) ?: continue
            val amount = m.group(2)?.toDoubleOrNull() ?: continue
            val start = m.start()
            val contextStart = maxOf(0, start - 45)
            val context = text.substring(contextStart, start).lowercase(Locale.getDefault())
            // Never treat balances/references/account details as transaction amount.
            val blocked = listOf(
                "ref", "reference",
                "date", "time", "tel", "phone", "avail bal", "available balance", "balance", "bal:",
                "your balance", "a/c bal"
            ).any { context.contains(it) }
            if (!blocked) return normalizeCurrency(currency) to amount
        }
        return null
    }

    private fun extractBalance(text: String): Pair<String, Double>? {
        val m = balancePattern.matcher(text)
        if (!m.find()) return null
        val currency = normalizeCurrency(m.group(1)?.uppercase(Locale.getDefault()) ?: return null)
        val rawAmount = m.group(2) ?: return null
        val amount = if (rawAmount.startsWith(".")) "0$rawAmount".toDoubleOrNull() else rawAmount.toDoubleOrNull()
        return if (amount == null) null else currency to amount
    }

    private fun normalizeCurrency(code: String): String {
        return if (code == "BD") "BHD" else code
    }

    private data class TypeDecision(
        val transactionType: String,
        val matchedIncomeKeyword: String?,
        val matchedExpenseKeyword: String?,
        val reason: String,
    )

    private fun detectTransactionType(text: String): TypeDecision {
        val l = text.lowercase(Locale.getDefault())
        val hasFromIbanCreditedToAcct = l.contains("from iban") && l.contains("credited to acct")
        val hasPaymentCreditedTo = l.contains("payment of") && l.contains("credited to")
        val hasDebitedFromAccount = l.contains("has been debited") || l.contains("debited from your account")
        val matchedIncomeKeyword = incomeKeywords.firstOrNull { l.contains(it) }
        val matchedExpenseKeyword = expenseKeywords.firstOrNull { l.contains(it) }
        val matchedExpenseOverride = expenseOverrideKeywords.firstOrNull { l.contains(it) }
        val matchedIncomeContext = incomeContextKeywords.firstOrNull { l.contains(it) }
        val matchedExpenseContext = expenseContextKeywords.firstOrNull { l.contains(it) }

        // 0) Strict always-expense phrases.
        if (hasDebitedFromAccount) {
            return TypeDecision(
                transactionType = "expense",
                matchedIncomeKeyword = matchedIncomeKeyword,
                matchedExpenseKeyword = "debited from your account",
                reason = "strict expense phrase matched",
            )
        }
        if (hasPaymentCreditedTo) {
            return TypeDecision(
                transactionType = "expense",
                matchedIncomeKeyword = matchedIncomeKeyword,
                matchedExpenseKeyword = "payment of ... credited to",
                reason = "outgoing payment credited to another account",
            )
        }

        // 1) Strict inbound transfer phrase.
        if (hasFromIbanCreditedToAcct) {
            return TypeDecision(
                transactionType = "income",
                matchedIncomeKeyword = "from iban ... credited to acct",
                matchedExpenseKeyword = matchedExpenseKeyword,
                reason = "strict inbound transfer phrase matched",
            )
        }

        // 2) Debit/card purchase keywords override everything.
        if (matchedExpenseOverride != null) {
            return TypeDecision(
                transactionType = "expense",
                matchedIncomeKeyword = matchedIncomeKeyword,
                matchedExpenseKeyword = matchedExpenseOverride,
                reason = "expense override keyword matched",
            )
        }

        // 3) "received from"/"was credited by"/"your account was credited" signals incoming funds.
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
            val isInbound = matchedIncomeContext != null || l.contains("received from") || l.contains("was credited by")
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
        if (l.contains("google*play") || l.contains("google play")) return "GOOGLE PLAY"
        if (l.contains("benefitpay") || l.contains("benefit") || l.contains("fawri")) {
            return "Transfer/Fawri+"
        }
        if (l.contains("al salam bank") && l.contains("debited")) return "Al Salam Bank"
        val at = merchantAtPattern.matcher(text)
        if (at.find()) {
            val raw = at.group(1)?.trim().orEmpty()
            if (raw.isNotEmpty()) {
                val upper = raw.uppercase(Locale.getDefault())
                if (upper.contains("TALABAT")) return "TALABAT"
                if (upper.contains("GOOGLE*PLAY") || upper.contains("GOOGLE PLAY")) return "GOOGLE PLAY"
                return upper.split("  ").first().trim()
            }
        }
        if (!title.isNullOrBlank()) return title.trim()
        return "Bank transaction"
    }

    private fun extractReference(text: String): String? {
        val m = referencePattern.matcher(text)
        return if (m.find()) m.group(1)?.trim() else null
    }

    private fun detectBank(text: String, title: String?, sourcePackage: String?): String {
        val hay = "$title $text ${sourcePackage.orEmpty()}".lowercase(Locale.getDefault())
        return when {
            hay.contains("al salam bank") -> "Al Salam Bank"
            hay.contains("nbb") || hay.contains("national bank of bahrain") -> "NBB-style Fawri+"
            hay.contains("bbk") || hay.contains("bank of bahrain and kuwait") -> "BBK"
            hay.contains("bisb") || hay.contains("bahrain islamic bank") -> "BisB"
            hay.contains("benefitpay") || hay.contains("benefit") -> "BenefitPay"
            hay.contains("kuwait finance house") || hay.contains("kfh") -> "KFH"
            hay.contains("ila bank") || hay.contains("ilabank") -> "ila"
            else -> "Unknown"
        }
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
                val time = m.group(2)
                val fmt = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault())
                fmt.timeZone = TimeZone.getDefault()
                val parsed = runCatching { fmt.parse("${date ?: ""} ${time ?: ""}".trim()) }.getOrNull()
                if (parsed != null) return parsed.time
            }
        }
        ddmmyyPattern.matcher(text).let { m ->
            if (m.find()) {
                val date = m.group(1) ?: return@let
                val time = m.group(2) ?: return@let
                val parts = date.split("/")
                if (parts.size != 3) return@let
                val dd = parts[0]
                val mm = parts[1]
                val yy = parts[2].toIntOrNull() ?: return@let
                val yyyy = if (yy in 0..69) 2000 + yy else 1900 + yy
                val fmt = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault())
                fmt.timeZone = TimeZone.getDefault()
                val parsed = runCatching { fmt.parse("$dd/$mm/$yyyy $time") }.getOrNull()
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

