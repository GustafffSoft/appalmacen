import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';
import '../services/order_service.dart';

class ScanProductsPage extends StatefulWidget {
  const ScanProductsPage({super.key});

  @override
  State<ScanProductsPage> createState() => _ScanProductsPageState();
}

class _ScanProductsPageState extends State<ScanProductsPage> {
  final _files = <XFile>[];
  List<Map<String, dynamic>> _products = [];
  bool _scanning = false;
  String? _message;

  Future<void> _takePhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() {
      _files.add(file);
      _products = [];
      _message = '${_files.length} imagen(es) seleccionadas.';
    });
  }

  Future<void> _pickImages() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() {
      _files
        ..clear()
        ..addAll(files);
      _products = [];
      _message = '${_files.length} imagen(es) seleccionadas.';
    });
  }

  void _clear() {
    setState(() {
      _files.clear();
      _products = [];
      _message = null;
    });
  }

  Future<void> _scan() async {
    if (_files.isEmpty) return;
    final firebaseService = context.read<FirebaseService>();
    final orderService = context.read<OrderService>();
    setState(() {
      _scanning = true;
      _products = [];
      _message = 'Analizando productos...';
    });
    try {
      final batchId = 'CAT-${DateTime.now().millisecondsSinceEpoch}';
      final uploaded = await firebaseService.uploadProductCatalogImages(
        batchId: batchId,
        files: _files,
      );
      final response = await orderService.scanProductCatalog(
        payload: {
          'pages': List.generate(
            uploaded.length,
            (index) => {
              'pageNo': index + 1,
              'imagePath': uploaded[index]['imagePath'],
              'imageUrl': uploaded[index]['imageUrl'],
            },
          ),
        },
      );
      if (!mounted) return;
      setState(() {
        _products = (response['products'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _message = response['message']?.toString() ?? 'Analisis completado.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Error escaneando productos: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear Productos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_files.length} imagen(es) seleccionadas',
                        ),
                      ),
                      if (_files.isNotEmpty)
                        IconButton(
                          tooltip: 'Limpiar imagenes',
                          onPressed: _scanning ? null : _clear,
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _scanning ? null : _takePhoto,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Tomar foto'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _scanning ? null : _pickImages,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Cargar imagenes'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _scanning || _files.isEmpty ? null : _scan,
            icon: _scanning
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner_outlined),
            label: Text(_scanning ? 'Analizando...' : 'Escanear productos'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(_message!),
            ),
          ],
          if (_products.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Productos detectados',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._products.map((product) => _ProductResultCard(product: product)),
          ] else if (!_scanning) ...[
            const SizedBox(height: 32),
            const Icon(Icons.qr_code_scanner, size: 64),
            const SizedBox(height: 8),
            const Text(
              'La IA extraera SKU, descripcion y datos visibles del producto. No guardara precios ni creara ordenes.',
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductResultCard extends StatelessWidget {
  const _ProductResultCard({required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final status = product['status']?.toString() ?? 'existing';
    final details = <String>[
      if ((product['category']?.toString() ?? '').isNotEmpty)
        product['category'].toString(),
      if ((product['brand']?.toString() ?? '').isNotEmpty)
        'Marca: ${product['brand']}',
      if ((product['manufacturer']?.toString() ?? '').isNotEmpty)
        'Fabricante: ${product['manufacturer']}',
      if ((product['packDescription']?.toString() ?? '').isNotEmpty)
        'Empaque: ${product['packDescription']}',
      if ((product['barcode']?.toString() ?? '').isNotEmpty)
        'Barcode: ${product['barcode']}',
      if ((product['size']?.toString() ?? '').isNotEmpty)
        'Tamano: ${product['size']}',
      if ((product['material']?.toString() ?? '').isNotEmpty)
        'Material: ${product['material']}',
      if ((product['color']?.toString() ?? '').isNotEmpty)
        'Color: ${product['color']}',
      if ((product['unitsPerCase'] as num?)?.toInt() case final units?
          when units > 1)
        '$units unidades por caja',
    ];
    return Card(
      child: ListTile(
        leading: Icon(
          status == 'created' ? Icons.add_box_outlined : Icons.inventory_2,
        ),
        title: Text(
          '${product['sku'] ?? ''} - ${product['description'] ?? ''}',
        ),
        subtitle: details.isEmpty ? null : Text(details.join(' | ')),
        trailing: Chip(
          label: Text(status == 'created' ? 'Creado' : 'Ya existia'),
          backgroundColor: status == 'created'
              ? const Color(0xFFEAF7EA)
              : const Color(0xFFF1F1F1),
          side: const BorderSide(color: Colors.black12),
        ),
      ),
    );
  }
}
