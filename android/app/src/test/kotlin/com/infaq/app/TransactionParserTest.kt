package com.infaq.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class TransactionParserTest {
    @Test
    fun debitCardTalabat_isExpense() {
        val msg =
            "Dear AHMED, thank you for using your Debit card xxx5 for BHD 3.380 at TALABAT SERVICES on 05/05 @19:17. Avail Bal BHD 7.983."
        val parsed = TransactionParser.parse("BBK", msg, "com.bank", System.currentTimeMillis())
        assertNotNull(parsed)
        assertEquals("expense", parsed!!.transactionType)
    }

    @Test
    fun bbkCardGooglePlay_isExpense() {
        val msg =
            "Thank you for using BBK CARD xxxx for BHD 1.200 at GOOGLE PLAY on 03/05/2026 13:55. Balance BHD 10.000."
        val parsed = TransactionParser.parse("BBK", msg, "com.bank", System.currentTimeMillis())
        assertNotNull(parsed)
        assertEquals("expense", parsed!!.transactionType)
    }

    @Test
    fun fawriReceivedCreditedBy_isIncome() {
        val msg =
            "Your account was credited by BHD3.400 from Fawri+ sender on 2026/05/07 13:51. Balance BHD7.350."
        val parsed = TransactionParser.parse("BisB", msg, "com.bank", System.currentTimeMillis())
        assertNotNull(parsed)
        assertEquals("income", parsed!!.transactionType)
    }

    @Test
    fun transferSentCreditedToAnotherIban_isExpense() {
        val msg =
            "Transfer sent to IBAN ending 3001. Amount BHD 5.000 was credited to IBAN ending 6237 on 2026/05/07 19:20."
        val parsed = TransactionParser.parse("BisB", msg, "com.bank", System.currentTimeMillis())
        assertNotNull(parsed)
        assertEquals("expense", parsed!!.transactionType)
    }

    @Test
    fun creditedToOnly_notAutoIncome() {
        val msg =
            "Payment made BHD 2.000 credited to IBAN ending 6237 on 2026/05/07 19:20."
        val parsed = TransactionParser.parse("BisB", msg, "com.bank", System.currentTimeMillis())
        assertNotNull(parsed)
        assertEquals("expense", parsed!!.transactionType)
    }
}

