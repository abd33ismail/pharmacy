import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'datdbase.dart';

class DailyInvoicesReport extends StatefulWidget {
  const DailyInvoicesReport({super.key});

  @override
  State<DailyInvoicesReport> createState() => _DailyInvoicesReportState();
}

class _DailyInvoicesReportState extends State<DailyInvoicesReport> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchInvoices();
  }

  Future<void> _fetchInvoices() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getTodayInvoices(_selectedDate);
    setState(() {
      _invoices = data;
      _isLoading = false;
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchInvoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('daily_sales_report').tr(),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDate(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _invoices.isEmpty
              ? Center(child: const Text('no_sales_found').tr())
              : ListView.builder(
                  itemCount: _invoices.length,
                  itemBuilder: (context, index) {
                    final invoice = _invoices[index];
                    final saleDate = DateTime.parse(invoice['sale_date']);
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: invoice['edited'] == 1 ? Colors.orange : Colors.blue,
                          child: Text('#${invoice['sale_id']}'),
                        ),
                        title: Text(
                          DateFormat('hh:mm a').format(saleDate),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${invoice['items_count']} ${'items'.tr()}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${invoice['total_amount']} ',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 16),
                          ],
                        ),
                        onTap: () => _showInvoiceDetails(invoice['sale_id']),
                      ),
                    );
                  },
                ),
    );
  }

  void _showInvoiceDetails(int saleId) async {
    final details = await DatabaseHelper.instance.getInvoiceDetails(saleId);
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${'invoice_details'.tr()} #$saleId', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: details.length,
                itemBuilder: (context, index) {
                  final item = details[index];
                  return ListTile(
                    title: Text(item['name']),
                    subtitle: Text('${item['quantity']} x ${item['price']} ${item['sale_currency'] ?? ''}'),
                    trailing: Text('${(item['quantity'] * item['price']).toStringAsFixed(2)}'),
                  );
                },
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text('modify_invoice').tr(),
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('feature_coming_soon'.tr())),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      icon: const Icon(Icons.undo),
                      label: const Text('refund').tr(),
                      onPressed: () => _confirmRefund(saleId, details),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRefund(int saleId, List<Map<String, dynamic>> items) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('confirm_refund').tr(),
        content: const Text('are_you_sure_refund_invoice').tr(),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('cancel').tr()),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.createRefund(saleId, items);
              if (!mounted) return;
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close bottom sheet
              _fetchInvoices();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: const Text('refund_successful').tr()),
              );
            },
            child: Text('confirm'.tr(), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
