import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:convert';

import '../config.dart';
import '../services/firebase_service.dart';
import 'add_product_page.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _researchingSku;

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

  bool _matches(Map<String, dynamic> data, String docId) {
    if (_query.isEmpty) return true;
    final values = [
      data['sku']?.toString() ?? docId,
      data['name'],
      data['secondName'],
      data['category'],
      ...(data['alternateSkus'] as List<dynamic>? ?? []),
    ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
    return values.contains(_query);
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  String _statusLabel(String status) {
    switch (status) {
      case 'bajo_stock':
        return 'Bajo stock';
      case 'lento':
        return 'Lento';
      case 'pausado':
        return 'Pausado';
      default:
        return 'Activo';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'bajo_stock':
        return const Color(0xFFFFF3CD);
      case 'lento':
        return const Color(0xFFE8F0FE);
      case 'pausado':
        return const Color(0xFFF1F1F1);
      default:
        return const Color(0xFFEAF7EA);
    }
  }

  Future<void> _researchProduct(Map<String, dynamic> data, String sku) async {
    setState(() => _researchingSku = sku);
    try {
      final uri = Uri.parse('$backendBaseUrl/api/v1/products/$sku/research');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sku': sku,
          'name': data['name']?.toString() ?? '',
          'secondName': data['secondName']?.toString(),
          'category': data['category']?.toString(),
          'alternateSkus': data['alternateSkus'] ?? [],
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Backend ${response.statusCode}: ${response.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Investigacion completada para $sku')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error investigando $sku: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _researchingSku = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Productos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Buscar producto por nombre o codigo',
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
                    child: Text('Error cargando productos: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs
                    .where((doc) => _matches(doc.data(), doc.id))
                    .toList();
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No hay productos registrados.'
                          : 'No se encontraron productos.',
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final sku = data['sku']?.toString() ?? docs[index].id;
                    final name = data['name']?.toString() ?? 'Producto';
                    final secondName = data['secondName']?.toString();
                    final l = data['lengthCm'];
                    final w = data['widthCm'];
                    final h = data['heightCm'];
                    final dims = [l, w, h].join('x');
                    final weight = data['weightKg'];
                    final category = data['category']?.toString() ?? '';
                    final cost = _toDouble(data['cost']);
                    final salePrice = _toDouble(data['salePrice']);
                    final stockQty = _toInt(data['stockQty']);
                    final unitsPerCase = _toInt(data['unitsPerCase']);
                    final productStatus =
                        data['productStatus']?.toString() ?? 'activo';
                    final confidence =
                        data['researchConfidence']?.toString() ??
                        'sin investigar';
                    final hasCaseDimensions =
                        data['researchHasCaseDimensions'] == true;
                    final hasCaseWeight = data['researchHasCaseWeight'] == true;
                    final productImageUrl =
                        data['productImageUrl']?.toString() ?? '';
                    final caseImageUrl = data['caseImageUrl']?.toString() ?? '';
                    final hasProductImage =
                        data['researchHasProductImage'] == true &&
                        productImageUrl.isNotEmpty;
                    final hasCaseImage =
                        data['researchHasCaseImage'] == true &&
                        caseImageUrl.isNotEmpty;
                    final useCase = data['useCase']?.toString() ?? '';
                    final sources =
                        (data['researchSources'] as List<dynamic>? ?? []);
                    final profit = salePrice - cost;
                    final marginPct = salePrice <= 0
                        ? 0
                        : (profit / salePrice) * 100;
                    final commercialLines = [
                      if (category.isNotEmpty) category,
                      'Costo ${_money(cost)}',
                      'Venta ${_money(salePrice)}',
                      'Margen ${marginPct.toStringAsFixed(1)}%',
                      'Stock $stockQty cajas',
                      if (unitsPerCase > 0) '$unitsPerCase unid/caja',
                      'Investigacion $confidence',
                      hasCaseDimensions
                          ? 'Medidas caja OK'
                          : 'Medidas caja pendiente',
                      hasCaseWeight ? 'Peso caja OK' : 'Peso caja pendiente',
                      hasProductImage
                          ? 'Imagen producto OK'
                          : 'Imagen producto pendiente',
                      hasCaseImage ? 'Imagen caja OK' : 'Imagen caja pendiente',
                    ];
                    final researchLine = [
                      if (useCase.isNotEmpty) useCase,
                      if (sources.isNotEmpty) '${sources.length} fuente(s)',
                    ].join(' | ');

                    return ListTile(
                      leading: hasProductImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                productImageUrl,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.inventory_2_outlined),
                              ),
                            )
                          : const Icon(Icons.inventory_2_outlined),
                      title: Text('$sku - $name'),
                      subtitle: Text(
                        secondName != null && secondName.isNotEmpty
                            ? '$secondName\n${commercialLines.join(' | ')}\n$dims in | $weight kg${researchLine.isEmpty ? '' : '\n$researchLine'}'
                            : '${commercialLines.join(' | ')}\n$dims in | $weight kg${researchLine.isEmpty ? '' : '\n$researchLine'}',
                      ),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Investigar medidas y peso',
                            onPressed: _researchingSku == null
                                ? () => _researchProduct(data, sku)
                                : null,
                            icon: _researchingSku == sku
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.travel_explore),
                          ),
                          Chip(
                            label: Text(_statusLabel(productStatus)),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: _statusColor(productStatus),
                            side: const BorderSide(color: Colors.black12),
                          ),
                        ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AddProductPage()));
        },
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
    );
  }
}
