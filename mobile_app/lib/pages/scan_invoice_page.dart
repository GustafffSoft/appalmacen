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
  final _invoiceNumberController = TextEditingController();
  final _invoiceDateController = TextEditingController();
  final _storeNumberController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _pageCountController = TextEditingController(text: '1');

  final List<_InvoiceItemForm> _items = [_InvoiceItemForm()];
  final List<XFile> _pageFiles = [];
  List<String> _ocrRawLines = const [];
  List<String> _ocrTexts = const [];

  bool _saving = false;
  bool _scanning = false;
  bool _showOcrDebug = false;
  String? _message;

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _invoiceDateController.dispose();
    _storeNumberController.dispose();
    _storeNameController.dispose();
    _addressController.dispose();
    _pageCountController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pickInvoiceDate() async {
    final initial = DateTime.tryParse(_invoiceDateController.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      _invoiceDateController.text = picked.toIso8601String().split('T').first;
    });
  }

  Future<void> _pickPagesFromGallery() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() {
      _pageFiles
        ..clear()
        ..addAll(files);
      _pageCountController.text = _pageFiles.length.toString();
      _ocrRawLines = const [];
      _ocrTexts = const [];
      _message = 'Se cargaron ${_pageFiles.length} paginas del invoice.';
    });
  }

  Future<void> _addPageFromCamera() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return;
    setState(() {
      _pageFiles.add(file);
      _pageCountController.text = _pageFiles.length.toString();
      _ocrRawLines = const [];
      _ocrTexts = const [];
      _message = 'Se agrego la pagina ${_pageFiles.length} desde camara.';
    });
  }

  void _removePage(int index) {
    setState(() {
      _pageFiles.removeAt(index);
      _pageCountController.text = _pageFiles.isEmpty ? '1' : _pageFiles.length.toString();
      _ocrRawLines = const [];
      _ocrTexts = const [];
    });
  }

  void _addLine() {
    setState(() {
      _items.add(_InvoiceItemForm());
    });
  }

  void _removeLine(int index) {
    if (_items.length == 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  void _replaceItems(List<dynamic> items) {
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    for (final raw in items) {
      final map = Map<String, dynamic>.from(raw as Map);
      _items.add(
        _InvoiceItemForm(
          skuValue: map['sku']?.toString() ?? '',
          descriptionValue: map['description']?.toString() ?? '',
          qtyValue: (map['qty'] ?? 1).toString(),
        ),
      );
    }
    if (_items.isEmpty) {
      _items.add(_InvoiceItemForm());
    }
  }

  void _changeQty(int index, int delta) {
    final current = int.tryParse(_items[index].qty.text.trim()) ?? 1;
    final next = (current + delta).clamp(1, 999);
    setState(() {
      _items[index].qty.text = next.toString();
    });
  }

  Future<void> _autoDetectFromPages() async {
    final invoiceNumber = _invoiceNumberController.text.trim();
    if (invoiceNumber.isEmpty) {
      setState(() {
        _message = 'Escribe primero el numero de invoice para poder subir las paginas.';
      });
      return;
    }
    if (_pageFiles.isEmpty) {
      setState(() {
        _message = 'Carga al menos una pagina del invoice antes de autodetectar.';
      });
      return;
    }

    setState(() {
      _scanning = true;
      _message = 'Subiendo paginas y ejecutando OCR...';
    });

    try {
      final uploadedPages = await context.read<FirebaseService>().uploadInvoicePages(
            invoiceNumber: invoiceNumber,
            files: _pageFiles,
          );

      final response = await context.read<OrderService>().scanInvoicePages(
            payload: {
              'invoiceNumber': invoiceNumber,
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

      final ocrAvailable = response['ocrAvailable'] == true;
      final isComplete = response['isComplete'] == true;
      final suggested = Map<String, dynamic>.from(response['suggestedInvoice'] as Map? ?? {});
      final rawLines = (suggested['rawLines'] as List<dynamic>? ?? []).map((line) => line.toString()).toList();
      final extractedTexts = (response['extractedTexts'] as List<dynamic>? ?? []).map((line) => line.toString()).toList();

      if (ocrAvailable && suggested.isNotEmpty) {
        setState(() {
          if ((suggested['invoiceNumber']?.toString() ?? '').isNotEmpty) {
            _invoiceNumberController.text = suggested['invoiceNumber'].toString();
          }
          if ((suggested['invoiceDate']?.toString() ?? '').isNotEmpty) {
            _invoiceDateController.text = suggested['invoiceDate'].toString();
          }
          _storeNumberController.text = suggested['storeNumber']?.toString() ?? _storeNumberController.text;
          _storeNameController.text = suggested['storeName']?.toString() ?? _storeNameController.text;
          _addressController.text = suggested['address']?.toString() ?? _addressController.text;
          _ocrRawLines = rawLines;
          _ocrTexts = extractedTexts;
          final parsedItems = (suggested['items'] as List<dynamic>? ?? []);
          _replaceItems(parsedItems);
          final backendMessage = response['message']?.toString() ?? 'Autodeteccion completada.';
          final statusSuffix = isComplete
              ? ' Invoice listo para confirmar.'
              : ' Revisa tienda, SKU y cantidades antes de registrar.';
          _message = '$backendMessage$statusSuffix';
        });
      } else {
        setState(() {
          _ocrRawLines = rawLines;
          _ocrTexts = extractedTexts;
          _message = response['message']?.toString() ?? 'No se pudo autodetectar el invoice.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Error autodetectando invoice: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final invoiceNumber = _invoiceNumberController.text.trim();
    if (invoiceNumber.isEmpty) {
      setState(() {
        _message = 'Invoice number es obligatorio.';
      });
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (final item in _items) {
      final sku = item.sku.text.trim();
      final description = item.description.text.trim();
      final qty = int.tryParse(item.qty.text.trim());
      if (sku.isEmpty && description.isEmpty) {
        continue;
      }
      if (sku.isEmpty || description.isEmpty || qty == null || qty <= 0) {
        setState(() {
          _message = 'Cada linea debe tener SKU, descripcion y cantidad valida.';
        });
        return;
      }
      items.add({
        'sku': sku,
        'description': description,
        'qty': qty,
        'rate': 0.0,
        'amount': 0.0,
      });
    }

    if (items.isEmpty) {
      setState(() {
        _message = 'Debes agregar al menos una linea del invoice.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _message = _pageFiles.isEmpty
          ? 'Registrando invoice y sincronizando orden...'
          : 'Subiendo paginas del invoice y sincronizando orden...';
    });

    try {
      final uploadedPages = _pageFiles.isEmpty
          ? <Map<String, String>>[]
          : await context.read<FirebaseService>().uploadInvoicePages(
                invoiceNumber: invoiceNumber,
                files: _pageFiles,
              );

      final effectiveInvoiceDate = _invoiceDateController.text.trim().isEmpty
          ? DateTime.now().toIso8601String().split('T').first
          : _invoiceDateController.text.trim();

      final payload = {
        'invoiceNumber': invoiceNumber,
        'invoiceDate': effectiveInvoiceDate,
        'storeNumber': _storeNumberController.text.trim(),
        'storeName': _storeNameController.text.trim(),
        'address': _addressController.text.trim(),
        'subtotal': 0.0,
        'tax': 0.0,
        'total': 0.0,
        'pageCount': _pageFiles.isEmpty ? (int.tryParse(_pageCountController.text.trim()) ?? 1) : uploadedPages.length,
        'pages': List.generate(
          _pageFiles.isEmpty ? (int.tryParse(_pageCountController.text.trim()) ?? 1) : uploadedPages.length,
          (index) => {
            'pageNo': index + 1,
            'imagePath': uploadedPages.isNotEmpty ? uploadedPages[index]['imagePath'] : null,
            'imageUrl': uploadedPages.isNotEmpty ? uploadedPages[index]['imageUrl'] : null,
          },
        ),
        'items': items,
        'sourceMode': uploadedPages.isEmpty ? 'manual_review' : 'manual_review_with_images',
      };

      final response = await context.read<OrderService>().registerInvoice(payload: payload);
      if (!mounted) return;
      final orderId = response['orderId']?.toString();
      if (orderId == null || orderId.isEmpty) {
        throw Exception('No se recibio orderId del backend');
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OrderDetailPage(orderId: orderId)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Error registrando invoice: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _buildInvoiceSummary() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen del invoice',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _invoiceNumberController,
                    decoration: const InputDecoration(labelText: 'Numero de invoice'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _invoiceDateController,
                    readOnly: true,
                    onTap: _pickInvoiceDate,
                    decoration: const InputDecoration(
                      labelText: 'Fecha de invoice',
                      suffixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _storeNumberController,
                    decoration: const InputDecoration(labelText: 'Numero de tienda'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _storeNameController,
                    decoration: const InputDecoration(labelText: 'Nombre de tienda'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Direccion'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectedItemsReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Revision de productos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _saving || _scanning ? null : _addLine,
              icon: const Icon(Icons.add),
              label: const Text('Agregar linea'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.sku.text.trim().isEmpty ? 'Linea ${index + 1}' : item.sku.text.trim(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: _saving || _scanning ? null : () => _removeLine(index),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: item.sku,
                    decoration: const InputDecoration(labelText: 'SKU', isDense: true),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: item.description,
                    minLines: 2,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Descripcion', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: _saving || _scanning ? null : () => _changeQty(index, -1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: item.qty,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: _saving || _scanning ? null : () => _changeQty(index, 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOcrDebug() {
    if (_ocrRawLines.isEmpty && _ocrTexts.isEmpty) {
      return const SizedBox.shrink();
    }

    return ExpansionTile(
      initiallyExpanded: _showOcrDebug,
      onExpansionChanged: (value) => setState(() => _showOcrDebug = value),
      title: const Text('Depuracion OCR'),
      children: [
        if (_ocrRawLines.isNotEmpty)
          ExpansionTile(
            title: const Text('Lineas detectadas'),
            children: _ocrRawLines
                .map(
                  (line) => ListTile(
                    dense: true,
                    title: Text(line, style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
          ),
        if (_ocrTexts.isNotEmpty)
          ExpansionTile(
            title: const Text('Texto OCR por pagina'),
            children: _ocrTexts.asMap().entries.map((entry) {
              return ListTile(
                title: Text('Pagina ${entry.key + 1}'),
                subtitle: SelectableText(entry.value, style: const TextStyle(fontSize: 12)),
              );
            }).toList(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear / Registrar Invoice')),
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
                child: Text(_message!, style: const TextStyle(color: Colors.white)),
              ),
            const Text(
              'Paginas del invoice',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving || _scanning ? null : _pickPagesFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Cargar Paginas'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || _scanning ? null : _addPageFromCamera,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Agregar Camara'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _saving || _scanning ? null : _autoDetectFromPages,
                  icon: _scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined),
                  label: Text(_scanning ? 'Autodetectando...' : 'Autodetectar'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pageCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cantidad de paginas'),
                  ),
                ),
              ],
            ),
            if (_pageFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._pageFiles.asMap().entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text('Pagina ${entry.key + 1}'),
                  subtitle: Text(entry.value.name),
                  trailing: IconButton(
                    onPressed: _saving || _scanning ? null : () => _removePage(entry.key),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildInvoiceSummary(),
            _buildDetectedItemsReview(),
            const SizedBox(height: 8),
            _buildOcrDebug(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _scanning ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_saving ? 'Confirmando invoice...' : 'Confirmar y Crear Orden'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceItemForm {
  _InvoiceItemForm({
    String skuValue = '',
    String descriptionValue = '',
    String qtyValue = '1',
  })  : sku = TextEditingController(text: skuValue),
        description = TextEditingController(text: descriptionValue),
        qty = TextEditingController(text: qtyValue);

  final TextEditingController sku;
  final TextEditingController description;
  final TextEditingController qty;

  void dispose() {
    sku.dispose();
    description.dispose();
    qty.dispose();
  }
}

