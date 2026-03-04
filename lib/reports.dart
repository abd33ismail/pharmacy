import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'daily-reports.dart';
import 'monthly-reports.dart';
import 'daily_invoices_report.dart'; // استيراد التقرير الجديد

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('reports'.tr()),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildButton(
              context,
              title: 'daily_report'.tr(),
              icon: Icons.today,
              screen: const DailyReportsScreen(),
            ),
            const SizedBox(height: 20),
            // إضافة زر تقرير الفواتير اليومي الجديد
            _buildButton(
              context,
              title: 'invoices_report'.tr(),
              icon: Icons.receipt_long,
              screen: const DailyInvoicesReport(),
            ),
            const SizedBox(height: 20),
            _buildButton(
              context,
              title: 'monthly_report'.tr(),
              icon: Icons.calendar_month,
              screen: const MonthlyReportsScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(
      BuildContext context, {
        required String title,
        required IconData icon,
        required Widget screen,
      }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(title),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          );
        },
      ),
    );
  }
}
