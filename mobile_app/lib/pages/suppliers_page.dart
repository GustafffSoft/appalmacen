import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Suplidores')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firebaseService.watchSuppliers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error cargando suplidores: ${snapshot.error}'),
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
                  'No hay suplidores todavia. Agrega mayoristas, distribuidores o tiendas de compra.',
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final name = data['name']?.toString() ?? 'Suplidor';
              final contact = data['contact']?.toString() ?? '';
              final phone = data['phone']?.toString() ?? '';
              final productFocus = data['productFocus']?.toString() ?? '';

              return ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(name),
                subtitle: Text(
                  [
                    if (productFocus.isNotEmpty) productFocus,
                    if (contact.isNotEmpty) contact,
                    if (phone.isNotEmpty) phone,
                  ].join(' | '),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SupplierFormPage(
                        supplierId: doc.id,
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
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nuevo'),
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SupplierFormPage()));
        },
      ),
    );
  }
}

class SupplierFormPage extends StatefulWidget {
  const SupplierFormPage({super.key, this.supplierId, this.initialData});

  final String? supplierId;
  final Map<String, dynamic>? initialData;

  @override
  State<SupplierFormPage> createState() => _SupplierFormPageState();
}

class _SupplierFormPageState extends State<SupplierFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  late final TextEditingController _phoneController;
  late final TextEditingController _websiteController;
  late final TextEditingController _productFocusController;
  late final TextEditingController _paymentTermsController;
  late final TextEditingController _notesController;
  bool _saving = false;

  bool get _isEditing => widget.supplierId != null;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? <String, dynamic>{};
    _nameController = TextEditingController(
      text: data['name']?.toString() ?? '',
    );
    _contactController = TextEditingController(
      text: data['contact']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: data['phone']?.toString() ?? '',
    );
    _websiteController = TextEditingController(
      text: data['website']?.toString() ?? '',
    );
    _productFocusController = TextEditingController(
      text: data['productFocus']?.toString() ?? '',
    );
    _paymentTermsController = TextEditingController(
      text: data['paymentTerms']?.toString() ?? '',
    );
    _notesController = TextEditingController(
      text: data['notes']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _productFocusController.dispose();
    _paymentTermsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _requiredValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo requerido';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await context.read<FirebaseService>().saveSupplier(
        supplierId: widget.supplierId,
        name: _nameController.text.trim(),
        contact: _contactController.text.trim(),
        phone: _phoneController.text.trim(),
        website: _websiteController.text.trim(),
        productFocus: _productFocusController.text.trim(),
        paymentTerms: _paymentTermsController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Suplidor actualizado' : 'Suplidor guardado',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error guardando: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Suplidor' : 'Nuevo Suplidor'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                validator: _requiredValue,
                decoration: const InputDecoration(
                  labelText: 'Nombre del suplidor',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(labelText: 'Contacto'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefono'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _websiteController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Website'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _productFocusController,
                decoration: const InputDecoration(
                  labelText: 'Productos principales',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _paymentTermsController,
                decoration: const InputDecoration(
                  labelText: 'Terminos de pago',
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
                  onPressed: _saving ? null : _save,
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
                  label: Text(_saving ? 'Guardando...' : 'Guardar Suplidor'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
