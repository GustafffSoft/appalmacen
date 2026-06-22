import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';

class ProspectsPage extends StatelessWidget {
  const ProspectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes B2B')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firebaseService.watchProspects(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error cargando clientes: ${snapshot.error}'),
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
                  'No hay prospectos todavia. Agrega restaurantes, cafeterias o delis para venderles.',
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
              final name = data['businessName']?.toString() ?? 'Negocio';
              final type = data['businessType']?.toString() ?? 'Sin tipo';
              final phone = data['phone']?.toString() ?? '';
              final area = data['area']?.toString() ?? '';
              final status = data['status']?.toString() ?? 'nuevo';
              final products = (data['likelyProducts'] as List<dynamic>? ?? [])
                  .map((item) => item.toString())
                  .where((item) => item.isNotEmpty)
                  .join(', ');

              return ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(name),
                subtitle: Text(
                  [
                    type,
                    if (area.isNotEmpty) area,
                    if (phone.isNotEmpty) phone,
                    if (products.isNotEmpty) products,
                  ].join(' | '),
                ),
                trailing: _StatusChip(label: status),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProspectFormPage(
                        prospectId: doc.id,
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
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Nuevo'),
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ProspectFormPage()));
        },
      ),
    );
  }
}

class ProspectFormPage extends StatefulWidget {
  const ProspectFormPage({super.key, this.prospectId, this.initialData});

  final String? prospectId;
  final Map<String, dynamic>? initialData;

  @override
  State<ProspectFormPage> createState() => _ProspectFormPageState();
}

class _ProspectFormPageState extends State<ProspectFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _businessNameController;
  late final TextEditingController _businessTypeController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _areaController;
  late final TextEditingController _likelyProductsController;
  late final TextEditingController _notesController;
  String _status = 'nuevo';
  bool _saving = false;

  bool get _isEditing => widget.prospectId != null;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? <String, dynamic>{};
    _businessNameController = TextEditingController(
      text: data['businessName']?.toString() ?? '',
    );
    _businessTypeController = TextEditingController(
      text: data['businessType']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: data['phone']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: data['email']?.toString() ?? '',
    );
    _addressController = TextEditingController(
      text: data['address']?.toString() ?? '',
    );
    _areaController = TextEditingController(
      text: data['area']?.toString() ?? '',
    );
    _likelyProductsController = TextEditingController(
      text: (data['likelyProducts'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .join(', '),
    );
    _notesController = TextEditingController(
      text: data['notes']?.toString() ?? '',
    );
    _status = data['status']?.toString() ?? 'nuevo';
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessTypeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _areaController.dispose();
    _likelyProductsController.dispose();
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
      final products = _likelyProductsController.text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();

      await context.read<FirebaseService>().saveProspect(
        prospectId: widget.prospectId,
        businessName: _businessNameController.text.trim(),
        businessType: _businessTypeController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        area: _areaController.text.trim(),
        likelyProducts: products,
        status: _status,
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Cliente actualizado' : 'Cliente guardado',
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
        title: Text(_isEditing ? 'Editar Cliente' : 'Nuevo Cliente'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _businessNameController,
                validator: _requiredValue,
                decoration: const InputDecoration(
                  labelText: 'Nombre del negocio',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _businessTypeController,
                validator: _requiredValue,
                decoration: const InputDecoration(labelText: 'Tipo de negocio'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefono'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Direccion'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _areaController,
                decoration: const InputDecoration(labelText: 'Zona'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _likelyProductsController,
                decoration: const InputDecoration(
                  labelText: 'Productos probables',
                  hintText: 'vasos, plates, trash bags',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: const [
                  DropdownMenuItem(value: 'nuevo', child: Text('Nuevo')),
                  DropdownMenuItem(
                    value: 'contactado',
                    child: Text('Contactado'),
                  ),
                  DropdownMenuItem(
                    value: 'interesado',
                    child: Text('Interesado'),
                  ),
                  DropdownMenuItem(value: 'cliente', child: Text('Cliente')),
                  DropdownMenuItem(value: 'pausado', child: Text('Pausado')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _status = value);
                  }
                },
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
                  label: Text(_saving ? 'Guardando...' : 'Guardar Cliente'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.white,
      side: const BorderSide(color: Colors.black26),
    );
  }
}
