import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key, this.initialProduct});

  final Map<String, dynamic>? initialProduct;

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _skuController;
  late final TextEditingController _nameController;
  late final TextEditingController _secondNameController;
  late final TextEditingController _lengthController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;

  bool _saving = false;
  String? _message;

  bool get _isEditing => widget.initialProduct != null;

  @override
  void initState() {
    super.initState();
    final product = widget.initialProduct ?? <String, dynamic>{};
    _skuController = TextEditingController(text: product['sku']?.toString() ?? '');
    _nameController = TextEditingController(text: product['name']?.toString() ?? '');
    _secondNameController = TextEditingController(text: product['secondName']?.toString() ?? '');
    _lengthController = TextEditingController(text: product['lengthCm']?.toString() ?? '');
    _widthController = TextEditingController(text: product['widthCm']?.toString() ?? '');
    _heightController = TextEditingController(text: product['heightCm']?.toString() ?? '');
    _weightController = TextEditingController(text: product['weightKg']?.toString() ?? '');
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _secondNameController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _message = _isEditing
          ? 'Actualizando producto en Firestore...'
          : 'Guardando producto en Firestore...';
    });

    try {
      final sku = _buildSku(
        rawSku: _skuController.text,
        name: _nameController.text,
      );

      if (_isEditing) {
        await context.read<FirebaseService>().updateProduct(
              sku: sku,
              name: _nameController.text.trim(),
              secondName: _secondNameController.text.trim().isEmpty
                  ? null
                  : _secondNameController.text.trim(),
              lengthIn: double.parse(_lengthController.text.trim()),
              widthIn: double.parse(_widthController.text.trim()),
              heightIn: double.parse(_heightController.text.trim()),
              weightKg: double.parse(_weightController.text.trim()),
            );
      } else {
        await context.read<FirebaseService>().createProduct(
              sku: sku,
              name: _nameController.text.trim(),
              secondName: _secondNameController.text.trim().isEmpty
                  ? null
                  : _secondNameController.text.trim(),
              lengthIn: double.parse(_lengthController.text.trim()),
              widthIn: double.parse(_widthController.text.trim()),
              heightIn: double.parse(_heightController.text.trim()),
              weightKg: double.parse(_weightController.text.trim()),
            );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditing ? 'Producto actualizado' : 'Producto guardado con SKU $sku')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Error guardando producto: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _buildSku({required String rawSku, required String name}) {
    final cleanedSku = rawSku.trim().toUpperCase();
    if (cleanedSku.isNotEmpty) {
      return cleanedSku.replaceAll(RegExp(r'[^A-Z0-9-]'), '-');
    }

    final base = name.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '-');
    final compact = base.replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return 'MAN-${compact.isEmpty ? 'PRODUCT' : compact}';
  }

  String? _requiredValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo requerido';
    }
    return null;
  }

  String? _requiredNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo requerido';
    }
    final number = double.tryParse(value.trim());
    if (number == null || number <= 0) {
      return 'Ingresa un numero mayor que 0';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar Producto' : 'Nuevo Producto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_message != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                color: Colors.black,
                child: Text(
                  _message!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _skuController,
                    readOnly: _isEditing,
                    decoration: InputDecoration(
                      labelText: 'SKU ${_isEditing ? '(bloqueado)' : '(opcional)'}',
                      hintText: _isEditing
                          ? 'El SKU no se cambia en edicion'
                          : 'Si lo dejas vacio se genera automaticamente',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    validator: _requiredValue,
                    decoration: const InputDecoration(labelText: 'Nombre del producto'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _secondNameController,
                    decoration: const InputDecoration(labelText: 'Segundo nombre (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lengthController,
                    validator: _requiredNumber,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Largo (in)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _widthController,
                    validator: _requiredNumber,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ancho (in)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _heightController,
                    validator: _requiredNumber,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Alto (in)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _weightController,
                    validator: _requiredNumber,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Peso (kg)'),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveProduct,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving
                          ? (_isEditing ? 'Actualizando producto...' : 'Guardando producto...')
                          : (_isEditing ? 'Actualizar Producto' : 'Guardar Producto')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
