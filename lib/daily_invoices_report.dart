import 'dart:async';
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
  StreamSubscription? _dbSubscription;

  // ✅ قائمة المعرفات المحددة
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _fetchInvoices();
    _dbSubscription = DatabaseHelper.instance.onDatabaseChanged.listen((_) {
      _fetchInvoices(showLoading: false);
    });
  }

  @override
  void dispose() {
    _dbSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchInvoices({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getTodayInvoices(_selectedDate);
    if (mounted) {
      setState(() {
        _invoices = data;
        _isLoading = false;
      });
    }
  }

  // ✅ منطق التحديد
  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  void _selectAll() {
    setState(() {
      for (var inv in _invoices) {
        _selectedIds.add(inv['sale_id'] as int);
      }
    });
  }

  Future<void> _deleteSelectedInvoices() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("confirm_delete").tr(),
        content: Text("${'confirm_delete_selected'.tr()} ($count)"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("cancel").tr(),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("delete").tr(),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      for (final id in _selectedIds) {
        await DatabaseHelper.instance.deleteSale(id);
      }
      _selectedIds.clear();
      await _fetchInvoices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('invoices_deleted_successfully'.tr())),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      _clearSelection();
      setState(() => _selectedDate = picked);
      _fetchInvoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelectionMode = _selectedIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        // ✅ شكل الـ AppBar يتغير عند التحديد
        leading: isSelectionMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection)
            : null,
        title: isSelectionMode
            ? Text('${_selectedIds.length}')
            : const Text('daily_sales_report').tr(),
        actions: isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAll,
                  tooltip: 'select_all'.tr(),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _deleteSelectedInvoices,
                  tooltip: 'delete'.tr(),
                ),
              ]
            : [
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
                    final saleId = invoice['sale_id'] as int;
                    final isSelected = _selectedIds.contains(saleId);
                    final saleDate = DateTime.parse(invoice['sale_date']);
                    final isRefunded = (invoice['is_refunded'] as int? ?? 0) > 0;
                    final isSynced = (invoice['synced'] as int? ?? 0) == 1;
                    final String displayId = invoice['invoice_daily'] != null 
                        ? invoice['invoice_daily'].toString().split('-').last 
                        : invoice['sale_id'].toString();
                    
                    return Dismissible(
                      key: Key(saleId.toString()),
                      // تعطيل السحب عند وجود تحديد
                      direction: isSelectionMode ? DismissDirection.none : DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white, size: 30),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("confirm_delete").tr(),
                            content: const Text("are_you_sure_delete_invoice").tr(),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text("cancel").tr(),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text("delete").tr(),
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (direction) async {
                        await DatabaseHelper.instance.deleteSale(saleId);
                        _fetchInvoices();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: const Text("invoice_deleted").tr()),
                        );
                      },
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        // ✅ تغيير لون الكرت المختار
                        color: isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
                        elevation: isSelected ? 0 : 1,
                        child: ListTile(
                          selected: isSelected,
                          onLongPress: () => _toggleSelection(saleId), // ✅ الضغط المطول للتحديد
                          onTap: isSelectionMode 
                              ? () => _toggleSelection(saleId) // ✅ النقر العادي للتحديد إذا كان الوضع مفعلاً
                              : () => _showInvoiceDetails(invoice), // ✅ النقر العادي لعرض التفاصيل
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                backgroundColor: isRefunded 
                                  ? Colors.grey 
                                  : (invoice['edited'] == 1 ? Colors.orange : Colors.blue),
                                child: Text('#$displayId', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              if (isSelected) // ✅ علامة صح عند التحديد
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.check, color: Colors.white, size: 20),
                                  ),
                                ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Text(
                                DateFormat('hh:mm a').format(saleDate),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (isRefunded) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(4)),
                                  child: Text('refunded'.tr(), style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ]
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${invoice['items_count']} ${'items'.tr()}'),
                              if (invoice['invoice_daily'] != null)
                                Text(invoice['invoice_daily'], style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSelected) 
                                const Icon(Icons.check_circle, color: Colors.blue)
                              else ...[
                                if (isSynced)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8.0),
                                    child: Icon(Icons.cloud_done, color: Colors.green, size: 18),
                                  ),
                                Text(
                                  '${invoice['total_amount']} ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    color: isRefunded ? Colors.grey : Colors.green,
                                    decoration: isRefunded ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios, size: 16),
                              ]
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showInvoiceDetails(Map<String, dynamic> invoice) async {
    final saleId = invoice['sale_id'] as int;
    final String fullInvoiceNum = invoice['invoice_daily'] ?? '#$saleId';
    final isRefunded = (invoice['is_refunded'] as int? ?? 0) > 0;
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
                Expanded(
                  child: Text(
                    '${'invoice_details'.tr()} $fullInvoiceNum', 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                      onPressed: isRefunded ? null : () {
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
                      onPressed: isRefunded ? null : () => _confirmRefund(saleId, details),
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
