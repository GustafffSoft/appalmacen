import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';
import 'add_product_page.dart';
import 'create_order_page.dart';
import 'order_detail_page.dart';
import 'products_page.dart';
import 'scan_invoice_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _statusMessage;

  String _groupLabel(Map<String, dynamic> data) {
    final invoiceDate = data['invoiceDate']?.toString();
    if (invoiceDate != null && invoiceDate.isNotEmpty) {
      return invoiceDate;
    }
    return 'Sin fecha';
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('appalmacen')),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Menu',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Escanear Invoice'),
                subtitle: const Text('Registrar invoice y crear/actualizar orden'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ScanInvoicePage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Crear Orden Manual'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreateOrderPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Nuevo Producto'),
                subtitle: const Text('Agregar nombre, medidas y peso'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddProductPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('Productos'),
                subtitle: const Text('Editar nombre, segundo nombre y medidas'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProductsPage()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.all(12),
              child: Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ScanInvoicePage()),
                      );
                    },
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Escanear Invoice'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CreateOrderPage()),
                      );
                    },
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Crear Orden'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firebaseService.watchOrders(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error cargando ordenes: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No hay ordenes todavia. Usa Escanear Invoice o crea una orden manual.'),
                  );
                }

                final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
                for (final doc in docs) {
                  final key = _groupLabel(doc.data());
                  grouped.putIfAbsent(key, () => []).add(doc);
                }

                final groupKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

                return ListView.builder(
                  itemCount: groupKeys.length,
                  itemBuilder: (context, groupIndex) {
                    final key = groupKeys[groupIndex];
                    final groupDocs = grouped[key]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            key,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        ...groupDocs.map((doc) {
                          final data = doc.data();
                          final status = data['status']?.toString() ?? 'unknown';
                          final items = (data['items'] as List<dynamic>? ?? []).length;
                          final invoiceNumber = data['invoiceNumber']?.toString();
                          final storeNumber = data['storeNumber']?.toString();
                          final storeName = data['storeName']?.toString();
                          final address = data['address']?.toString();

                          final subtitleParts = <String>[
                            'Estado: $status',
                            'Items: $items',
                            if (invoiceNumber != null && invoiceNumber.isNotEmpty) 'Invoice: $invoiceNumber',
                            if (storeNumber != null && storeNumber.isNotEmpty) 'Tienda: #$storeNumber',
                            if (storeName != null && storeName.isNotEmpty) storeName,
                            if (address != null && address.isNotEmpty) address,
                          ];

                          return ListTile(
                            title: Text('Orden ${doc.id}'),
                            subtitle: Text(subtitleParts.join(' | ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OrderDetailPage(orderId: doc.id),
                                ),
                              );
                            },
                          );
                        }),
                        const Divider(height: 1),
                      ],
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
