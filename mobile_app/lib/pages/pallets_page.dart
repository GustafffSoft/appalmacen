import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';

class PalletsPage extends StatefulWidget {
  const PalletsPage({super.key});

  @override
  State<PalletsPage> createState() => _PalletsPageState();
}

class _PalletsPageState extends State<PalletsPage> {
  final _searchController = TextEditingController();
  String _query = '';

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
    final boxesController = TextEditingController(
      text: _toInt(pallet['boxes']).toString(),
    );
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
                    TextField(
                      controller: boxesController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Cantidad de cajas',
                        prefixIcon: Icon(Icons.numbers),
                        border: OutlineInputBorder(),
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
                        final boxes = int.tryParse(boxesController.text) ?? -1;
                        if (name.isEmpty || boxes < 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Ingresa nombre y cantidad valida.',
                              ),
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
                            boxes: boxes,
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
    boxesController.dispose();
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
                final pallets = snapshot.data!.docs
                    .where((doc) => _matches(doc.data(), doc.id))
                    .toList();
                if (pallets.isEmpty) {
                  return const Center(child: Text('No hay pallets.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: pallets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = pallets[index];
                    final data = doc.data();
                    final boxes = _toInt(data['boxes']);
                    final status = data['status']?.toString() ?? '';
                    final location = data['locationCode']?.toString() ?? '';
                    final photos = _photoUrls(data);
                    final palletName =
                        data['palletName']?.toString() ??
                        'Pallet ${data['sku'] ?? ''}';
                    return Card(
                      child: ListTile(
                        leading: photos.isEmpty
                            ? const Icon(Icons.view_in_ar_outlined)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  photos.first,
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox(
                                    width: 54,
                                    child: Icon(Icons.view_in_ar_outlined),
                                  ),
                                ),
                              ),
                        title: Text(palletName),
                        subtitle: Text(
                          '${data['sku'] ?? ''} - ${data['productName'] ?? ''}\n'
                          '$boxes cajas | ${location.isEmpty ? 'Sin ubicacion' : location} | '
                          '$status | ${photos.length} foto(s)',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editPallet(context, doc.id, data),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
