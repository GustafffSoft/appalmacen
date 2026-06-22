import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';

class SupplierPricesPage extends StatelessWidget {
  const SupplierPricesPage({super.key});

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Precios por Suplidor')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firebaseService.watchSupplierPrices(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error cargando precios: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay precios registrados. Agrega precios de suplidores para comparar compras.',
                ),
              ),
            );
          }

          final bestBySku =
              <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
          for (final doc in docs) {
            final data = doc.data();
            final sku = data['productSku']?.toString() ?? '';
            if (sku.isEmpty) continue;

            final currentBest = bestBySku[sku];
            if (currentBest == null) {
              bestBySku[sku] = doc;
              continue;
            }

            if (_toDouble(data['unitCost']) <
                _toDouble(currentBest.data()['unitCost'])) {
              bestBySku[sku] = doc;
            }
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final sku = data['productSku']?.toString() ?? '';
              final productName = data['productName']?.toString() ?? 'Producto';
              final supplierName =
                  data['supplierName']?.toString() ?? 'Suplidor';
              final caseCost = _toDouble(data['caseCost']);
              final shippingCost = _toDouble(data['shippingCost']);
              final totalCost = _toDouble(data['totalCost']);
              final unitCost = _toDouble(data['unitCost']);
              final unitsPerCase = data['unitsPerCase']?.toString() ?? '0';
              final minimumOrderQty =
                  data['minimumOrderQty']?.toString() ?? '0';
              final isBest = bestBySku[sku]?.id == doc.id;

              return ListTile(
                leading: Icon(
                  isBest
                      ? Icons.check_circle_outline
                      : Icons.price_check_outlined,
                  color: isBest ? Colors.green.shade700 : Colors.black87,
                ),
                title: Text('$sku - $productName'),
                subtitle: Text(
                  [
                    supplierName,
                    'Caja ${_money(caseCost)}',
                    'Shipping ${_money(shippingCost)}',
                    'Total ${_money(totalCost)}',
                    'Unidad ${_money(unitCost)}',
                    '$unitsPerCase unid/caja',
                    'Min $minimumOrderQty',
                  ].join(' | '),
                ),
                trailing: isBest
                    ? const Chip(
                        label: Text('Mejor'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Color(0xFFEAF7EA),
                        side: BorderSide(color: Colors.black12),
                      )
                    : const Icon(Icons.edit_outlined),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SupplierPriceFormPage(
                        supplierPriceId: doc.id,
                        initialData: data,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_card_outlined),
        label: const Text('Nuevo'),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SupplierPriceFormPage()),
          );
        },
      ),
    );
  }
}

class SupplierPriceFormPage extends StatefulWidget {
  const SupplierPriceFormPage({
    super.key,
    this.supplierPriceId,
    this.initialData,
  });

  final String? supplierPriceId;
  final Map<String, dynamic>? initialData;

  @override
  State<SupplierPriceFormPage> createState() => _SupplierPriceFormPageState();
}

