import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';

enum _PalletView { active, history }

class PalletsPage extends StatefulWidget {
  const PalletsPage({super.key});

  @override
  State<PalletsPage> createState() => _PalletsPageState();
}

class _PalletsPageState extends State<PalletsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  _PalletView _view = _PalletView.active;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isExhausted(Map<String, dynamic> pallet) {
    return pallet['status']?.toString() == 'agotado' ||
        _toInt(pallet['boxes']) <= 0;
  }

  bool _matches(Map<String, dynamic> data, String docId) {
    if (_query.isEmpty) return true;
    final values = [
      data['palletId']?.toString() ?? docId,
      data['palletName'],
      data['sku'],
      data['productName'],
      data['locationCode'],
      data['status'],
    ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
    return values.contains(_query);
  }

  List<String> _photoUrls(Map<String, dynamic> data) {
    final urls = <String>{};
    final primary = data['photoUrl']?.toString() ?? '';
    if (primary.isNotEmpty) urls.add(primary);
    for (final value in data['photoUrls'] as List<dynamic>? ?? []) {
      final url = value.toString();
      if (url.isNotEmpty) urls.add(url);
    }
    return urls.toList();
  }

  String _photoStatusLabel(String status) {
    return switch (status) {
      'pending' => 'Subiendo foto',
      'failed' => 'Foto no subida',
      _ => '',
    };
  }

  Future<void> _addPalletPhoto(BuildContext context, String palletId) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Seleccionar de la galeria'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (image == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 30),
        content: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Subiendo foto...'),
          ],
        ),
      ),
    );
    try {
      await context.read<FirebaseService>().addWarehousePalletImages(
        palletId: palletId,
        images: [image],
      );
      if (!context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Foto guardada.')));
    } catch (error) {
      if (!context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('No se pudo subir: $error')));
    }
  }

  Future<void> _editPallet(
    BuildContext context,
    String palletId,
    Map<String, dynamic> pallet,
  ) async {
    final nameController = TextEditingController(
      text:
          pallet['palletName']?.toString() ??
          'Pallet ${pallet['sku']?.toString() ?? ''}',
    );
    final boxes = _toInt(pallet['boxes']);
    final selectedImages = <XFile>[];
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final existingPhotos = _photoUrls(pallet);
          return AlertDialog(
            title: const Text('Editar pallet'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pallet['sku'] ?? ''} - ${pallet['productName'] ?? ''}',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre o identificador del pallet',
                        prefixIcon: Icon(Icons.label_outline),
                        border: OutlineInputBorder(),
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
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$boxes cajas. La cantidad solo se cambia dando entrada a pallets desde Mapa de Racks.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Fotografias guardadas: ${existingPhotos.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (existingPhotos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: existingPhotos.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) => ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              existingPhotos[index],
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(
                                width: 92,
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  final image = await ImagePicker().pickImage(
                                    source: ImageSource.camera,
                                    imageQuality: 80,
                                  );
                                  if (image != null) {
                                    setDialogState(
                                      () => selectedImages.add(image),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Tomar foto'),
                        ),
                        OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  final images = await ImagePicker()
                                      .pickMultiImage(imageQuality: 80);
                                  if (images.isNotEmpty) {
                                    setDialogState(
                                      () => selectedImages.addAll(images),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Agregar imagenes'),
                        ),
                      ],
                    ),
                    if (selectedImages.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('${selectedImages.length} imagen(es) nuevas'),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ingresa un nombre valido.'),
                            ),
                          );
                          return;
                        }
                        setDialogState(() => saving = true);
                        try {
                          final service = context.read<FirebaseService>();
                          await service.updateWarehousePalletDetails(
                            palletId: palletId,
                            palletName: name,
                          );
                          if (selectedImages.isNotEmpty) {
                            await service.addWarehousePalletImages(
                              palletId: palletId,
                              images: selectedImages,
                            );
                          }
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $error')),
                            );
                          }
                          setDialogState(() => saving = false);
                        }
                      },
                icon: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(saving ? 'Guardando...' : 'Guardar'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
  }

  Future<void> _depletePallet(
    BuildContext context,
    String palletId,
    Map<String, dynamic> pallet,
  ) async {
    final boxes = _toInt(pallet['boxes']);
    if (boxes <= 0) return;
    final name =
        pallet['palletName']?.toString() ?? 'Pallet ${pallet['sku'] ?? ''}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dar de baja pallet'),
        content: Text(
          '¿Confirmas que este pallet esta vacio?\n\n'
          'Se descontaran $boxes cajas del inventario, se quitara del rack '
          'y se guardara en el historial de pallets agotados.\n\n'
          '$name',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Mover al historial'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final deducted = await context
          .read<FirebaseService>()
          .depleteWarehousePallet(palletId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deducted > 0
                ? '$deducted cajas descontadas. Pallet movido al historial.'
                : 'El pallet ya no tenia cantidad disponible.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<FirebaseService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Lista de Pallets')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar pallet, producto, SKU o ubicacion',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: service.watchWarehousePallets(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final matchingPallets = snapshot.data!.docs
                    .where((doc) => _matches(doc.data(), doc.id))
                    .toList();
                final activePallets = matchingPallets
                    .where((doc) => !_isExhausted(doc.data()))
                    .toList();
                final historyPallets = matchingPallets
                    .where((doc) => _isExhausted(doc.data()))
                    .toList();
                final pallets = _view == _PalletView.active
                    ? activePallets
                    : historyPallets;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<_PalletView>(
                          segments: [
                            ButtonSegment(
                              value: _PalletView.active,
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: Text('Activos ${activePallets.length}'),
                            ),
                            ButtonSegment(
                              value: _PalletView.history,
                              icon: const Icon(Icons.history),
                              label: Text('Historial ${historyPallets.length}'),
                            ),
                          ],
                          selected: {_view},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) {
                            setState(() => _view = selection.first);
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: pallets.isEmpty
                          ? Center(
                              child: Text(
                                _view == _PalletView.active
                                    ? 'No hay pallets activos.'
                                    : 'No hay pallets en el historial.',
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              itemCount: pallets.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final doc = pallets[index];
                                final data = doc.data();
                                final exhausted = _isExhausted(data);
                                final boxes = exhausted
                                    ? _toInt(
                                        data['previousBoxes'] ?? data['boxes'],
                                      )
                                    : _toInt(data['boxes']);
                                final status = data['status']?.toString() ?? '';
                                final photoUploadStatus =
                                    data['photoUploadStatus']?.toString() ?? '';
                                final photoStatusLabel = _photoStatusLabel(
                                  photoUploadStatus,
                                );
                                final location = exhausted
                                    ? data['previousLocationCode']
                                              ?.toString() ??
                                          ''
                                    : data['locationCode']?.toString() ?? '';
                                final photos = _photoUrls(data);
                                final palletName =
                                    data['palletName']?.toString() ??
                                    'Pallet ${data['sku'] ?? ''}';
                                final locationLabel = exhausted
                                    ? location.isEmpty
                                          ? 'Sin ubicacion anterior'
                                          : 'Antes: $location'
                                    : location.isEmpty
                                    ? 'Sin ubicacion'
                                    : location;
                                return Card(
                                  child: ListTile(
                                    leading: photos.isEmpty
                                        ? Icon(
                                            photoUploadStatus == 'failed'
                                                ? Icons.broken_image_outlined
                                                : Icons.view_in_ar_outlined,
                                          )
                                        : ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            child: Image.network(
                                              photos.first,
                                              width: 54,
                                              height: 54,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const SizedBox(
                                                    width: 54,
                                                    child: Icon(
                                                      Icons.view_in_ar_outlined,
                                                    ),
                                                  ),
                                            ),
                                          ),
                                    title: Text(palletName),
                                    subtitle: Text(
                                      '${data['sku'] ?? ''} - ${data['productName'] ?? ''}\n'
                                      '$boxes cajas | $locationLabel | '
                                      '${exhausted ? 'Agotado' : status} | ${photos.length} foto(s)'
                                      '${photoStatusLabel.isEmpty ? '' : ' | $photoStatusLabel'}',
                                    ),
                                    isThreeLine: true,
                                    trailing: exhausted
                                        ? const Icon(Icons.history)
                                        : PopupMenuButton<String>(
                                            onSelected: (value) {
                                              if (value == 'edit') {
                                                _editPallet(
                                                  context,
                                                  doc.id,
                                                  data,
                                                );
                                              }
                                              if (value == 'deplete') {
                                                _depletePallet(
                                                  context,
                                                  doc.id,
                                                  data,
                                                );
                                              }
                                              if (value == 'add_photo') {
                                                _addPalletPhoto(
                                                  context,
                                                  doc.id,
                                                );
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.edit_outlined,
                                                  ),
                                                  title: Text('Editar'),
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                ),
                                              ),
                                              if (photos.isEmpty ||
                                                  photoUploadStatus == 'failed')
                                                const PopupMenuItem(
                                                  value: 'add_photo',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons
                                                          .add_a_photo_outlined,
                                                    ),
                                                    title: Text('Agregar foto'),
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                  ),
                                                ),
                                              const PopupMenuItem(
                                                value: 'deplete',
                                                child: ListTile(
                                                  leading: Icon(
                                                    Icons.remove_circle_outline,
                                                  ),
                                                  title: Text('Dar de baja'),
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                ),
                                              ),
                                            ],
                                          ),
                                    onTap: () =>
                                        _editPallet(context, doc.id, data),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
