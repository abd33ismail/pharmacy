import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'datdbase.dart';
import 'inventory.dart';
import 'expiration.dart';
import 'daily-reports.dart';
import 'notes.dart';
import 'barcode-image.dart';
import 'daily_invoices_report.dart';

// --- Widget الأيقونة المتحركة ✨ ---
class AnimatedIconWidget extends StatefulWidget {
  final IconData icon;
  final Color color;

  const AnimatedIconWidget({
    super.key,
    required this.icon,
    required this.color,
  });

  @override
  State<AnimatedIconWidget> createState() => _AnimatedIconWidgetState();
}

class _AnimatedIconWidgetState extends State<AnimatedIconWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Icon(widget.icon, size: 40, color: widget.color),
    );
  }
}

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

  Future<void> _refreshData() async {
    try {
      final total = await DatabaseHelper.instance.getTotalProductCount();
      final alerts = await DatabaseHelper.instance.getExpirationAlertsCount();

      if (mounted) {
        setState(() {
          _totalItems = total;
          _expirationAlerts = alerts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error refreshing data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9FF),
      appBar: AppBar(
        title: const Text('Pharmacy', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        centerTitle: true,
        backgroundColor: const Color(0xFFD1C4E9),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
                children: [
                  _buildDashboardCard(
                    context,
                    'number_of_items'.tr(),
                    _totalItems.toString(),
                    Icons.inventory_2,
                    Colors.blue,
                    const InventoryScreen(),
                  ),
                  _buildDashboardCard(
                    context,
                    'expiration_alerts'.tr(),
                    _expirationAlerts.toString(),
                    Icons.warning_amber_rounded,
                    Colors.orange,
                    const ExpirationScreen(),
                  ),
                  _buildDashboardCard(
                    context,
                    'today_sales'.tr(),
                    '',
                    Icons.attach_money,
                    Colors.green,
                    const DailyReportsScreen(),
                  ),
                  _buildDashboardCard(
                    context,
                    'daily_invoices'.tr(),
                    '',
                    Icons.receipt_long,
                    Colors.teal,
                    const DailyInvoicesReport(),
                  ),
                  _buildDashboardCard(
                    context,
                    'notes'.tr(),
                    '',
                    Icons.edit_note,
                    Colors.brown,
                    const NotesScreen(),
                  ),
                  _buildDashboardCard(
                    context,
                    'scan_product'.tr(),
                    '',
                    Icons.camera_alt,
                    const Color(0xFFAB47BC),
                    const BarcodeImageScreen(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDashboardCard(BuildContext context, String title, String value, IconData icon, Color color, Widget screen) {
    return InkWell(
      onTap: () async {
        // حركة Bounce خفيفة عند الضغط 🎬
        await Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (context, animation, secondaryAnimation) => screen,
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOutBack,
                ),
                child: child,
              );
            },
          ),
        );
        _refreshData();
      },
      child: Card(
        elevation: 3,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // استخدام الـ Widget المتحرك هنا ✨
              AnimatedIconWidget(icon: icon, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
