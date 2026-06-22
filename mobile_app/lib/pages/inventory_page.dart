import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';
import 'add_product_page.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _matches(Map<String, dynamic> data, String docId) {
    if (_query.isEmpty) return true;
    final sku = (data['sku']?.toString() ?? docId).toLowerCase();
    final name = (data['name']?.toString() ?? '').toLowerCase();
    final secondName = (data['secondName']?.toString() ?? '').toLowerCase();
    final alternateSkus = (data['alternateSkus'] as List<dynamic>? ?? [])
        .map((item) => item.toString().toLowerCase())
        .join(' ');
    return sku.contains(_query) ||
        name.contains(_query) ||
        secondName.contains(_query) ||
        alternateSkus.contains(_query);
  }

  Color _stockColor(int stockQty) {
    if (stockQty <= 0) return const Color(0xFFFFE8E8);
    if (stockQty <= 5) return const Color(0xFFFFF3CD);
    return const Color(0xFFEAF7EA);
  }

  String _stockLabel(int stockQty) {
    if (stockQty <= 0) return 'Sin existencia';
    if (stockQty <= 5) return 'Bajo';
    return 'Disponible';
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Buscar por nombre o codigo',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firebaseService.watchProducts(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error cargando inventario: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final products =
                    snapshot.data!.docs
                        .where((doc) => _matches(doc.data(), doc.id))
                        .toList()
                      ..sort((a, b) {
                        final stockA = _toInt(a.data()['stockQty']);
                        final stockB = _toInt(b.data()['stockQty']);
                        final byStock = stockA.compareTo(stockB);
                        if (byStock != 0) return byStock;
                        final nameA = a.data()['name']?.toString() ?? '';
                        final nameB = b.data()['name']?.toString() ?? '';
                        return nameA.compareTo(nameB);
                      });

                if (products.isEmpty) {
                  return const Center(
                    child: Text('No se encontraron productos.'),
                  );
                }

                return ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = products[index];
                    final data = doc.data();
                    final sku = data['sku']?.toString() ?? doc.id;
                    final name = data['name']?.toString() ?? 'Producto';
                    final secondName = data['secondName']?.toString() ?? '';
                    final category = data['category']?.toString() ?? '';
                    final stockQty = _toInt(data['stockQty']);
                    final unitsPerCase = _toInt(data['unitsPerCase']);
                    final productStatus =
                        data['productStatus']?.toString() ?? 'activo';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _stockColor(stockQty),
                        foregroundColor: Colors.black,
                        child: Text(
                          stockQty.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text('$sku - $name'),
                      subtitle: Text(
                        [
                          if (secondName.isNotEmpty) secondName,
                          if (category.isNotEmpty) category,
                          '${unitsPerCase <= 0 ? 1 : unitsPerCase} unid/caja',
                          'Estado: $productStatus',
                        ].join(' | '),
                      ),
                      trailing: Chip(
                        label: Text(_stockLabel(stockQty)),
                        backgroundColor: _stockColor(stockQty),
                        side: const BorderSide(color: Colors.black12),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AddProductPage(initialProduct: data),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
