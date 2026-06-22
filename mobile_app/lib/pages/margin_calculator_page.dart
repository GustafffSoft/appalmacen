import 'package:flutter/material.dart';

class MarginCalculatorPage extends StatefulWidget {
  const MarginCalculatorPage({super.key});

  @override
  State<MarginCalculatorPage> createState() => _MarginCalculatorPageState();
}

class _MarginCalculatorPageState extends State<MarginCalculatorPage> {
  final _costController = TextEditingController();
  final _shippingController = TextEditingController(text: '0');
  final _unitsController = TextEditingController(text: '1');
  final _salePriceController = TextEditingController();

  @override
  void dispose() {
    _costController.dispose();
    _shippingController.dispose();
    _unitsController.dispose();
    _salePriceController.dispose();
    super.dispose();
  }

  double _readNumber(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double get _totalCost =>
      _readNumber(_costController) + _readNumber(_shippingController);

  double get _unitCost {
    final units = _readNumber(_unitsController);
    if (units <= 0) return 0;
    return _totalCost / units;
  }

  double get _salePrice => _readNumber(_salePriceController);

  double get _profit => _salePrice - _totalCost;

  double get _marginPct {
    if (_salePrice <= 0) return 0;
    return (_profit / _salePrice) * 100;
  }

  double _suggestedPrice(double markupPct) {
    return _totalCost * (1 + markupPct / 100);
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calculadora de Margen')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _costController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Costo del producto o caja',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _shippingController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Shipping / delivery',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Unidades por caja'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _salePriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Precio de venta'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            _MetricTile(label: 'Costo total', value: _money(_totalCost)),
            _MetricTile(label: 'Costo por unidad', value: _money(_unitCost)),
            _MetricTile(label: 'Ganancia por caja', value: _money(_profit)),
            _MetricTile(
              label: 'Margen',
              value: '${_marginPct.toStringAsFixed(1)}%',
            ),
            const SizedBox(height: 18),
            const Text(
              'Precios sugeridos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _MetricTile(
              label: 'Markup 20%',
              value: _money(_suggestedPrice(20)),
            ),
            _MetricTile(
              label: 'Markup 30%',
              value: _money(_suggestedPrice(30)),
            ),
            _MetricTile(
              label: 'Markup 40%',
              value: _money(_suggestedPrice(40)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
