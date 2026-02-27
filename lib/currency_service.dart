import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

enum Currency {
  syp,
  usd,
}

String formatPrice(double price) {
  return NumberFormat('#.##').format(price);
}

String currencyLabel(Currency c) {
  return c == Currency.syp ? 'ل.س' : '\$';
}

class PriceWithCurrency extends StatefulWidget {
  final String label;
  final Function(double amount, Currency currency) onChanged;
  final double initialAmount;
  final Currency initialCurrency;

  const PriceWithCurrency({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialAmount = 0.0,
    this.initialCurrency = Currency.syp,
  });

  @override
  State<PriceWithCurrency> createState() => _PriceWithCurrencyState();
}

class _PriceWithCurrencyState extends State<PriceWithCurrency> {
  // 1. Controller is no longer final.
  late TextEditingController controller;
  late Currency selectedCurrency;

  // 3. Simplified initState.
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: widget.initialAmount == 0 ? '' : formatPrice(widget.initialAmount),
    );
    selectedCurrency = widget.initialCurrency;
  }

  // 2. The definitive solution: didUpdateWidget.
  @override
  void didUpdateWidget(covariant PriceWithCurrency oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialAmount != widget.initialAmount) {
      final text = widget.initialAmount == 0
          ? ''
          : formatPrice(widget.initialAmount);

      // Prevents interrupting user input.
      if (controller.text != text) {
        controller.text = text;
      }
    }

    if (oldWidget.initialCurrency != widget.initialCurrency) {
      if (mounted) {
        setState(() {
            selectedCurrency = widget.initialCurrency;
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              widget.onChanged(
                double.tryParse(value) ?? 0.0,
                selectedCurrency,
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<Currency>(
            value: selectedCurrency,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: Currency.syp,
                child: Text('ليرة سوري'),
              ),
              DropdownMenuItem(
                value: Currency.usd,
                child: Text('دولار'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedCurrency = value;
                });
                widget.onChanged(
                  double.tryParse(controller.text) ?? 0,
                  selectedCurrency,
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
