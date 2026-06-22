import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';
import 'purchase_recommendations_page.dart';
import 'sales_follow_up_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firebaseService.watchProducts(),
      builder: (context, productsSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firebaseService.watchSupplierPrices(),
          builder: (context, pricesSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firebaseService.watchSalesMessages(),
              builder: (context, messagesSnapshot) {
                if (!productsSnapshot.hasData ||
                    !pricesSnapshot.hasData ||
                    !messagesSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final products = productsSnapshot.data!.docs;
                final prices = pricesSnapshot.data!.docs;
                final messages = messagesSnapshot.data!.docs;

                final lowStock = products
                    .where((doc) {
                      final data = doc.data();
                      final stockQty = _toInt(data['stockQty']);
                      final status =
                          data['productStatus']?.toString() ?? 'activo';
                      return stockQty <= 2 || status == 'bajo_stock';
                    })
                    .take(5)
                    .toList();

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

                final bestBuys = bestPriceBySku.entries.take(5).toList();
                final followUps = messages
                    .where((doc) {
                      final status =
                          doc.data()['status']?.toString() ?? 'draft';
                      return status == 'follow_up' ||
                          status == 'replied' ||
                          status == 'interested';
                    })
                    .take(5)
                    .toList();
                final drafts = messages
                    .where((doc) {
                      final status =
                          doc.data()['status']?.toString() ?? 'draft';
                      return status == 'draft';
                    })
                    .take(5)
                    .toList();

                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  children: [
                    _MetricRow(
                      items: [
                        _MetricItem(
                          icon: Icons.inventory_2_outlined,
                          label: 'Bajo stock',
                          value: lowStock.length.toString(),
                        ),
                        _MetricItem(
                          icon: Icons.price_check_outlined,
                          label: 'Mejores compras',
                          value: bestBuys.length.toString(),
                        ),
                        _MetricItem(
                          icon: Icons.mark_chat_read_outlined,
                          label: 'Seguimientos',
                          value: followUps.length.toString(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DashboardSection(
                      title: 'Productos bajo stock',
                      actionLabel: 'Comprar',
                      onAction: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PurchaseRecommendationsPage(),
                          ),
                        );
                      },
                      emptyText: 'No hay productos marcados con bajo stock.',
                      children: lowStock.map((doc) {
                        final data = doc.data();
                        final sku = data['sku']?.toString() ?? doc.id;
                        final name = data['name']?.toString() ?? 'Producto';
                        final stockQty = _toInt(data['stockQty']);
                        return _CompactTile(
                          icon: Icons.warning_amber_outlined,
                          title: '$sku - $name',
                          subtitle: 'Stock $stockQty cajas',
                        );
                      }).toList(),
                    ),
                    _DashboardSection(
                      title: 'Mejores compras',
                      emptyText:
                          'Agrega precios por suplidor para ver oportunidades.',
                      children: bestBuys.map((entry) {
                        final data = entry.value;
                        final supplierName =
                            data['supplierName']?.toString() ?? 'Suplidor';
                        final productName =
                            data['productName']?.toString() ?? entry.key;
                        final unitCost = _toDouble(data['unitCost']);
                        final totalCost = _toDouble(data['totalCost']);
                        return _CompactTile(
                          icon: Icons.local_shipping_outlined,
                          title: '$productName - $supplierName',
                          subtitle:
                              'Caja ${_money(totalCost)} | Unidad ${_money(unitCost)}',
                        );
                      }).toList(),
                    ),
                    _DashboardSection(
                      title: 'Seguimientos pendientes',
                      actionLabel: 'Ver',
                      onAction: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SalesFollowUpPage(),
                          ),
                        );
                      },
                      emptyText: 'No hay seguimientos urgentes.',
                      children: followUps.map((doc) {
                        final data = doc.data();
                        final name =
                            data['prospectName']?.toString() ?? 'Cliente';
                        final status = data['status']?.toString() ?? '';
                        final date = data['followUpDate']?.toString() ?? '';
                        return _CompactTile(
                          icon: Icons.event_note_outlined,
                          title: name,
                          subtitle: [
                            if (status.isNotEmpty) status,
                            if (date.isNotEmpty) date,
                          ].join(' | '),
                        );
                      }).toList(),
                    ),
                    _DashboardSection(
                      title: 'Mensajes listos',
                      emptyText: 'No hay borradores de venta.',
                      children: drafts.map((doc) {
                        final data = doc.data();
                        final name =
                            data['prospectName']?.toString() ?? 'Cliente';
                        final channel = data['channel']?.toString() ?? '';
                        final products =
                            (data['productNames'] as List<dynamic>? ?? [])
                                .map((item) => item.toString())
                                .where((item) => item.isNotEmpty)
                                .take(2)
                                .join(', ');
                        return _CompactTile(
                          icon: Icons.chat_outlined,
                          title: name,
                          subtitle: [
                            if (channel.isNotEmpty) channel,
                            if (products.isNotEmpty) products,
                          ].join(' | '),
                        );
                      }).toList(),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MetricItem {
  const _MetricItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.items});

  final List<_MetricItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, size: 20),
                    const SizedBox(height: 8),
                    Text(
                      item.value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.emptyText,
    required this.children,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String emptyText;
  final List<Widget> children;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (actionLabel != null && onAction != null)
                  TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ),
          ),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  emptyText,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class _CompactTile extends StatelessWidget {
  const _CompactTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}
