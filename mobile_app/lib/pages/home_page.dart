import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'admin_users_page.dart';
import 'add_product_page.dart';
import 'dashboard_page.dart';
import 'inventory_page.dart';
import 'pallets_page.dart';
import 'products_page.dart';
import 'purchase_recommendations_page.dart';
import 'scan_products_page.dart';
import 'warehouse_rack_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.profile});

  final AppUserProfile profile;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _statusMessage;
  bool _rackMoveMode = false;

  void _setRackMoveMode(bool active) {
    if (_rackMoveMode == active) return;
    debugPrint('[RackMove] Home fullScreen=$active');
    setState(() => _rackMoveMode = active);
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final canWarehouse = profile.isAdmin || profile.isWarehouse;
    final canSales = profile.isAdmin || profile.isSales;

    return Scaffold(
      appBar: _rackMoveMode
          ? null
          : AppBar(
              title: const Text('appalmacen'),
              actions: [
                IconButton(
                  tooltip: 'Cerrar sesion',
                  onPressed: context.read<AuthService>().signOut,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
      drawer: _rackMoveMode
          ? null
          : Drawer(
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
                          Text(
                            profile.name.isEmpty ? profile.email : profile.name,
                          ),
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
                    if (canWarehouse)
                      ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text('Nuevo Producto'),
                        subtitle: const Text('Agregar nombre, medidas y peso'),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AddProductPage(),
                            ),
                          );
                        },
                      ),
                    if (canWarehouse)
                      ListTile(
                        leading: const Icon(Icons.qr_code_scanner),
                        title: const Text('Escanear Productos'),
                        subtitle: const Text(
                          'Crear productos nuevos desde imagenes',
                        ),
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
                      subtitle: const Text(
                        'Editar nombre, segundo nombre y medidas',
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProductsPage(
                              canDeleteProducts: profile.isAdmin,
                            ),
                          ),
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
                            MaterialPageRoute(
                              builder: (_) => const InventoryPage(),
                            ),
                          );
                        },
                      ),
                    if (canWarehouse)
                      ListTile(
                        leading: const Icon(Icons.view_module_outlined),
                        title: const Text('Mapa de Racks'),
                        subtitle: const Text('Ubicar pallets en posiciones'),
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
                        subtitle: const Text(
                          'Editar cantidades, nombres y fotos',
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PalletsPage(),
                            ),
                          );
                        },
                      ),
                    if (canSales)
                      ListTile(
                        leading: const Icon(
                          Icons.shopping_cart_checkout_outlined,
                        ),
                        title: const Text('Recomendacion de Compra'),
                        subtitle: const Text(
                          'Mejor suplidor, margen y alerta de stock',
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const PurchaseRecommendationsPage(),
                            ),
                          );
                        },
                      ),
                    if (profile.isAdmin) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.admin_panel_settings_outlined,
                        ),
                        title: const Text('Administracion'),
                        subtitle: const Text('Usuarios, roles y permisos'),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminUsersPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
      body: SafeArea(
        top: canWarehouse && _rackMoveMode,
        bottom: canWarehouse && _rackMoveMode,
        child: Column(
          children: [
            if (!_rackMoveMode && _statusMessage != null)
              Container(
                width: double.infinity,
                color: Colors.black,
                padding: const EdgeInsets.all(12),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            Expanded(
              child: canWarehouse
                  ? WarehouseRackPage(
                      key: const ValueKey('home-warehouse-rack'),
                      embedded: true,
                      onMoveModeChanged: _setRackMoveMode,
                    )
                  : const DashboardPage(),
            ),
          ],
        ),
      ),
    );
  }
}