class _SupplierPriceFormPageState extends State<SupplierPriceFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _caseCostController;
  late final TextEditingController _shippingCostController;
  late final TextEditingController _unitsPerCaseController;
  late final TextEditingController _minimumOrderQtyController;
  late final TextEditingController _sourceUrlController;
  late final TextEditingController _notesController;
  String? _productSku;
  String? _supplierId;
  bool _saving = false;

  bool get _isEditing => widget.supplierPriceId != null;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? <String, dynamic>{};
    _productSku = data['productSku']?.toString();
    _supplierId = data['supplierId']?.toString();
    _caseCostController = TextEditingController(
      text: data['caseCost']?.toString() ?? '0',
    );
    _shippingCostController = TextEditingController(
      text: data['shippingCost']?.toString() ?? '0',
    );
    _unitsPerCaseController = TextEditingController(
      text: data['unitsPerCase']?.toString() ?? '1',
    );
    _minimumOrderQtyController = TextEditingController(
      text: data['minimumOrderQty']?.toString() ?? '1',
    );
    _sourceUrlController = TextEditingController(
      text: data['sourceUrl']?.toString() ?? '',
    );
    _notesController = TextEditingController(
      text: data['notes']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _caseCostController.dispose();
    _shippingCostController.dispose();
    _unitsPerCaseController.dispose();
    _minimumOrderQtyController.dispose();
    _sourceUrlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _requiredMoney(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo requerido';
    }
    final number = double.tryParse(value.trim());
    if (number == null || number < 0) {
      return 'Ingresa un numero valido';
    }
    return null;
  }

  String? _requiredPositiveWholeNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo requerido';
    }
    final number = int.tryParse(value.trim());
    if (number == null || number <= 0) {
      return 'Ingresa un numero mayor que 0';
    }
    return null;
  }

  double _readDouble(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  int _readInt(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ?? 1;
  }

  Future<void> _save({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> suppliers,
  }) async {
    final firebaseService = context.read<FirebaseService>();
    if (!_formKey.currentState!.validate()) return;
    if (_productSku == null || _supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona producto y suplidor')),
      );
      return;
    }

    final productDoc = products.firstWhere(
      (doc) => (doc.data()['sku']?.toString() ?? doc.id) == _productSku,
    );
    final supplierDoc = suppliers.firstWhere((doc) => doc.id == _supplierId);
    final productData = productDoc.data();
    final supplierData = supplierDoc.data();

    setState(() => _saving = true);
    try {
      await firebaseService.saveSupplierPrice(
        supplierPriceId: widget.supplierPriceId,
        productSku: productData['sku']?.toString() ?? productDoc.id,
        productName: productData['name']?.toString() ?? 'Producto',
        supplierId: supplierDoc.id,
        supplierName: supplierData['name']?.toString() ?? 'Suplidor',
        caseCost: _readDouble(_caseCostController),
        shippingCost: _readDouble(_shippingCostController),
        unitsPerCase: _readInt(_unitsPerCaseController),
        minimumOrderQty: _readInt(_minimumOrderQtyController),
        sourceUrl: _sourceUrlController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Precio actualizado' : 'Precio guardado'),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error guardando precio: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Precio' : 'Nuevo Precio'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firebaseService.watchProducts(),
        builder: (context, productsSnapshot) {
          if (!productsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: firebaseService.watchSuppliers(),
            builder: (context, suppliersSnapshot) {
              if (!suppliersSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final products = productsSnapshot.data!.docs;
              final suppliers = suppliersSnapshot.data!.docs;
              if (products.isEmpty || suppliers.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Necesitas al menos un producto y un suplidor antes de registrar precios.',
                    ),
                  ),
                );
              }

              final productSkus = products
                  .map((doc) => doc.data()['sku']?.toString() ?? doc.id)
                  .toSet();
              if (_productSku == null || !productSkus.contains(_productSku)) {
                _productSku =
                    products.first.data()['sku']?.toString() ??
                    products.first.id;
              }
              final supplierIds = suppliers.map((doc) => doc.id).toSet();
              if (_supplierId == null || !supplierIds.contains(_supplierId)) {
                _supplierId = suppliers.first.id;
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _productSku,
                        decoration: const InputDecoration(
                          labelText: 'Producto',
                        ),
                        items: products
                            .map((doc) {
                              final data = doc.data();
                              final sku = data['sku']?.toString() ?? doc.id;
                              final name =
                                  data['name']?.toString() ?? 'Producto';
                              return DropdownMenuItem(
                                value: sku,
                                child: Text('$sku - $name'),
                              );
                            })
                            .toList(growable: false),
                        onChanged: (value) =>
                            setState(() => _productSku = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _supplierId,
                        decoration: const InputDecoration(
                          labelText: 'Suplidor',
                        ),
                        items: suppliers
                            .map((doc) {
                              final data = doc.data();
                              return DropdownMenuItem(
                                value: doc.id,
                                child: Text(
                                  data['name']?.toString() ?? 'Suplidor',
                                ),
                              );
                            })
                            .toList(growable: false),
                        onChanged: (value) =>
                            setState(() => _supplierId = value),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _caseCostController,
                              validator: _requiredMoney,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Costo caja',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _shippingCostController,
                              validator: _requiredMoney,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Shipping',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _unitsPerCaseController,
                              validator: _requiredPositiveWholeNumber,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Unid. caja',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _minimumOrderQtyController,
                              validator: _requiredPositiveWholeNumber,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Min compra',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _sourceUrlController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Link / fuente',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(labelText: 'Notas'),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _save(
                                  products: products,
                                  suppliers: suppliers,
                                ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving ? 'Guardando...' : 'Guardar Precio',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
