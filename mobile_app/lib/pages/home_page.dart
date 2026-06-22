import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import 'admin_users_page.dart';
import 'add_product_page.dart';
import 'create_order_page.dart';
import 'dashboard_page.dart';
import 'inventory_page.dart';
import 'margin_calculator_page.dart';
import 'order_detail_page.dart';
import 'pallets_page.dart';
import 'products_page.dart';
import 'prospects_page.dart';
import 'purchase_recommendations_page.dart';
import 'sales_agent_page.dart';
import 'sales_follow_up_page.dart';
import 'scan_invoice_page.dart';
import 'scan_products_page.dart';
import 'supplier_prices_page.dart';
import 'suppliers_page.dart';
import 'warehouse_rack_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.profile});

  final AppUserProfile profile;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _statusMessage;
  int _selectedTab = 0;

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
    final profile = widget.profile;
    final canWarehouse = profile.isAdmin || profile.isWarehouse;
    final canSales = profile.isAdmin || profile.isSales;

    return Scaffold(
      appBar: AppBar(
        title: const Text('appalmacen'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: context.read<AuthService>().signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Menu',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(profile.name.isEmpty ? profile.email : profile.name),
                    Text(
                      profile.role == 'admin'
                          ? 'Administrador'
                          : profile.role == 'warehouse'
                          ? 'Almacen'
                          : 'Ventas',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Ordenes'),
                subtitle: const Text('Ver ordenes creadas y procesar pallets'),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => _selectedTab = 1);
                },
              ),
              if (canWarehouse)
                ListTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: const Text('Escanear Invoice'),
                  subtitle: const Text(
                    'Registrar invoice y crear/actualizar orden',
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ScanInvoicePage(),
                      ),
                    );
                  },
                ),
              if (canWarehouse)
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Crear Orden Manual'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateOrderPage(),
                      ),
                    );
                  },
                ),
              if (canWarehouse)
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
              if (canWarehouse)
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner),
                  title: const Text('Escanear Productos'),
                  subtitle: const Text('Crear productos nuevos desde imagenes'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ScanProductsPage(),
                      ),
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
              if (canWarehouse)
                ListTile(
                  leading: const Icon(Icons.warehouse_outlined),
                  title: const Text('Inventario'),
                  subtitle: const Text('Buscar productos por existencia'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InventoryPage()),
                    );
                  },
                ),
              if (canWarehouse)
                ListTile(
                  leading: const Icon(Icons.view_module_outlined),
                  title: const Text('Mapa de Racks'),
                  subtitle: const Text('Arrastrar pallets a posiciones'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WarehouseRackPage(),
                      ),
                    );
                  },
                ),
              if (canWarehouse)
                ListTile(
                  leading: const Icon(Icons.view_in_ar_outlined),
                  title: const Text('Lista de Pallets'),
                  subtitle: const Text('Editar cantidades, nombres y fotos'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PalletsPage()),
                    );
                  },
                ),
              if (canSales) const Divider(height: 1),
              if (canSales)
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Clientes B2B'),
                  subtitle: const Text('Prospectos, negocios y seguimiento'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProspectsPage()),
                    );
                  },
                ),
              if (canSales)
                ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: const Text('Suplidores'),
                  subtitle: const Text('Mayoristas, contactos y notas'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SuppliersPage()),
                    );
                  },
                ),
              if (canSales)
                ListTile(
                  leading: const Icon(Icons.price_check_outlined),
                  title: const Text('Precios por Suplidor'),
                  subtitle: const Text('Comparar costo, shipping y unidad'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SupplierPricesPage(),
                      ),
                    );
                  },
                ),
              if (canSales)
                ListTile(
                  leading: const Icon(Icons.shopping_cart_checkout_outlined),
                  title: const Text('Recomendacion de Compra'),
                  subtitle: const Text(
                    'Mejor suplidor, margen y alerta de stock',
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PurchaseRecommendationsPage(),
                      ),
                    );
                  },
                ),
              if (canSales)
                ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('Agente Vendedor'),
                  subtitle: const Text('Mensajes para WhatsApp, SMS o llamada'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SalesAgentPage()),
                    );
                  },
                ),
              if (canSales)
                ListTile(
                  leading: const Icon(Icons.mark_chat_read_outlined),
                  title: const Text('Seguimiento'),
                  subtitle: const Text('Estados, notas y proximos contactos'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SalesFollowUpPage(),
                      ),
                    );
                  },
                ),
              if (canSales)
                ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: const Text('Calculadora de Margen'),
                  subtitle: const Text('Costo, shipping, venta y ganancia'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MarginCalculatorPage(),
                      ),
                    );
                  },
                ),
              if (profile.isAdmin) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Administracion'),
                  subtitle: const Text('Usuarios, roles y permisos'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdminUsersPage()),
                    );
                  },
                ),
              ],
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
          if (canWarehouse)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ScanInvoicePage(),
                              ),
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
                              MaterialPageRoute(
                                builder: (_) => const CreateOrderPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add_box_outlined),
                          label: const Text('Crear Orden'),
                        ),
                      ),
                    ],
                  ),
                  if (canSales) const SizedBox(height: 8),
                  if (canSales)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ProspectsPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.storefront_outlined),
                            label: const Text('Clientes'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SalesAgentPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat_outlined),
                            label: const Text('Vender'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.dashboard_outlined),
                  label: Text('Dashboard'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.receipt_long_outlined),
                  label: Text('Ordenes'),
                ),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (selection) {
                setState(() => _selectedTab = selection.first);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _selectedTab == 0
                ? const DashboardPage()
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: firebaseService.watchOrders(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error cargando ordenes: ${snapshot.error}',
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No hay ordenes todavia. Usa Escanear Invoice o crea una orden manual.',
                          ),
                        );
                      }

                      final grouped =
                          <
                            String,
                            List<QueryDocumentSnapshot<Map<String, dynamic>>>
                          >{};
                      for (final doc in docs) {
                        final key = _groupLabel(doc.data());
                        grouped.putIfAbsent(key, () => []).add(doc);
                      }

                      final groupKeys = grouped.keys.toList()
                        ..sort((a, b) => b.compareTo(a));

                      return ListView.builder(
                        itemCount: groupKeys.length,
                        itemBuilder: (context, groupIndex) {
                          final key = groupKeys[groupIndex];
                          final groupDocs = grouped[key]!;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  key,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              ...groupDocs.map((doc) {
                                final data = doc.data();
                                final status =
                                    data['status']?.toString() ?? 'unknown';
                                final items =
                                    (data['items'] as List<dynamic>? ?? [])
                                        .length;
                                final invoiceNumber = data['invoiceNumber']
                                    ?.toString();
                                final storeNumber = data['storeNumber']
                                    ?.toString();
                                final storeName = data['storeName']?.toString();
                                final address = data['address']?.toString();

                                final subtitleParts = <String>[
                                  'Estado: $status',
                                  'Items: $items',
                                  if (invoiceNumber != null &&
                                      invoiceNumber.isNotEmpty)
                                    'Invoice: $invoiceNumber',
                                  if (storeNumber != null &&
                                      storeNumber.isNotEmpty)
                                    'Tienda: #$storeNumber',
                                  if (storeName != null && storeName.isNotEmpty)
                                    storeName,
                                  if (address != null && address.isNotEmpty)
                                    address,
                                ];

                                return ListTile(
                                  title: Text('Orden ${doc.id}'),
                                  subtitle: Text(subtitleParts.join(' | ')),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            OrderDetailPage(orderId: doc.id),
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
