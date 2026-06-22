import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';
import '../services/order_service.dart';
import '../widgets/pallet_3d_viewer.dart';
import '../widgets/pallet_four_views.dart';

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  bool _uploading = false;
  bool _processing = false;
  String? _loadingReason;

  Future<ImageSource?> _pickImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tomar foto del invoice'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Seleccionar invoice de galeria'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _uploadPhoto() async {
    final firebaseService = context.read<FirebaseService>();
    final source = await _pickImageSource();
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _uploading = true;
      _loadingReason = 'Subiendo imagen del invoice a Firebase Storage...';
    });
    try {
      await firebaseService.uploadOrderImage(
        orderId: widget.orderId,
        file: picked,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice subido correctamente')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error subiendo invoice: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _loadingReason = null;
        });
      }
    }
  }

  Future<void> _processOrder(Map<String, dynamic> order) async {
    final firebaseService = context.read<FirebaseService>();
    final orderService = context.read<OrderService>();
    final imageUrl = order['imageUrl']?.toString();

    setState(() {
      _processing = true;
      _loadingReason =
          'Procesando productos: creando pallets y generando revision IA...';
    });
    try {
      await firebaseService.updateOrderStatus(widget.orderId, 'processing');

      await orderService.processOrder(
        orderId: widget.orderId,
        imageUrl: imageUrl,
        allowOverhangCm: 0,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orden procesada. Se generaron pallets y revision IA.'),
        ),
      );
    } catch (error) {
      await firebaseService.updateOrderStatus(
        widget.orderId,
        'error',
        extra: {'errorMessage': error.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error procesando orden: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          _loadingReason = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(title: Text('Orden ${widget.orderId}')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: firebaseService.watchOrder(widget.orderId),
        builder: (context, orderSnapshot) {
          if (orderSnapshot.hasError) {
            return Center(
              child: Text('Error cargando orden: ${orderSnapshot.error}'),
            );
          }
          if (!orderSnapshot.hasData || !orderSnapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final order = orderSnapshot.data!.data() ?? <String, dynamic>{};
          final status = order['status']?.toString() ?? 'new';
          final imageUrl = order['imageUrl']?.toString() ?? '-';
          final items = (order['items'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadingReason != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    color: Colors.black,
                    child: Text(
                      _loadingReason!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Colors.black12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estado: $status',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SelectableText('Invoice URL (opcional): $imageUrl'),
                        const SizedBox(height: 8),
                        const Text('Items seleccionados:'),
                        const SizedBox(height: 4),
                        if (items.isEmpty)
                          const Text('- Sin items en la orden')
                        else
                          ...items.map(
                            (it) => Text('- ${it['sku']} x ${it['qty']}'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _uploading ? null : _uploadPhoto,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(
                        _uploading
                            ? 'Subiendo invoice...'
                            : 'Subir Invoice (Opcional)',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _processing
                          ? null
                          : () => _processOrder(order),
                      icon: _processing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.view_in_ar),
                      label: Text(
                        _processing
                            ? 'Calculando con IA...'
                            : 'Procesar Pallets con IA',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Resultado del Pallet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: firebaseService.watchPalletPlan(widget.orderId),
                  builder: (context, planSnapshot) {
                    if (planSnapshot.hasError) {
                      return Text(
                        'Error leyendo pallet plan: ${planSnapshot.error}',
                      );
                    }
                    if (!planSnapshot.hasData || !planSnapshot.data!.exists) {
                      return const Text(
                        'Aun no hay resultado para esta orden.',
                      );
                    }

                    final plan =
                        planSnapshot.data!.data() ?? <String, dynamic>{};
                    final stats =
                        (plan['stats'] as Map<String, dynamic>?) ?? {};
                    final pallet =
                        (plan['pallet'] as Map<String, dynamic>?) ?? {};
                    final boxes = (plan['boxes'] as List<dynamic>? ?? [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    final rawPallets = (plan['pallets'] as List<dynamic>? ?? [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    final packingLog =
                        (plan['packingLog'] as List<dynamic>? ?? [])
                            .map((e) => e.toString())
                            .toList();
                    final aiReview =
                        (plan['aiReview'] as Map<String, dynamic>?) ?? {};
                    final aiFinalAnswer =
                        aiReview['finalAnswer']?.toString() ?? '';

                    final palletsToRender = rawPallets.isNotEmpty
                        ? rawPallets
                        : [
                            {
                              'palletNo': 1,
                              'layout': plan['layout'] ?? [],
                              'stats': stats,
                            },
                          ];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Colors.black12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cantidad de pallets: ${plan['palletCount'] ?? palletsToRender.length}',
                                ),
                                Text(
                                  'Peso total (kg): ${stats['totalWeightKg'] ?? '-'}',
                                ),
                                Text(
                                  'Volumen usado (in3): ${stats['usedVolumeCm3'] ?? '-'}',
                                ),
                                Text(
                                  'Utilizacion (%): ${stats['utilizationPct'] ?? '-'}',
                                ),
                                Text(
                                  'No empacadas: ${stats['unpackedCount'] ?? '-'}',
                                ),
                                Text(
                                  'Pallet: ${pallet['lengthCm']}x${pallet['widthCm']}x${pallet['maxHeightCm']} in',
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (aiReview.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Card(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Colors.black12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Plan final IA del pallet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Riesgo: ${aiReview['riskLevel'] ?? '-'}',
                                  ),
                                  if (aiFinalAnswer.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(aiFinalAnswer),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (packingLog.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Card(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Colors.black12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Log de acomodo',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...packingLog
                                      .take(18)
                                      .map((line) => Text('- $line')),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        ...palletsToRender.map((palletView) {
                          final palletStats =
                              (palletView['stats'] as Map<String, dynamic>? ??
                              {});
                          final layout =
                              (palletView['layout'] as List<dynamic>? ?? [])
                                  .map(
                                    (e) => Map<String, dynamic>.from(e as Map),
                                  )
                                  .toList();
                          final packingSummary =
                              (palletView['packingSummary']
                                  as Map<String, dynamic>?) ??
                              {};
                          final layers =
                              (packingSummary['layers'] as List<dynamic>? ?? [])
                                  .map(
                                    (e) => Map<String, dynamic>.from(e as Map),
                                  )
                                  .toList();
                          final notes =
                              (packingSummary['notes'] as List<dynamic>? ?? [])
                                  .map((e) => e.toString())
                                  .toList();
                          final palletNo =
                              palletView['palletNo']?.toString() ?? '?';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pallet $palletNo',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Peso pallet (kg): ${palletStats['totalWeightKg'] ?? '-'}',
                                  ),
                                  Text(
                                    'Volumen pallet (in3): ${palletStats['usedVolumeCm3'] ?? '-'}',
                                  ),
                                  Text(
                                    'Utilizacion pallet (%): ${palletStats['utilizationPct'] ?? '-'}',
                                  ),
                                  if (layers.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Resumen por capas',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ...layers.map(
                                      (layer) => Text(
                                        'Capa ${layer['layer']}: cobertura ${layer['baseCoveragePct']}% | cajas ${layer['boxCount']} | peso ${layer['totalWeightKg']} kg | z ${layer['zStart']}',
                                      ),
                                    ),
                                  ],
                                  if (notes.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    ...notes.map((note) => Text('- $note')),
                                  ],
                                  const SizedBox(height: 8),
                                  PalletFourViews(
                                    layout: layout,
                                    boxes: boxes,
                                    pallet: pallet,
                                  ),
                                  const SizedBox(height: 12),
                                  Pallet3DViewer(
                                    layout: layout,
                                    boxes: boxes,
                                    pallet: pallet,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
