import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/transaction_model.dart';

/// PDF Report Generator Service for PaymentGuard PH
class PdfReportService {
  /// Generates a PDF Daily Sales Report with Store Header, 3 Metrics Boxes, and Transaction Table.
  static Future<Uint8List> generateDailyPdfReport({
    required List<TransactionModel> transactions,
    required String storeName,
    required String ownerName,
  }) async {
    final pdf = pw.Document();

    // Fetch TTF fonts with full Unicode support (handles ₱ Peso sign cleanly)
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final myTheme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
    );

    final now = DateTime.now();
    final isToday = (DateTime dt) => dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final todayTxs = transactions.where((t) => isToday(t.timestamp)).toList();

    final double todayRevenue = todayTxs
        .where((t) => !t.isScam)
        .fold(0.0, (sum, t) => sum + (t.amount ?? 0.0));
    final int todayCount = todayTxs.where((t) => !t.isScam).length;
    final int todayScams = todayTxs.where((t) => t.isScam).length;

    final currencyFormatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
    final dateStr = DateFormat('MMMM dd, yyyy').format(now);
    final timeFormat = DateFormat('hh:mm a');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: myTheme,
        build: (pw.Context context) {
          return [
            // 1. Dark Navy Header Banner
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#0F172A'),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        storeName,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Store Owner: $ownerName',
                        style: pw.TextStyle(
                          color: PdfColor.fromHex('#00E676'),
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'DAILY SALES REPORT',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        dateStr,
                        style: const pw.TextStyle(
                          color: PdfColors.grey300,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // 2. Summary Metric Boxes
            pw.Row(
              children: [
                pw.Expanded(
                  child: _buildPdfMetricBox(
                    title: 'Total Revenue Today',
                    value: currencyFormatter.format(todayRevenue),
                    color: PdfColor.fromHex('#00E676'),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: _buildPdfMetricBox(
                    title: 'Total Transactions',
                    value: '$todayCount Orders',
                    color: PdfColors.blue,
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: _buildPdfMetricBox(
                    title: 'Scam Attempts Blocked',
                    value: '$todayScams Attempted',
                    color: PdfColors.orangeAccent,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // 3. Transactions Table
            pw.Text(
              'Transactions Log',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#0F172A')),
            ),
            pw.SizedBox(height: 10),

            pw.Table.fromTextArray(
              headers: ['Time', 'E-Wallet', 'Payer Name', 'Amount', 'Reference No', 'Status'],
              data: transactions.map((tx) {
                final time = timeFormat.format(tx.timestamp);
                final source = tx.provider.isNotEmpty ? tx.provider : tx.source;
                final sender = tx.senderName.isNotEmpty ? tx.senderName : 'N/A';
                final amount = tx.amount != null ? '₱${tx.amount!.toStringAsFixed(2)}' : '₱0.00';
                final ref = tx.refNumber.isNotEmpty ? tx.refNumber : 'NO_REF';

                String status = 'VERIFIED';
                if (tx.isScam) {
                  status = 'PHISHING BLOCKED';
                } else if (tx.isDuplicate) {
                  status = 'DUPLICATE';
                }

                return [time, source, sender, amount, ref, status];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#1E293B'),
              ),
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildPdfMetricBox({
    required String title,
    required String value,
    required PdfColor color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
