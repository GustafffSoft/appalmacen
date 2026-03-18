import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';
import '../services/order_service.dart';
import 'order_detail_page.dart';

class CreateOrderPage extends StatefulWidget {
  const CreateOrderPage({super.key});

  @override
  State<CreateOrderPage> createState() => _CreateOrderPageState();
}

class _CreateOrderPageState extends State<CreateOrderPage> {
  final Map<String, int> _qtyBySku = {};
  final _invoiceNumberController = TextEditingController();
  final _storeNumberController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _invoiceDateController = TextEditingController();

  bool _creating = false;
  String? _message;

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _storeNumberController.dispose();
    _storeNameController.dispose();
    _addressController.dispose();
    _invoiceDateController.dispose();
    super.dispose();
  }

  void _changeQty(String sku, int delta) {
    final current = _qtyBySku[sku] ?? 0;
    final next = (current + delta).clamp(0, 999);
    setState(() {
      if (next == 0) {
        _qtyBySku.remove(sku);
      } else {
        _qtyBySku[sku] = next;
      }
    });
  }

  Future<void> _pickInvoiceDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_invoiceDateController.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      _invoiceDateController.text = picked.toIso8601String().split('T').first;
    });
  }

  Future<void> _createOrder() async {
    if (_qtyBySku.isEmpty) {
      setState(() => _message = 'Selecciona al menos un producto con cantidad.');
      return;
    }

    setState(() {
      _creating = true;
      _message = 'Creando orden con los productos seleccionados...';
    });

    final items = _qtyBySku.entries
        .map((entry) => {'sku': entry.key, 'qty': entry.value})
        .toList(growable: false);

    final invoiceData = <String, dynamic>{
      'invoiceNumber': _invoiceNumberController.text.trim(),
      'storeNumber': _storeNumberController.text.trim(),
      'storeName': _storeNameController.text.trim(),
      'address': _addressController.text.trim(),
      'invoiceDate': _invoiceDateController.text.trim().isEmpty
          ? DateTime.now().toIso8601String().split('T').first
          : _invoiceDateController.text.trim(),
    };

    try {
      final orderId = await context.read<OrderService>().createOrder(
            items: items,
            invoiceData: invoiceData,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OrderDetailPage(orderId: orderId)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'No se pudo crear la orden: $error');
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Crear Orden')),
      body: Column(
        children: [
          if (_message != null)
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.all(12),
              child: Text(_message!, style: const TextStyle(color: Colors.white)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _invoiceNumberController,
                  decoration: const InputDecoration(labelText: 'Numero de invoice'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _storeNumberController,
                        decoration: const InputDecoration(labelText: 'Numero de tienda'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _storeNameController,
                        decoration: const InputDecoration(labelText: 'Nombre de tienda'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Direccion'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _invoiceDateController,
                  readOnly: true,
                  onTap: _pickInvoiceDate,
                  decoration: const InputDecoration(
                    labelText: 'Fecha de invoice',
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firebaseService.watchProducts(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error cargando productos: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No hay productos. Usa el menu lateral para agregar productos.'),
                  );
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final sku = data['sku']?.toString() ?? docs[index].id;
                    final name = data['name']?.toString() ?? 'Producto';
                    final secondName = data['secondName']?.toString();
                    final weight = data['weightKg'];
                    final l = data['lengthCm'];
                    final w = data['widthCm'];
                    final h = data['heightCm'];
                    final qty = _qtyBySku[sku] ?? 0;

                    return ListTile(
                      title: Text('$sku - $name'),
                      subtitle: Text(
                        secondName != null && secondName.isNotEmpty
                            ? '$secondName\nCaja aprox: ${l}x${w}x${h} in | ${weight} kg'
                            : 'Caja aprox: ${l}x${w}x${h} in | ${weight} kg',
                      ),
                      isThreeLine: secondName != null && secondName.isNotEmpty,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _changeQty(sku, -1),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '$qty',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _changeQty(sku, 1),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _creating ? null : _createOrder,
                icon: _creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(_creating ? 'Creando orden...' : 'Crear Orden con Productos'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
