import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';
import 'add_product_page.dart';

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Productos')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
            return const Center(child: Text('No hay productos registrados.'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final sku = data['sku']?.toString() ?? docs[index].id;
              final name = data['name']?.toString() ?? 'Producto';
              final secondName = data['secondName']?.toString();
              final l = data['lengthCm'];
              final w = data['widthCm'];
              final h = data['heightCm'];
              final weight = data['weightKg'];

              return ListTile(
                title: Text('$sku - $name'),
                subtitle: Text(
                  secondName != null && secondName.isNotEmpty
                      ? '$secondName\n${l}x${w}x${h} in | ${weight} kg'
                      : '${l}x${w}x${h} in | ${weight} kg',
                ),
                isThreeLine: secondName != null && secondName.isNotEmpty,
                trailing: const Icon(Icons.edit_outlined),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddProductPage(initialProduct: data),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddProductPage()),
          );
        },
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
    );
  }
}
