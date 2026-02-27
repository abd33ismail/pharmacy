import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'datdbase.dart';
import 'inventory.dart';
import 'expiration.dart';
import 'daily-reports.dart';
import 'notes.dart';
import 'barcode-image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _totalItems = 0;
  int _expirationAlerts = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshData();
  }

  // -----------------------
  // تحديث البيانات
  // -----------------------
  Future<void> _refreshData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final total = await DatabaseHelper.instance.getTotalProductCount();
    final alerts = await DatabaseHelper.instance.getExpirationAlertsCount();

    if (mounted) {
      setState(() {
        _totalItems = total;
        _expirationAlerts = alerts;
        _isLoading = false;
      });
    }
  }

  // -----------------------
  // بناء واجهة البطاقة
  // -----------------------
  Widget _buildDashboardCard(
      BuildContext context,
      String title,
      String value,
      IconData icon,
      Color color, {
        VoidCallback? onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 4,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------
  // واجهة الصفحة
  // -----------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('app_title'.tr()),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _buildDashboardCard(
              context,
              'number_of_items'.tr(),
              _totalItems.toString(),
              Icons.inventory_2,
              Colors.blue,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const InventoryScreen()),
                );
                _refreshData();
              },
            ),
            _buildDashboardCard(
              context,
              'expiration_alerts'.tr(),
              _expirationAlerts.toString(),
              Icons.warning_amber_rounded,
              Colors.orange,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ExpirationScreen()),
                );
                _refreshData();
              },
            ),
            _buildDashboardCard(
              context,
              'today_sales'.tr(),
              '',
              Icons.attach_money,
              Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DailyReportsScreen()),
                );
              },
            ),
            _buildDashboardCard(
              context,
              'notes'.tr(),
              '',
              Icons.note_alt,
              Colors.brown,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotesScreen()),
                );
              },
            ),
            _buildDashboardCard(
              context,
              'scan_product'.tr(),
              '',
              Icons.camera_alt,
              Colors.purple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BarcodeImageScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
