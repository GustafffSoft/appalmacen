import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';

class PurchaseRecommendationsPage extends StatelessWidget {
  const PurchaseRecommendationsPage({super.key});

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  String _decision({
    required int stockQty,
    required double currentMargin,
    required bool hasSupplierPrice,
  }) {
    if (!hasSupplierPrice) return 'Falta precio';
    if (stockQty <= 2) return 'Comprar pronto';
    if (currentMargin < 20) return 'Revisar precio venta';
    return 'OK';
  }

  Color _decisionColor(String decision) {
    switch (decision) {
      case 'Comprar pronto':
        return const Color(0xFFFFF3CD);
      case 'Revisar precio venta':
        return const Color(0xFFFCE8E6);
      case 'Falta precio':
        return const Color(0xFFF1F1F1);
      default:
        return const Color(0xFFEAF7EA);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Recomendacion de Compra')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firebaseService.watchProducts(),
        builder: (context, productsSnapshot) {
          if (!productsSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: firebaseService.watchSupplierPrices(),
            builder: (context, pricesSnapshot) {
              if (!pricesSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final products = productsSnapshot.data!.docs;
              final prices = pricesSnapshot.data!.docs;
              if (products.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Agrega productos para ver recomendaciones de compra.',
                    ),
                  ),
                );
              }

              final bestPriceBySku = <String, Map<String, dynamic>>{};
              for (final priceDoc in prices) {
                final data = priceDoc.data();
                final sku = data['productSku']?.toString() ?? '';
                if (sku.isEmpty) continue;

                final current = bestPriceBySku[sku];
                if (current == null ||
                    _toDouble(data['unitCost']) <
                        _toDouble(current['unitCost'])) {
                  bestPriceBySku[sku] = data;
                }
              }

              return ListView.separated(
                itemCount: products.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = products[index].data();
                  final sku = product['sku']?.toString() ?? products[index].id;
                  final name = product['name']?.toString() ?? 'Producto';
                  final category = product['category']?.toString() ?? '';
                  final salePrice = _toDouble(product['salePrice']);
                  final productCost = _toDouble(product['cost']);
                  final stockQty = _toInt(product['stockQty']);
                  final bestPrice = bestPriceBySku[sku];
                  final bestCaseCost = _toDouble(bestPrice?['totalCost']);
                  final bestUnitCost = _toDouble(bestPrice?['unitCost']);
                  final supplierName =
                      bestPrice?['supplierName']?.toString() ?? '';
                  final effectiveCost = bestCaseCost > 0
                      ? bestCaseCost
                      : productCost;
                  final profit = salePrice - effectiveCost;
                  final marginPct = salePrice <= 0
                      ? 0.0
                      : (profit / salePrice) * 100;
                  final suggested30 = effectiveCost <= 0
                      ? 0.0
                      : effectiveCost * 1.30;
                  final decision = _decision(
                    stockQty: stockQty,
                    currentMargin: marginPct.toDouble(),
                    hasSupplierPrice: bestPrice != null,
                  );

                  return ListTile(
                    leading: const Icon(Icons.shopping_cart_checkout_outlined),
                    title: Text('$sku - $name'),
                    subtitle: Text(
                      [
                        if (category.isNotEmpty) category,
                        'Stock $stockQty cajas',
                        if (supplierName.isNotEmpty) 'Mejor: $supplierName',
                        if (bestCaseCost > 0)
                          'Costo caja ${_money(bestCaseCost)}',
                        if (bestUnitCost > 0) 'Unidad ${_money(bestUnitCost)}',
                        if (salePrice > 0) 'Venta ${_money(salePrice)}',
                        if (marginPct != 0)
                          'Margen ${marginPct.toStringAsFixed(1)}%',
                        if (suggested30 > 0) 'Venta 30% ${_money(suggested30)}',
                      ].join(' | '),
                    ),
                    isThreeLine: true,
                    trailing: Chip(
                      label: Text(decision),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: _decisionColor(decision),
                      side: const BorderSide(color: Colors.black12),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
