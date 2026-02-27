import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pharmacy/currency_service.dart';
import 'datdbase.dart';

class AddProductScreen extends StatefulWidget {
  final Map<String, dynamic>? product;

  const AddProductScreen({super.key, this.product});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _quantityController = TextEditingController();
  final _expiryDateController = TextEditingController();
  String _selectedCategory = 'Medicines';
  File? _image;

  double salePrice = 0;
  Currency saleCurrency = Currency.syp;

  double purchasePrice = 0;
  Currency purchaseCurrency = Currency.syp;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _nameController.text = widget.product!['name'];
      _barcodeController.text = widget.product!['barcode'] ?? '';
      salePrice = (widget.product!['sale_price'] as num?)?.toDouble() ?? 0.0;
      saleCurrency = Currency.values.firstWhere((e) => e.name == widget.product!['sale_currency'], orElse: () => Currency.syp);
      purchasePrice = (widget.product!['purchase_price'] as num?)?.toDouble() ?? 0.0;
      purchaseCurrency = Currency.values.firstWhere((e) => e.name == widget.product!['purchase_currency'], orElse: () => Currency.syp);
      _quantityController.text = widget.product!['quantity'].toString();
      _expiryDateController.text = widget.product!['expiry_date'] ?? '';
      _selectedCategory = widget.product!['category'];
      if (widget.product!['image'] != null) {
        _image = File(widget.product!['image']);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _quantityController.dispose();
    _expiryDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (picked != null) {
      setState(() {
        _expiryDateController.text =
            DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _pickImage() async {
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('please_fill_required_fields'.tr())),
      );
      return;
    }

    try {
      final productData = {
        'name': _nameController.text,
        'category': _selectedCategory,
        'barcode': _barcodeController.text,
        'purchase_price': purchasePrice,
        'purchase_currency': purchaseCurrency.name,
        'sale_price': salePrice,
        'sale_currency': saleCurrency.name,
        'quantity': int.tryParse(_quantityController.text) ?? 0,
        'expiry_date': _expiryDateController.text,
        'image': _image?.path,
        'created_at': DateTime.now().toIso8601String(),
      };

      if (widget.product == null) {
        await DatabaseHelper.instance.addProduct(productData);

        await addMedicine(
          name: _nameController.text.trim(),
          saleprice: salePrice.toString(),
          quantity: _quantityController.text.trim(),
          expiryDate: _expiryDateController.text.trim(),
          barcode: _barcodeController.text.trim(),
          currency: saleCurrency.name.toUpperCase(),
          category: _selectedCategory,
          purchasePrice: purchasePrice.toString(),
          purchaseCurrency: purchaseCurrency.name.toUpperCase(),
        );

      } else {
        productData['product_id'] = widget.product!['product_id'];
        await DatabaseHelper.instance.updateProduct(productData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('product_saved_successfully'.tr())),
        );
        Navigator.pop(context, true);
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${'error_saving_product'.tr()}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'add_product'.tr() : 'edit_product'.tr()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTextField(_nameController, 'name'.tr(), validator: (v) => v!.isEmpty ? 'field_required'.tr() : null),
              const SizedBox(height: 16),
              _buildCategorySelector(),
              const SizedBox(height: 16),
              _buildTextField(_barcodeController, 'barcode'.tr()),
              const SizedBox(height: 16),
              PriceWithCurrency(
                label: 'purchase_price'.tr(),
                initialAmount: purchasePrice,
                initialCurrency: purchaseCurrency,
                onChanged: (amount, currency) {
                  purchasePrice = amount;
                  purchaseCurrency = currency;
                },
              ),
              const SizedBox(height: 16),
              PriceWithCurrency(
                label: 'sale_price'.tr(),
                initialAmount: salePrice,
                initialCurrency: saleCurrency,
                onChanged: (amount, currency) {
                  salePrice = amount;
                  saleCurrency = currency;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(_quantityController, 'quantity'.tr(), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? 'field_required'.tr() : null),
              const SizedBox(height: 16),
              _buildDateField(context),
              const SizedBox(height: 16),
              _buildImagePicker(),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: Text(widget.product == null ? 'add_product'.tr() : 'edit_product'.tr()),
                onPressed: _saveProduct,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DropdownButtonFormField<String> _buildCategorySelector() {
    return DropdownButtonFormField(
      value: _selectedCategory,
      decoration: InputDecoration(labelText: 'category'.tr(), border: const OutlineInputBorder()),
      items: ['Medicines', 'Prescriptions', 'Supplies', 'Accessories'].map((String category) {
        return DropdownMenuItem(value: category, child: Text(category.toLowerCase().tr()));
      }).toList(),
      onChanged: (newValue) => setState(() => _selectedCategory = newValue!),
    );
  }

  TextFormField _buildTextField(TextEditingController controller, String label, {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  TextFormField _buildDateField(BuildContext context) {
    return TextFormField(
      controller: _expiryDateController,
      decoration: InputDecoration(
        labelText: 'expiry_date'.tr(),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(icon: const Icon(Icons.calendar_today), onPressed: () => _selectDate(context)),
      ),
      readOnly: true,
    );
  }

  Widget _buildImagePicker() {
    return Column(
      children: [
        _image == null ? const Text('No image selected.').tr() : Image.file(_image!, height: 150),
        TextButton.icon(
          icon: const Icon(Icons.image),
          label: Text('select_image'.tr()),
          onPressed: _pickImage,
        ),
      ],
    );
  }
}
