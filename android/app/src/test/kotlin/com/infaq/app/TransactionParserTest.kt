package com.infaq.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class TransactionParserTest {
    private fun parseRequired(title: String, msg: String): ParsedTransaction {
        val parsed = TransactionParser.parse(title, msg, "com.bank", System.currentTimeMillis())
        assertNotNull(parsed)
        return parsed!!
    }

    private fun assertDateTime(parsed: ParsedTransaction, expected: String, format: String) {
        val f = SimpleDateFormat(format, Locale.getDefault())
        f.timeZone = TimeZone.getDefault()
        assertEquals(expected, f.format(parsed.timestampMillis))
    }

    @Test
    fun debitCardTalabat_isExpense() {
        val msg =
            "Dear AHMED, thank you for using your Debit card xxx5 for BHD 3.380 at TALABAT SERVICES on 05/05 @19:17. Avail Bal BHD 7.983."
        val parsed = parseRequired("BBK", msg)
        assertEquals("expense", parsed.transactionType)
        assertEquals(3.380, parsed.amountValue, 0.0001)
        assertEquals(7.983, parsed.balanceValue ?: 0.0, 0.0001)
        assertEquals("BBK", parsed.detectedBank)
    }

    @Test
    fun bbkCardGooglePlay_isExpense() {
        val msg =
            "Thank you for using BBK CARD xxxx for BHD 1.200 at GOOGLE*PLAY MOUNTAIN US on 03/05/2026 13:55. Balance BHD 10.000."
        val parsed = parseRequired("BBK", msg)
        assertEquals("expense", parsed.transactionType)
        assertEquals("GOOGLE PLAY", parsed.merchant)
        assertEquals(1.200, parsed.amountValue, 0.0001)
        assertEquals("BHD", parsed.amountCurrency)
        assertEquals("BBK", parsed.detectedBank)
    }

    @Test
    fun fawriReceivedCreditedBy_isIncome() {
        val msg =
            "Your account was credited by BHD3.400 from Fawri+ sender on 2026/05/07 13:51. Balance BHD7.350."
        val parsed = parseRequired("BisB", msg)
        assertEquals("income", parsed.transactionType)
        assertEquals("Fawri+", parsed.merchant)
        assertEquals("BisB", parsed.detectedBank)
    }

    @Test
    fun transferSentCreditedToAnotherIban_isExpense() {
        val msg =
            "Transfer sent to IBAN ending 3001. Amount BHD 5.000 was credited to IBAN ending 6237 on 2026/05/07 19:20."
        val parsed = parseRequired("BisB", msg)
        assertEquals("expense", parsed.transactionType)
    }

    @Test
    fun creditedToOnly_notAutoIncome() {
        val msg =
            "Payment made BHD 2.000 credited to IBAN ending 6237 on 2026/05/07 19:20."
        val parsed = parseRequired("BisB", msg)
        assertEquals("expense", parsed.transactionType)
    }

    @Test
    fun bbkFawriPlusPaymentCreditedTo_isExpense() {
        val msg =
            "Your Fawri+ payment of BHD4.500 was credited to BH02FIBH01028XXXXXXX11 on 05/04/2026 at 10:53 ref:BPA2604052029254.For help 17207777"
        val parsed = parseRequired("BBK", msg)
        assertEquals("BBK", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals("BHD", parsed.amountCurrency)
        assertEquals(4.500, parsed.amountValue, 0.0001)
        assertEquals("Fawri+", parsed.merchant)
        assertEquals("BPA2604052029254", parsed.referenceNumber)
        assertEquals(null, parsed.balanceValue)
        assertDateTime(parsed, "05/04/2026 10:53", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun bbkFawriPlusAccountCreditedByFrom_isIncome() {
        val msg =
            "Your account BH15BBKU00200XXXXXXX05 was credited by BHD10.600 from BH40BIBB00200XXXXXXX22 for Fawri+ on 25/04/2026 08:51 ref:BIB103K5F003RYQN.For help 17207777"
        val parsed = parseRequired("BBK", msg)
        assertEquals("BBK", parsed.detectedBank)
        assertEquals("income", parsed.transactionType)
        assertEquals("BHD", parsed.amountCurrency)
        assertEquals(10.600, parsed.amountValue, 0.0001)
        assertEquals("Fawri+", parsed.merchant)
        assertEquals("BIB103K5F003RYQN", parsed.referenceNumber)
        assertEquals(null, parsed.balanceValue)
        assertDateTime(parsed, "25/04/2026 08:51", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun nbbStyleFawriPlusFromIbanCreditedToAcct_isIncome() {
        val msg =
            "Fawri+ BHD 58.117 ref NBB010226ONQE7AJ from IBAN BH42NBOBXXXXXXXXXXXX97 credited to acct XXX06150000. Bal: BHD 58.117 on 01/02/26 at 21:09. Tel 17005500"
        val parsed = parseRequired("NBB", msg)
        assertEquals("NBB-style Fawri+", parsed.detectedBank)
        assertEquals("income", parsed.transactionType)
        assertEquals("BHD", parsed.amountCurrency)
        assertEquals(58.117, parsed.amountValue, 0.0001)
        assertEquals("Fawri+", parsed.merchant)
        assertEquals("NBB010226ONQE7AJ", parsed.referenceNumber)
        assertEquals("BHD", parsed.balanceCurrency)
        assertEquals(58.117, parsed.balanceValue ?: 0.0, 0.0001)
        assertDateTime(parsed, "01/02/2026 21:09", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun alSalamDebitedFromAccount_isExpense() {
        val msg =
            "Dear Client, BHD 30.000 has been debited from your account XXXX06150000. Your balance is BHD 28.117 on 03/02/26 at 19:05. Thank you, Al Salam Bank."
        val parsed = parseRequired("Al Salam Bank", msg)
        assertEquals("Al Salam Bank", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals("BHD", parsed.amountCurrency)
        assertEquals(30.000, parsed.amountValue, 0.0001)
        assertEquals("Al Salam Bank", parsed.merchant)
        assertEquals("BHD", parsed.balanceCurrency)
        assertEquals(28.117, parsed.balanceValue ?: 0.0, 0.0001)
        assertDateTime(parsed, "03/02/2026 19:05", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun kfhCardPurchase_isExpense_withMerchantAndAvailBal() {
        val msg =
            "Dear Customer, you have a purchase on your card ****1234 at CUT BURGER MANAMA BH for BHD 1.540 on 30-Mar 22:48:43, Avail bal BHD 100.000"
        val parsed = parseRequired("KFH", msg)
        assertEquals("KFH", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(1.540, parsed.amountValue, 0.0001)
        assertEquals("CUT BURGER MANAMA BH", parsed.merchant)
        assertEquals(100.000, parsed.balanceValue ?: 0.0, 0.0001)
        assertEquals("BHD", parsed.balanceCurrency)
    }

    @Test
    fun kfhFawriPlusCreditedToIban_isExpense_outboundPayment() {
        val msg =
            "Dear Customer, Fawri+ payment BD 2.500, Ref. AUB103K5U004426E credited to IBAN BH75BIBB00200004446237 on 10/05/2026 at 15:30. Call 17221999 for Inquiries"
        val parsed = parseRequired("KFH", msg)
        assertEquals("KFH", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(2.500, parsed.amountValue, 0.0001)
        assertEquals("BHD", parsed.amountCurrency)
        assertEquals("AUB103K5U004426E", parsed.referenceNumber)
        assertDateTime(parsed, "10/05/2026 15:30", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun kfhFawriPlusCreditedToIban_legacySample_isExpense() {
        val msg =
            "Dear Customer, Fawri+ payment BD 25.5, Ref. ABC123XY credited to IBAN BH123456789 on 08/05/2026 at 19:08. Call 17221999 for Inquiries"
        val parsed = parseRequired("KFH", msg)
        assertEquals("KFH", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(25.5, parsed.amountValue, 0.0001)
        assertEquals("BHD", parsed.amountCurrency)
        assertEquals("ABC123XY", parsed.referenceNumber)
        assertDateTime(parsed, "08/05/2026 19:08", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun kfhFawriPlusReceivedFromIban_isIncome_exactTemplate() {
        val msg =
            "Dear Customer, Fawri+ payment BHD 12.345, Ref. R9 received from IBAN BH99999999 on 07/05/2026 at 14:10. Call 17221999 for Inquiries"
        val parsed = parseRequired("KFH", msg)
        assertEquals("income", parsed.transactionType)
        assertEquals(12.345, parsed.amountValue, 0.0001)
        assertEquals("Fawri+ payment received from IBAN", parsed.merchant)
        assertEquals("R9", parsed.referenceNumber)
        assertEquals("KFH", parsed.detectedBank)
        assertDateTime(parsed, "07/05/2026 14:10", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun kfhFawriCreditedToAccount_isIncome() {
        val msg =
            "Dear Customer, Fawri payment with ref. FR123 received from BH88IBAN001 BHD 500.12 credited to your *1234 on 15/04/2026 at 09:17. For enquiry please call 17221999"
        val parsed = parseRequired("KFH", msg)
        assertEquals("income", parsed.transactionType)
        assertEquals(500.12, parsed.amountValue, 0.0001)
        assertEquals("Fawri payment received", parsed.merchant)
        assertEquals("FR123", parsed.referenceNumber)
        assertEquals("KFH", parsed.detectedBank)
        assertDateTime(parsed, "15/04/2026 09:17", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun ilaCardPurchase_isExpense_amountNotBalance() {
        val msg =
            "Success! Purchase at GALALI FUEL STATION A using card ****1234 for BHD 10.700 on 04/05/2026 01:25 debited from BHD Ac Balance BHD 100.000 Enquiry 17123456"
        val parsed = parseRequired("ila", msg)
        assertEquals("ila", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(10.700, parsed.amountValue, 0.0001)
        assertEquals("GALALI FUEL STATION A", parsed.merchant)
        assertEquals(100.000, parsed.balanceValue ?: 0.0, 0.0001)
    }

    @Test
    fun ilaFawriPlusTransferCredited_isIncome() {
        val msg =
            "Success! Fawri+ transfer of BHD 3.25 from IBAN BH11CRED01 credited to BHD Ac on 04/05/2026 19:08 Ref XYZ1 Balance BHD 200.5 Enquiry 17123456"
        val parsed = parseRequired("ila", msg)
        assertEquals("ila", parsed.detectedBank)
        assertEquals("income", parsed.transactionType)
        assertEquals(3.25, parsed.amountValue, 0.0001)
        assertEquals("Fawri+ transfer credited", parsed.merchant)
        assertEquals("XYZ1", parsed.referenceNumber)
        assertEquals(200.5, parsed.balanceValue ?: 0.0, 0.0001)
        assertDateTime(parsed, "04/05/2026 19:08", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun ilaFawriPlusSentToIban_isExpense() {
        val msg =
            "Success! Fawri+ transfer of BHD 2.700 to IBAN **3844 is completed on 23/02/2026 05:21 Ref ABCO260223032237 Balance BHD 0.002 Enquiry 17123456"
        val parsed = parseRequired("ila", msg)
        assertEquals("ila", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(2.700, parsed.amountValue, 0.0001)
        assertEquals("BHD", parsed.amountCurrency)
        assertEquals("ABCO260223032237", parsed.referenceNumber)
        assertEquals(0.002, parsed.balanceValue ?: 0.0, 0.0001)
        assertDateTime(parsed, "23/02/2026 05:21", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun ilaFawriPlusAcctCredited_isIncome() {
        val msg =
            "Success! Your BHD Ac credited with BHD 40.000 on 30/12/2025 16:31 Ref BP2512301331274761 Balance BHD 40.000 Enquiry 17123456"
        val parsed = parseRequired("ila", msg)
        assertEquals("ila", parsed.detectedBank)
        assertEquals("income", parsed.transactionType)
        assertEquals(40.000, parsed.amountValue, 0.0001)
        assertEquals("BP2512301331274761", parsed.referenceNumber)
        assertEquals(40.000, parsed.balanceValue ?: 0.0, 0.0001)
        assertDateTime(parsed, "30/12/2025 16:31", "dd/MM/yyyy HH:mm")
    }

    @Test
    fun ilaCardPurchaseUsd_isExpense() {
        val msg =
            "Purchase at AMAZON MARKETPLACE SEATTLE US using card **9499 for USD 98.68 on 30/12/2025 18:24 debited from USD Ac Balance USD 7.18 Enquiry 17123456"
        val parsed = parseRequired("ila", msg)
        assertEquals("ila", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(98.68, parsed.amountValue, 0.0001)
        assertEquals("USD", parsed.amountCurrency)
        assertEquals("AMAZON MARKETPLACE SEATTLE US", parsed.merchant)
        assertEquals(7.18, parsed.balanceValue ?: 0.0, 0.0001)
        assertEquals("USD", parsed.balanceCurrency)
    }

    @Test
    fun nbbFawriPlusSentToIban_isExpense() {
        val msg =
            "Success! Fawri+ transfer of BHD 2.700 to IBAN **3844 is completed on 23/02/2026 05:21 Ref ABCO260223032237 Balance BHD 0.002 Enquiry 17123456"
        val parsed = parseRequired("NBB", msg)
        assertEquals("NBB-style Fawri+", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(2.700, parsed.amountValue, 0.0001)
    }

    @Test
    fun nbbFawriPlusReceived_isIncome() {
        val msg =
            "Fawri+ transfer of BHD 15.500 from Ahmed Ali credited to your account on 08/05/2026 20:06, Ref. NBB123456789, A/C ending 0036 balance BHD 50.000"
        val parsed = parseRequired("NBB", msg)
        assertEquals("NBB-style Fawri+", parsed.detectedBank)
        assertEquals("income", parsed.transactionType)
        assertEquals(15.500, parsed.amountValue, 0.0001)
        assertEquals("NBB123456789", parsed.referenceNumber)
        assertEquals(50.000, parsed.balanceValue ?: 0.0, 0.0001)
    }

    @Test
    fun nbbDebitCardPurchase_isExpense() {
        val msg =
            "Thank you for using NBB Debit Card at IN & OUT PETROL STATIOMANAMA for BHD 25.500 on 05/05/2026 10:37, A/C ending 0036 balance BHD 100.000"
        val parsed = parseRequired("NBB", msg)
        assertEquals("NBB-style Fawri+", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals("IN & OUT PETROL STATIOMANAMA", parsed.merchant)
        assertEquals(25.500, parsed.amountValue, 0.0001)
    }

    @Test
    fun bbkCardMonthNamePurchase_isExpense() {
        val msg =
            "Thank you for using BBK Card ending in 0938 for BHD 2.600 at ILLYCAFFE GRAVITY V BAH BH on May 10 at 11:46. A/C bal BHD XXXX For help"
        val parsed = parseRequired("BBK", msg)
        assertEquals("BBK", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(2.600, parsed.amountValue, 0.0001)
        assertEquals("ILLYCAFFE GRAVITY V BAH BH", parsed.merchant)
    }

    @Test
    fun bisbFawriPlusReceived_isIncome() {
        val msg =
            "Fawri+ payment BHD0.100 received from IBAN ending 6237 credited to IBAN ending 2757 ref. BIB103K5X000FTHG on 2026/05/13 10:45. Balance BHD26.461. Tel: 17515151"
        val parsed = parseRequired("BisB", msg)
        assertEquals("BisB", parsed.detectedBank)
        assertEquals("income", parsed.transactionType)
        assertEquals(0.100, parsed.amountValue, 0.0001)
        assertEquals("BIB103K5X000FTHG", parsed.referenceNumber)
        assertEquals(26.461, parsed.balanceValue ?: 0.0, 0.0001)
    }

    @Test
    fun bisbFawriPlusSent_isExpense() {
        val msg =
            "Fawri+ payment BHD0.100, ref: BIB103K5X000FZ9X was credited to IBAN ending 6237 on 2026/05/13 11:30. Balance BHD26.361. Tel: 17515151"
        val parsed = parseRequired("BisB", msg)
        assertEquals("BisB", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(0.100, parsed.amountValue, 0.0001)
        assertEquals("BIB103K5X000FZ9X", parsed.referenceNumber)
        assertEquals(26.361, parsed.balanceValue ?: 0.0, 0.0001)
    }

    @Test
    fun bisbDebitCardPurchase_isExpense() {
        val msg =
            "Dear AHMED, thank you for using your Debit card 9075 for BHD 0.400 at ARD Alkayrat CafeteriaMANAMA BH-531526 on 12/05 @10:37. Avail Bal BHD 29.381. Tel 17515151"
        val parsed = parseRequired("BisB", msg)
        assertEquals("BisB", parsed.detectedBank)
        assertEquals("expense", parsed.transactionType)
        assertEquals(0.400, parsed.amountValue, 0.0001)
        assertEquals("ARD ALKAYRAT CAFETERIAMANAMA BH-531526", parsed.merchant)
        assertEquals(29.381, parsed.balanceValue ?: 0.0, 0.0001)
    }
}

