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
  late final TextEditingController _categoryController;
  late final TextEditingController _costController;
  late final TextEditingController _salePriceController;
  late final TextEditingController _unitsPerCaseController;
  late final TextEditingController _lengthController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  String _productStatus = 'activo';

  bool _saving = false;
  String? _message;

  bool get _isEditing => widget.initialProduct != null;

  @override
  void initState() {
    super.initState();
    final product = widget.initialProduct ?? <String, dynamic>{};
    _skuController = TextEditingController(
      text: product['sku']?.toString() ?? '',
    );
    _nameController = TextEditingController(
      text: product['name']?.toString() ?? '',
    );
    _secondNameController = TextEditingController(
      text: product['secondName']?.toString() ?? '',
    );
    _categoryController = TextEditingController(
      text: product['category']?.toString() ?? '',
    );
    _costController = TextEditingController(
      text: product['cost']?.toString() ?? '0',
    );
    _salePriceController = TextEditingController(
      text: product['salePrice']?.toString() ?? '0',
    );
    _unitsPerCaseController = TextEditingController(
      text: product['unitsPerCase']?.toString() ?? '1',
    );
    _lengthController = TextEditingController(
      text: product['lengthCm']?.toString() ?? '',
    );
    _widthController = TextEditingController(
      text: product['widthCm']?.toString() ?? '',
    );
    _heightController = TextEditingController(
      text: product['heightCm']?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: product['weightKg']?.toString() ?? '',
    );
    _productStatus = product['productStatus']?.toString() ?? 'activo';
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _secondNameController.dispose();
    _categoryController.dispose();
    _costController.dispose();
    _salePriceController.dispose();
    _unitsPerCaseController.dispose();
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
      final cost = double.tryParse(_costController.text.trim()) ?? 0;
      final salePrice = double.tryParse(_salePriceController.text.trim()) ?? 0;
      final unitsPerCase = int.parse(_unitsPerCaseController.text.trim());

      if (_isEditing) {
        await context.read<FirebaseService>().updateProduct(
          sku: sku,
          name: _nameController.text.trim(),
          secondName: _secondNameController.text.trim().isEmpty
              ? null
              : _secondNameController.text.trim(),
          category: _categoryController.text.trim(),
          cost: cost,
          salePrice: salePrice,
          unitsPerCase: unitsPerCase,
          productStatus: _productStatus,
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
          category: _categoryController.text.trim(),
          cost: cost,
          salePrice: salePrice,
          unitsPerCase: unitsPerCase,
          productStatus: _productStatus,
          lengthIn: double.parse(_lengthController.text.trim()),
          widthIn: double.parse(_widthController.text.trim()),
          heightIn: double.parse(_heightController.text.trim()),
          weightKg: double.parse(_weightController.text.trim()),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Producto actualizado'
                : 'Producto guardado con SKU $sku',
          ),
        ),
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

    final base = name.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]+'),
      '-',
    );
    final compact = base
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
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

  String? _optionalMoney(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final number = double.tryParse(raw);
    if (number == null || number < 0) {
      return 'Ingresa un numero valido';
    }
    return null;
  }

  String? _requiredPositiveWholeNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo requerido';
    }
    final number = int.tryParse(value.trim());
    if (number == null || number <= 0) {
      return 'Ingresa un numero mayor que 0';
    }
    return null;
  }

  Widget _imagePanel({
    required String title,
    required String imageUrl,
    required bool confirmed,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1.4,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFFF7F7F7),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl.isEmpty
                  ? Center(
                      child: Text(
                        confirmed ? 'Sin imagen' : 'Pendiente',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text('No se pudo cargar la imagen'),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(confirmed ? 'Confirmada' : 'No confirmada'),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('$label: $value'),
    );
  }

  Widget _imageGallery(String title, List<String> urls) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final url = urls[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 110,
                  height: 92,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 110,
                    height: 92,
                    color: const Color(0xFFF1F1F1),
                    alignment: Alignment.center,
                    child: const Text('Error'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _researchDetails() {
    final product = widget.initialProduct;
    if (product == null) return const SizedBox.shrink();

    final productImageUrl = product['productImageUrl']?.toString() ?? '';
    final caseImageUrl = product['caseImageUrl']?.toString() ?? '';
    final productImageUrls =
        (product['productImageUrls'] as List<dynamic>? ?? [])
            .map((url) => url.toString())
            .where((url) => url.isNotEmpty)
            .toList();
    final caseImageUrls = (product['caseImageUrls'] as List<dynamic>? ?? [])
        .map((url) => url.toString())
        .where((url) => url.isNotEmpty)
        .toList();
    final hasProductImage = product['researchHasProductImage'] == true;
    final hasCaseImage = product['researchHasCaseImage'] == true;
    final confidence = product['researchConfidence']?.toString() ?? '';
    final hasCaseDimensions = product['researchHasCaseDimensions'] == true;
    final hasCaseWeight = product['researchHasCaseWeight'] == true;
    final needsReview = product['researchNeedsManualReview'] == true;
    final useCase = product['useCase']?.toString() ?? '';
    final notes = product['researchNotes']?.toString() ?? '';
    final model = product['researchModel']?.toString() ?? '';
    final sources = (product['researchSources'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((source) => Map<String, dynamic>.from(source))
        .toList();
    final reviewedUrls =
        (product['researchReviewedSourceUrls'] as List<dynamic>? ?? [])
            .map((url) => url.toString())
            .where((url) => url.isNotEmpty)
            .toList();
    final rejectedUrls =
        (product['researchRejectedSourceUrls'] as List<dynamic>? ?? [])
            .map((url) => url.toString())
            .where((url) => url.isNotEmpty)
            .toList();

    final hasResearch =
        confidence.isNotEmpty ||
        useCase.isNotEmpty ||
        notes.isNotEmpty ||
        productImageUrl.isNotEmpty ||
        caseImageUrl.isNotEmpty ||
        productImageUrls.isNotEmpty ||
        caseImageUrls.isNotEmpty ||
        sources.isNotEmpty ||
        reviewedUrls.isNotEmpty ||
        rejectedUrls.isNotEmpty;

    if (!hasResearch) return const SizedBox.shrink();

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Investigacion del producto',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _imagePanel(
                  title: 'Producto',
                  imageUrl: productImageUrl,
                  confirmed: hasProductImage,
                ),
                const SizedBox(width: 12),
                _imagePanel(
                  title: 'Caja',
                  imageUrl: caseImageUrl,
                  confirmed: hasCaseImage,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    'Confianza: ${confidence.isEmpty ? '-' : confidence}',
                  ),
                ),
                Chip(
                  label: Text(
                    hasCaseDimensions
                        ? 'Medidas caja OK'
                        : 'Medidas caja pendiente',
                  ),
                ),
                Chip(
                  label: Text(
                    hasCaseWeight ? 'Peso caja OK' : 'Peso caja pendiente',
                  ),
                ),
                Chip(
                  label: Text(
                    needsReview ? 'Revisar manual' : 'Listo para pallet',
                  ),
                ),
              ],
            ),
            _detailLine('Uso', useCase),
            _detailLine('Notas', notes),
            _detailLine('Modelo IA', model),
            _detailLine('Fuentes revisadas', reviewedUrls.length.toString()),
            _detailLine(
              'Fuentes sin datos de caja',
              rejectedUrls.length.toString(),
            ),
            _imageGallery('Imagenes guardadas del producto', productImageUrls),
            _imageGallery('Imagenes guardadas de caja', caseImageUrls),
            if (sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Fuentes',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...sources.map((source) {
                final title = source['title']?.toString() ?? 'Fuente';
                final url = source['url']?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(url.isEmpty ? title : '$title\n$url'),
                );
              }),
            ],
            if (rejectedUrls.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Fuentes ya revisadas sin datos completos de caja',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...rejectedUrls
                  .take(5)
                  .map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText(url),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Producto' : 'Nuevo Producto'),
      ),
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
            _researchDetails(),
            if (_isEditing) const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _skuController,
                    readOnly: _isEditing,
                    decoration: InputDecoration(
                      labelText:
                          'SKU ${_isEditing ? '(bloqueado)' : '(opcional)'}',
                      hintText: _isEditing
                          ? 'El SKU no se cambia en edicion'
                          : 'Si lo dejas vacio se genera automaticamente',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    validator: _requiredValue,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del producto',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _secondNameController,
                    decoration: const InputDecoration(
                      labelText: 'Segundo nombre (opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      hintText: 'Vasos, platos, bolsas, contenedores...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _costController,
                          validator: _optionalMoney,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Costo compra',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _salePriceController,
                          validator: _optionalMoney,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Precio venta',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _unitsPerCaseController,
                    validator: _requiredPositiveWholeNumber,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Unid. por caja',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F6FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'La existencia no se edita aqui. La cantidad entra solamente desde Mapa de Racks al crear un pallet.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _productStatus,
                    decoration: const InputDecoration(
                      labelText: 'Estado comercial',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'activo', child: Text('Activo')),
                      DropdownMenuItem(
                        value: 'bajo_stock',
                        child: Text('Bajo stock'),
                      ),
                      DropdownMenuItem(value: 'lento', child: Text('Lento')),
                      DropdownMenuItem(
                        value: 'pausado',
                        child: Text('Pausado'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _productStatus = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lengthController,
                    validator: _requiredNumber,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Largo (in)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _widthController,
                    validator: _requiredNumber,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Ancho (in)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _heightController,
                    validator: _requiredNumber,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Alto (in)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _weightController,
                    validator: _requiredNumber,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _saving
                            ? (_isEditing
                                  ? 'Actualizando producto...'
                                  : 'Guardando producto...')
                            : (_isEditing
                                  ? 'Actualizar Producto'
                                  : 'Guardar Producto'),
                      ),
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
