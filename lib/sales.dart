import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:pharmacy/currency_service.dart';
import 'datdbase.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  final Map<int, int> _selectedQuantities = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.queryAllProducts();
    setState(() {
      _products = data;
      _filteredProducts = data;
      _isLoading = false;
      for (var p in data) {
        _selectedQuantities[p['product_id']] = 1;
      }
    });
  }

  void _filterProducts() {
    setState(() {
      _filteredProducts = _products
          .where((p) => p['name'].toString().toLowerCase().contains(_searchController.text.toLowerCase()))
          .toList();
    });
  }

  Future<void> _confirmSale(Map<String, dynamic> product) async {
    final productId = product['product_id'];
    final quantity = _selectedQuantities[productId] ?? 1;
    final stock = product['quantity'] as int;

    if (stock >= quantity) {
      final items = [
        {
          'product_id': productId,
          'quantity': quantity,
          'price': product['sale_price'],
        }
      ];

      final totalSaleAmount = (product['sale_price'] as num).toDouble() * quantity;

      await DatabaseHelper.instance.createSale(totalSaleAmount, items);
      
      await _loadProducts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('sale_successful'.tr()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('out_of_stock'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('sales'.tr()),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'search_product'.tr(),
                  leading: const Icon(Icons.search),
                  elevation: WidgetStateProperty.all(2),
                ),
              ),
              Expanded(
                child: _filteredProducts.isEmpty 
                  ? Center(child: Text('no_products_found'.tr()))
                  : ListView.builder(
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        final productId = product['product_id'];
                        final currentQty = _selectedQuantities[productId] ?? 1;

                        final saleCurrencyStr = product['sale_currency'] as String?;
                        final saleCurrency = saleCurrencyStr == 'usd' ? Currency.usd : Currency.syp;
                        final currencySymbol = currencyLabel(saleCurrency);
                        final price = (product['sale_price'] as num?)?.toDouble() ?? 0.0;

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        product['name'],
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${formatPrice(price)} $currencySymbol',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('${'stock'.tr()}: ${product['quantity']}'),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                          onPressed: () {
                                            if (currentQty > 1) {
                                              setState(() => _selectedQuantities[productId] = currentQty - 1);
                                            }
                                          },
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.grey),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '$currentQty',
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                          onPressed: () {
                                            if (currentQty < product['quantity']) {
                                              setState(() => _selectedQuantities[productId] = currentQty + 1);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: product['quantity'] > 0 ? () => _confirmSale(product) : null,
                                      icon: const Icon(Icons.check),
                                      label: Text('confirm_sale'.tr()),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ],
          ),
    );
  }
}
