import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';
import '../services/order_service.dart';
import 'order_detail_page.dart';

class ScanInvoicePage extends StatefulWidget {
  const ScanInvoicePage({super.key});

  @override
  State<ScanInvoicePage> createState() => _ScanInvoicePageState();
}

class _ScanInvoicePageState extends State<ScanInvoicePage> {
  final _invoiceFiles = <XFile>[];
  final _results = <_ScannedInvoiceResult>[];
  _ScanMode _mode = _ScanMode.multipleInvoices;
  bool _scanning = false;
  int _scannedCount = 0;
  String? _message;

  Future<void> _addInvoiceFromCamera() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() {
      _invoiceFiles.add(file);
      _results.clear();
      _message = '${_invoiceFiles.length} invoice(s) listos para escanear.';
    });
  }

  Future<void> _pickInvoicesFromGallery() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() {
      _invoiceFiles
        ..clear()
        ..addAll(files);
      _results.clear();
      _message = '${_invoiceFiles.length} invoice(s) listos para escanear.';
    });
  }

  void _clearAll() {
    setState(() {
      _invoiceFiles.clear();
      _results.clear();
      _message = null;
      _scannedCount = 0;
    });
  }

  Future<void> _scanInvoices() async {
    if (_invoiceFiles.isEmpty) {
      setState(() {
        _message = 'Toma una foto o carga imagenes de invoices primero.';
      });
      return;
    }

    final firebaseService = context.read<FirebaseService>();
    final orderService = context.read<OrderService>();
    final batchId = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _scanning = true;
      _results.clear();
      _scannedCount = 0;
      _message = 'Escaneando ${_invoiceFiles.length} invoice(s)...';
    });

    try {
      if (_mode == _ScanMode.singleInvoiceMultiplePages) {
        final uploadId = 'MULTIPAGE-$batchId';
        final uploadedPages = await firebaseService.uploadInvoicePages(
          invoiceNumber: uploadId,
          files: _invoiceFiles,
        );
        final response = await orderService.scanInvoicePages(
          payload: {
            'pages': List.generate(
              uploadedPages.length,
              (index) => {
                'pageNo': index + 1,
                'imagePath': uploadedPages[index]['imagePath'],
                'imageUrl': uploadedPages[index]['imageUrl'],
              },
            ),
          },
        );
        final suggested = Map<String, dynamic>.from(
          response['suggestedInvoice'] as Map? ?? {},
        );
        if (!mounted) return;
        setState(() {
          _results.add(
            _ScannedInvoiceResult(
              pageIndex: 1,
              response: response,
              invoice: suggested,
              uploadedPages: uploadedPages,
            ),
          );
          _scannedCount = _invoiceFiles.length;
          _message = 'Invoice de varias paginas escaneado.';
        });
        return;
      }

      for (var index = 0; index < _invoiceFiles.length; index++) {
        final uploadId = 'BATCH-$batchId-${index + 1}';
        final uploadedPages = await firebaseService.uploadInvoicePages(
          invoiceNumber: uploadId,
          files: [_invoiceFiles[index]],
        );
        final response = await orderService.scanInvoicePages(
          payload: {
            'pages': [
              {
                'pageNo': 1,
                'imagePath': uploadedPages.first['imagePath'],
                'imageUrl': uploadedPages.first['imageUrl'],
              },
            ],
          },
        );
        final suggested = Map<String, dynamic>.from(
          response['suggestedInvoice'] as Map? ?? {},
        );
        final result = _ScannedInvoiceResult(
          pageIndex: index + 1,
          response: response,
          invoice: suggested,
          uploadedPages: uploadedPages,
        );
        if (!mounted) return;
        setState(() {
          _results.add(result);
          _scannedCount = index + 1;
          _message =
              'Escaneados $_scannedCount de ${_invoiceFiles.length} invoice(s).';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Error escaneando invoices: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Escanear Invoices')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_ScanMode>(
            segments: const [
              ButtonSegment(
                value: _ScanMode.multipleInvoices,
                icon: Icon(Icons.receipt_long),
                label: Text('Varios invoices'),
              ),
              ButtonSegment(
                value: _ScanMode.singleInvoiceMultiplePages,
                icon: Icon(Icons.layers_outlined),
                label: Text('Un invoice'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _scanning
                ? null
                : (selection) {
                    setState(() {
                      _mode = selection.first;
                      _results.clear();
                      _message = null;
                    });
                  },
          ),
          const SizedBox(height: 12),
          _PhotoActions(
            invoiceCount: _invoiceFiles.length,
            mode: _mode,
            scanning: _scanning,
            onCamera: _addInvoiceFromCamera,
            onGallery: _pickInvoicesFromGallery,
            onClear: _invoiceFiles.isEmpty ? null : _clearAll,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _scanning || _invoiceFiles.isEmpty
                ? null
                : _scanInvoices,
            icon: _scanning
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner),
            label: Text(
              _scanning
                  ? 'Escaneando $_scannedCount/${_invoiceFiles.length}'
                  : _mode == _ScanMode.multipleInvoices
                  ? 'Escanear invoices'
                  : 'Escanear invoice',
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(message: _message!),
          ],
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Resultados', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final result in _results) _InvoiceResultCard(result: result),
          ] else ...[
            const SizedBox(height: 28),
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              _mode == _ScanMode.multipleInvoices
                  ? 'Cada foto se procesa como un invoice distinto.'
                  : 'Todas las fotos se procesan como paginas del mismo invoice.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ],
      ),
    );
  }
}

enum _ScanMode { multipleInvoices, singleInvoiceMultiplePages }

class _ScannedInvoiceResult {
  _ScannedInvoiceResult({
    required this.pageIndex,
    required this.response,
    required this.invoice,
    required this.uploadedPages,
  });

  final int pageIndex;
  final Map<String, dynamic> response;
  final Map<String, dynamic> invoice;
  final List<Map<String, String>> uploadedPages;
  bool saving = false;

  List<dynamic> get items => invoice['items'] as List<dynamic>? ?? const [];

  Set<String> get newProductSkus =>
      (invoice['newProductsDetected'] as List<dynamic>? ??
              invoice['newProductsCreated'] as List<dynamic>? ??
              const [])
          .map((sku) => sku.toString().trim())
          .where((sku) => sku.isNotEmpty)
          .toSet();
}

class _PhotoActions extends StatelessWidget {
  const _PhotoActions({
    required this.invoiceCount,
    required this.mode,
    required this.scanning,
    required this.onCamera,
    required this.onGallery,
    required this.onClear,
  });

  final int invoiceCount;
  final _ScanMode mode;
  final bool scanning;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_camera),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mode == _ScanMode.multipleInvoices
                        ? '$invoiceCount invoice(s) seleccionados'
                        : '$invoiceCount pagina(s) seleccionadas',
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    tooltip: 'Limpiar imagenes',
                    onPressed: scanning ? null : onClear,
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
                  onPressed: scanning ? null : onCamera,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tomar foto'),
                ),
                OutlinedButton.icon(
                  onPressed: scanning ? null : onGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Cargar imagenes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceResultCard extends StatefulWidget {
  const _InvoiceResultCard({required this.result});

  final _ScannedInvoiceResult result;

  @override
  State<_InvoiceResultCard> createState() => _InvoiceResultCardState();
}

class _InvoiceResultCardState extends State<_InvoiceResultCard> {
  Future<void> _createOrder() async {
    final result = widget.result;
    final invoiceNumber = result.invoice['invoiceNumber']?.toString().trim();
    if (invoiceNumber == null ||
        invoiceNumber.isEmpty ||
        result.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este invoice necesita revision manual.')),
      );
      return;
    }

    setState(() => result.saving = true);
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final invoiceDate =
          result.invoice['invoiceDate']?.toString().trim().isNotEmpty == true
          ? result.invoice['invoiceDate'].toString().trim()
          : today;
      final response = await context.read<OrderService>().registerInvoice(
        payload: {
          'invoiceNumber': invoiceNumber,
          'invoiceDate': invoiceDate,
          'storeNumber': result.invoice['storeNumber']?.toString() ?? '',
          'storeName': result.invoice['storeName']?.toString() ?? '',
          'address': result.invoice['address']?.toString() ?? '',
          'subtotal': _toDouble(result.invoice['subtotal']),
          'tax': _toDouble(result.invoice['tax']),
          'total': _toDouble(result.invoice['total']),
          'pageCount': result.uploadedPages.length,
          'sourceMode': 'ai_batch_scan_review',
          'pages': List.generate(
            result.uploadedPages.length,
            (index) => {
              'pageNo': index + 1,
              'imagePath': result.uploadedPages[index]['imagePath'],
              'imageUrl': result.uploadedPages[index]['imageUrl'],
            },
          ),
          'items': result.items.map((raw) {
            final item = Map<String, dynamic>.from(raw as Map);
            return {
              'sku': item['sku']?.toString() ?? '',
              'description': item['description']?.toString() ?? '',
              'qty': _toInt(item['qty'], fallback: 1),
              'rate': _toDouble(item['rate']),
              'amount': _toDouble(item['amount']),
              'category': item['category']?.toString() ?? 'General',
              'unitsPerCase': _toInt(item['unitsPerCase'], fallback: 1),
              'alternateSkus': (item['alternateSkus'] as List<dynamic>? ?? [])
                  .map((value) => value.toString())
                  .toList(),
            };
          }).toList(),
        },
      );
      final orderId = response['orderId']?.toString();
      if (!mounted) return;
      if (orderId == null || orderId.isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderDetailPage(orderId: orderId)),
      );
    } finally {
      if (mounted) setState(() => result.saving = false);
    }
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final invoiceNumber =
        result.invoice['invoiceNumber']?.toString().trim().isNotEmpty == true
        ? result.invoice['invoiceNumber'].toString()
        : 'No detectado';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invoice ${result.pageIndex}: $invoiceNumber',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Tienda',
              value: result.invoice['storeName']?.toString() ?? '',
            ),
            _SummaryRow(
              label: 'Productos',
              value:
                  '${result.items.length} detectados, ${result.newProductSkus.length} nuevos',
            ),
            const SizedBox(height: 8),
            _ProductsList(
              items: result.items,
              newProductSkus: result.newProductSkus,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: result.saving ? null : _createOrder,
              icon: result.saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_shopping_cart),
              label: Text(result.saving ? 'Creando orden...' : 'Crear orden'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: TextStyle(color: colors.onPrimaryContainer)),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cleanValue = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(cleanValue)),
        ],
      ),
    );
  }
}

class _ProductsList extends StatelessWidget {
  const _ProductsList({required this.items, required this.newProductSkus});

  final List<dynamic> items;
  final Set<String> newProductSkus;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('No se detectaron productos.');
    }
    return Column(
      children: [
        for (final raw in items)
          _ProductTile(
            item: Map<String, dynamic>.from(raw as Map),
            isNew: newProductSkus.contains(raw['sku']?.toString().trim()),
          ),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.item, required this.isNew});

  final Map<String, dynamic> item;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final sku = item['sku']?.toString() ?? '';
    final description = item['description']?.toString() ?? '';
    final qty = item['qty']?.toString() ?? '1';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(description.isEmpty ? sku : description),
      subtitle: Text('SKU: $sku | Qty: $qty'),
      trailing: Text(isNew ? 'Nuevo' : 'Existente'),
    );
  }
}
