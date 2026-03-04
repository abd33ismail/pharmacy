import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:pharmacy/currency_service.dart';
import 'add-edd-product.dart';
import 'datdbase.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allProducts = [];
  bool _isLoading = true;

  final List<String> _categories = ['Medicines', 'Prescriptions', 'Supplies', 'Accessories'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _refreshProducts();
  }

  Future<void> _refreshProducts() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllProducts();
    setState(() {
      _allProducts = data;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getFilteredProducts(String category) {
    return _allProducts
        .where((p) => p['category'].toString().toLowerCase() == category.toLowerCase())
        .where((p) => p['name'].toString().toLowerCase().contains(_searchController.text.toLowerCase()))
        .toList();
  }

  void _showOptions(BuildContext context, Map<String, dynamic> product) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: Text('edit_product'.tr()),
            onTap: () async {
              Navigator.pop(context);
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddProductScreen(product: product)),
              );
              if (result == true) _refreshProducts();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text('delete_product'.tr()),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context, product['product_id']);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('delete'.tr()),
        content: Text('are_you_sure_delete'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr())),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteProduct(id);
              Navigator.pop(context);
              _refreshProducts();
            },
            child: Text('delete'.tr(), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('inventory'.tr()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(125),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'search_product'.tr(),
                  leading: const Icon(Icons.search),
                  onChanged: (val) => setState(() {}),
                  elevation: WidgetStateProperty.all(0),
                  backgroundColor: WidgetStateProperty.all(Colors.grey[200]),
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: _categories.map((c) => Tab(text: c.toLowerCase().tr())).toList(),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: _categories.map((c) => _buildProductList(c)).toList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddProductScreen()),
          );
          if (result == true) _refreshProducts();
        },
        tooltip: 'add_product'.tr(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildProductList(String category) {
    final products = _getFilteredProducts(category);
    if (products.isEmpty) return Center(child: Text('no_products_found'.tr()));

    return ListView.builder(
      itemCount: products.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final product = products[index];

        final saleCurrencyStr = product['sale_currency'] as String?;
        final saleCurrency = saleCurrencyStr == 'usd' ? Currency.usd : Currency.syp;
        final currencySymbol = currencyLabel(saleCurrency);

        final price = (product['sale_price'] as num?)?.toDouble() ?? 0.0;
        final expiryDate = product['expiry_date'] as String?;

        return Card(
          child: ListTile(
            onTap: () => _showOptions(context, product),
            leading: const CircleAvatar(child: Icon(Icons.medication)),
            title: Text(product['name'] as String),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${'stock'.tr()}: ${product['quantity']}'),
                if (expiryDate != null && expiryDate.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text('${'expiry_date'.tr()}: $expiryDate', style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            trailing: Text(
              '$currencySymbol${formatPrice(price)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
        );
      },
    );
  }
}