import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/firebase_service.dart';

const _fourPositions = [
  _RackPosition('FI', 'Frente izq.'),
  _RackPosition('FD', 'Frente der.'),
  _RackPosition('AI', 'Atras izq.'),
  _RackPosition('AD', 'Atras der.'),
];
const _twoPositions = [
  _RackPosition('F', 'Frente'),
  _RackPosition('A', 'Atras'),
];

int _rackNumberFromIdOrName(Map<String, dynamic> rack, int fallback) {
  final values = [
    rack['rackNumber'],
    rack['rackId'],
    rack['name'],
  ].map((value) => value?.toString() ?? '');
  for (final value in values) {
    final match = RegExp(r'(\d+)').firstMatch(value);
    final number = int.tryParse(match?.group(1) ?? '');
    if (number != null && number > 0) return number;
  }
  return fallback;
}

String _rackDisplayName(Map<String, dynamic> rack, int rackNumber) {
  final name = rack['name']?.toString().trim() ?? '';
  if (name.isNotEmpty &&
      !RegExp(r'^Rack\s+[A-Z]+$', caseSensitive: false).hasMatch(name)) {
    return name;
  }
  return 'Rack $rackNumber';
}

int _positionNumber(List<_RackPosition> positions, _RackPosition position) {
  final index = positions.indexWhere((item) => item.code == position.code);
  return index < 0 ? 1 : index + 1;
}

String _positionDisplayCode(
  int rackNumber,
  List<_RackPosition> positions,
  _RackPosition position,
) {
  return '$rackNumber.${_positionNumber(positions, position)}';
}

List<int> _levelsForRack(Map<String, dynamic> rack) {
  final raw = rack['levels'];
  final levels = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  final safeLevels = (levels == null || levels < 1) ? 1 : levels;
  return List.generate(safeLevels, (index) => safeLevels - index);
}

List<_RackPosition> _positionsForRack(Map<String, dynamic> rack) {
  final raw = rack['positionsPerLevel'];
  final count = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  return count == 2 ? _twoPositions : _fourPositions;
}

class WarehouseRackPage extends StatefulWidget {
  const WarehouseRackPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<WarehouseRackPage> createState() => _WarehouseRackPageState();
}

class _WarehouseRackPageState extends State<WarehouseRackPage> {
  String _query = '';
  List<Map<String, dynamic>> _currentRacks = [];

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _nextRackNumber(List<Map<String, dynamic>> racks) {
    final usedNumbers = <int>{};
    for (var index = 0; index < racks.length; index++) {
      usedNumbers.add(_rackNumberFromIdOrName(racks[index], index + 1));
    }
    var number = usedNumbers.isEmpty
        ? 1
        : usedNumbers.reduce((a, b) => a > b ? a : b) + 1;
    while (true) {
      if (!usedNumbers.contains(number)) return number;
      number++;
    }
  }

  Future<void> _showRackDialog(
    BuildContext context, {
    Map<String, dynamic>? rack,
  }) async {
    final isEditing = rack != null;
    final autoNumber = _nextRackNumber(_currentRacks);
    final rackId = isEditing
        ? rack['rackId']?.toString() ?? ''
        : 'RACK-$autoNumber';
    final nameController = TextEditingController(
      text: isEditing
          ? rack['name']?.toString() ?? 'Rack $autoNumber'
          : 'Rack $autoNumber',
    );
    var levels = isEditing ? _toInt(rack['levels']) : 1;
    if (levels < 1) levels = 1;
    var positionsPerLevel = isEditing ? _toInt(rack['positionsPerLevel']) : 4;
    if (positionsPerLevel != 2) positionsPerLevel = 4;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'Editar rack' : 'Agregar rack'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      readOnly: !isEditing,
                      enableInteractiveSelection: isEditing,
                      textCapitalization: isEditing
                          ? TextCapitalization.characters
                          : TextCapitalization.none,
                      decoration: InputDecoration(
                        labelText: isEditing
                            ? 'Nombre visible del rack'
                            : 'Nombre automatico',
                        helperText: isEditing
                            ? 'Puedes cambiar el nombre sin perder ubicaciones.'
                            : 'El sistema asigna numeros automaticamente.',
                        prefixIcon: isEditing
                            ? const Icon(Icons.edit_outlined)
                            : const Icon(Icons.tag_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: levels,
                      decoration: const InputDecoration(labelText: 'Pisos'),
                      items: List.generate(
                        8,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text('${index + 1} piso(s)'),
                        ),
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => levels = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 2,
                          label: Text('2 posiciones'),
                          icon: Icon(Icons.view_agenda_outlined),
                        ),
                        ButtonSegment(
                          value: 4,
                          label: Text('4 posiciones'),
                          icon: Icon(Icons.grid_view_outlined),
                        ),
                      ],
                      selected: {positionsPerLevel},
                      onSelectionChanged: (selection) {
                        setDialogState(
                          () => positionsPerLevel = selection.first,
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    await context.read<FirebaseService>().saveWarehouseRack(
                      rackId: rackId,
                      name: name,
                      levels: levels,
                      positionsPerLevel: positionsPerLevel,
                      rackNumber: isEditing
                          ? _rackNumberFromIdOrName(rack, autoNumber)
                          : autoNumber,
                    );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: Text(isEditing ? 'Actualizar' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showPalletEntryDialog(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocs,
  ) async {
    final quantityController = TextEditingController();
    var productQuery = '';
    var productQueryText = '';
    Map<String, dynamic>? selectedProduct;
    String selectedSku = '';
    XFile? selectedPhoto;
    var saving = false;
    var creatingProduct = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredProducts = productDocs
                .where((doc) {
                  final data = doc.data();
                  final sku = data['sku']?.toString() ?? doc.id;
                  if (productQuery.isEmpty) return true;
                  final name = (data['name']?.toString() ?? '').toLowerCase();
                  final secondName = (data['secondName']?.toString() ?? '')
                      .toLowerCase();
                  final alternateSkus =
                      (data['alternateSkus'] as List<dynamic>? ?? [])
                          .map((item) => item.toString().toLowerCase())
                          .join(' ');
                  return name.contains(productQuery) ||
                      secondName.contains(productQuery) ||
                      alternateSkus.contains(productQuery) ||
                      sku.toLowerCase().contains(productQuery);
                })
                .take(12)
                .toList();

            return AlertDialog(
              title: const Text('Dar entrada a pallet'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Buscar producto por nombre o codigo',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            productQueryText = value.trim();
                            productQuery = productQueryText.toLowerCase();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child:
                            filteredProducts.isEmpty && productQuery.isNotEmpty
                            ? ListTile(
                                leading: const Icon(Icons.add_box_outlined),
                                title: const Text('Crear producto'),
                                subtitle: Text(productQueryText),
                                trailing: creatingProduct
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.add),
                                onTap: creatingProduct
                                    ? null
                                    : () async {
                                        setDialogState(
                                          () => creatingProduct = true,
                                        );
                                        try {
                                          final product = await context
                                              .read<FirebaseService>()
                                              .createMinimalProduct(
                                                name: productQueryText,
                                              );
                                          setDialogState(() {
                                            selectedProduct = product;
                                            selectedSku = product['sku']
                                                .toString();
                                            creatingProduct = false;
                                          });
                                        } catch (error) {
                                          setDialogState(
                                            () => creatingProduct = false,
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'No se pudo crear: $error',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final doc = filteredProducts[index];
                                  final data = doc.data();
                                  final sku = data['sku']?.toString() ?? doc.id;
                                  final name =
                                      data['name']?.toString() ?? 'Producto';
                                  final selected = selectedSku == sku;
                                  return ListTile(
                                    selected: selected,
                                    dense: true,
                                    title: Text('$sku - $name'),
                                    trailing: selected
                                        ? const Icon(Icons.check_circle)
                                        : null,
                                    onTap: () {
                                      setDialogState(() {
                                        selectedProduct = data;
                                        selectedSku = sku;
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                      if (selectedProduct != null) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.check_circle),
                          title: Text(
                            selectedProduct!['name']?.toString() ?? 'Producto',
                          ),
                          subtitle: Text(selectedSku),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: quantityController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Cantidad de cajas en este pallet',
                          prefixIcon: Icon(Icons.numbers),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final source =
                              await showModalBottomSheet<ImageSource>(
                                context: context,
                                builder: (context) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.camera_alt),
                                        title: const Text('Tomar foto'),
                                        onTap: () => Navigator.of(
                                          context,
                                        ).pop(ImageSource.camera),
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.photo_library,
                                        ),
                                        title: const Text(
                                          'Seleccionar galeria',
                                        ),
                                        onTap: () => Navigator.of(
                                          context,
                                        ).pop(ImageSource.gallery),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                          if (source == null) return;
                          final file = await ImagePicker().pickImage(
                            source: source,
                            imageQuality: 60,
                            maxWidth: 1600,
                            maxHeight: 1600,
                          );
                          if (file != null) {
                            setDialogState(() => selectedPhoto = file);
                          }
                        },
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          selectedPhoto == null
                              ? 'Foto obligatoria del pallet'
                              : 'Foto seleccionada',
                        ),
                      ),
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
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final qty =
                              int.tryParse(quantityController.text.trim()) ?? 0;
                          if (selectedProduct == null ||
                              selectedSku.isEmpty ||
                              qty <= 0 ||
                              selectedPhoto == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Selecciona producto, cantidad y foto del pallet.',
                                ),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => saving = true);
                          final productName =
                              selectedProduct!['name']?.toString() ??
                              'Producto';
                          try {
                            await context
                                .read<FirebaseService>()
                                .createWarehousePalletEntry(
                                  sku: selectedSku,
                                  productName: productName,
                                  boxes: qty,
                                  photo: selectedPhoto!,
                                );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Pallet creado. La foto seguira subiendo en segundo plano.',
                                  ),
                                ),
                              );
                            }
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error creando pallet: $error'),
                                ),
                              );
                            }
                            setDialogState(() => saving = false);
                          }
                        },
                  child: Text(saving ? 'Guardando...' : 'Guardar pallet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteRack(
    BuildContext context,
    Map<String, dynamic> rack,
  ) async {
    final rackId = rack['rackId']?.toString() ?? '';
    final name = rack['name']?.toString() ?? rackId;
    if (rackId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Eliminar $name'),
        content: const Text(
          'Esto elimina el rack y deja sin ubicacion los pallets que esten dentro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await context.read<FirebaseService>().deleteWarehouseRack(rackId);
    }
  }

  Map<String, List<Map<String, dynamic>>> _placedByLocation(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final data = {'palletId': doc.id, ...doc.data()};
      final code = data['locationCode']?.toString() ?? '';
      if (code.isNotEmpty) {
        result.putIfAbsent(code, () => []).add(data);
      }
    }
    return result;
  }

  bool _palletMatchesQuery(Map<String, dynamic> pallet, String query) {
    if (query.isEmpty) return true;
    final values = [
      pallet['palletId'],
      pallet['palletName'],
      pallet['sku'],
      pallet['productName'],
      pallet['locationCode'],
      pallet['rackId'],
      pallet['position'],
    ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
    return values.contains(query);
  }

  bool _rackHasQueryMatch(
    Map<String, dynamic> rack,
    int rackNumber,
    Map<String, List<Map<String, dynamic>>> placedByLocation,
    String query,
  ) {
    if (query.isEmpty) return true;
    final rackId = rack['rackId']?.toString() ?? '';
    final rackName = _rackDisplayName(rack, rackNumber);
    final rackValues = [
      rackId,
      rackName,
      'rack $rackNumber',
    ].map((value) => value.toLowerCase()).join(' ');
    if (rackValues.contains(query)) return true;
    final levels = _levelsForRack(rack);
    final positions = _positionsForRack(rack);
    for (final level in levels) {
      for (final position in positions) {
        final positionCode = _positionDisplayCode(
          rackNumber,
          positions,
          position,
        );
        final visibleLocation = [
          positionCode,
          position.label,
          '$rackName piso $level $positionCode',
        ].map((value) => value.toLowerCase()).join(' ');
        if (visibleLocation.contains(query)) return true;
        final locationCode = '$rackId-L$level-${position.code}';
        final pallets = placedByLocation[locationCode] ?? [];
        if (pallets.any((pallet) => _palletMatchesQuery(pallet, query))) {
          return true;
        }
      }
    }
    return false;
  }

  Future<bool> _placePallet(
    BuildContext context, {
    required Map<String, dynamic> pallet,
    required String rackId,
    required int level,
    required String position,
  }) async {
    final firebaseService = context.read<FirebaseService>();
    final palletId = pallet['palletId'].toString();
    final targetLocation = '$rackId-L$level-$position';
    final currentLocation = pallet['locationCode']?.toString() ?? '';
    Map<String, int>? consumed;
    if (level == 1 && currentLocation != targetLocation) {
      final isEmpty = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text('$rackId - Piso 1 - $position'),
          content: const Text('¿Esta posicion del piso 1 esta vacia?'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No esta vacia'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Esta vacia'),
            ),
          ],
        ),
      );
      if (isEmpty == null || !context.mounted) return false;
      if (isEmpty) {
        consumed = await firebaseService.consumeFirstFloorLocation(
          rackId: rackId,
          position: position,
          excludingPalletId: palletId,
        );
      }
    }
    await firebaseService.saveWarehousePalletLocation(
      palletId: palletId,
      sku: pallet['sku'].toString(),
      productName: pallet['productName'].toString(),
      boxes: _toInt(pallet['boxes']),
      rackId: rackId,
      level: level,
      position: position,
    );
    if (context.mounted && consumed != null && consumed['boxes']! > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${consumed['boxes']} cajas descontadas de '
            '${consumed['pallets']} pallet(s) agotados.',
          ),
        ),
      );
    }
    return true;
  }

  Future<void> _clearPalletLocation(
    BuildContext context,
    Map<String, dynamic> pallet,
  ) async {
    final palletId = pallet['palletId']?.toString() ?? '';
    if (palletId.isEmpty) return;
    await context.read<FirebaseService>().clearWarehousePalletLocation(
      palletId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pallet fuera del rack.')));
    }
  }

  Future<void> _depletePallet(
    BuildContext context,
    Map<String, dynamic> pallet,
  ) async {
    final palletId = pallet['palletId']?.toString() ?? '';
    final boxes = _toInt(pallet['boxes']);
    if (palletId.isEmpty || boxes <= 0) return;
    final name =
        pallet['palletName']?.toString() ?? 'Pallet ${pallet['sku'] ?? ''}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dar de baja pallet'),
        content: Text(
          'Este pallet esta vacio?\n\n'
          'Se descontaran $boxes cajas del inventario y el pallet quedara como agotado.\n\n'
          '$name',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Dar de baja'),
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
                ? '$deducted cajas descontadas. Pallet agotado.'
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
    final body = _buildRackBody(context);
    if (widget.embedded) {
      return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 2),
                child: Row(
                  children: [
                    const Icon(Icons.view_module_outlined, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mapa de Racks',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Entrada y ubicacion de pallets',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Agregar rack',
                      onPressed: () => _showRackDialog(context),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      icon: const Icon(Icons.add, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Racks'),
        actions: [
          IconButton(
            tooltip: 'Agregar rack',
            onPressed: () => _showRackDialog(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildRackBody(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firebaseService.watchProducts(),
      builder: (context, productSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firebaseService.watchWarehousePallets(),
          builder: (context, palletSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firebaseService.watchWarehouseRacks(),
              builder: (context, rackSnapshot) {
                if (productSnapshot.hasError ||
                    palletSnapshot.hasError ||
                    rackSnapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error cargando mapa: ${productSnapshot.error ?? palletSnapshot.error ?? rackSnapshot.error}',
                    ),
                  );
                }
                if (!productSnapshot.hasData ||
                    !palletSnapshot.hasData ||
                    !rackSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final racks =
                    rackSnapshot.data!.docs
                        .map((doc) => {'rackId': doc.id, ...doc.data()})
                        .toList()
                      ..sort((a, b) {
                        final numberComparison = _rackNumberFromIdOrName(
                          a,
                          1 << 30,
                        ).compareTo(_rackNumberFromIdOrName(b, 1 << 30));
                        if (numberComparison != 0) return numberComparison;
                        return (a['name']?.toString() ?? '').compareTo(
                          b['name']?.toString() ?? '',
                        );
                      });
                _currentRacks = racks;
                final palletDocs = palletSnapshot.data!.docs;
                final placedByLocation = _placedByLocation(palletDocs);
                final filteredRacks = <Map<String, dynamic>>[
                  for (var index = 0; index < racks.length; index++)
                    if (_rackHasQueryMatch(
                      racks[index],
                      _rackNumberFromIdOrName(racks[index], index + 1),
                      placedByLocation,
                      _query,
                    ))
                      racks[index],
                ];
                final products = productSnapshot.data!.docs;
                final unassigned =
                    palletDocs
                        .map((doc) => {'palletId': doc.id, ...doc.data()})
                        .where((pallet) {
                          final locationCode =
                              pallet['locationCode']?.toString() ?? '';
                          final boxes = _toInt(pallet['boxes']);
                          final status = pallet['status']?.toString() ?? '';
                          return locationCode.isEmpty &&
                              boxes > 0 &&
                              status != 'agotado' &&
                              _palletMatchesQuery(pallet, _query);
                        })
                        .toList()
                      ..sort(
                        (a, b) =>
                            _toInt(a['boxes']).compareTo(_toInt(b['boxes'])),
                      );

                return Column(
                  children: [
                    SizedBox(
                      height: unassigned.isEmpty ? 188 : 231,
                      child: _PendingPalletsPanel(
                        pallets: unassigned,
                        query: _query,
                        onAddPallet: () =>
                            _showPalletEntryDialog(context, products),
                        onDropOutside: (pallet) =>
                            _clearPalletLocation(context, pallet),
                        onDepletePallet: (pallet) =>
                            _depletePallet(context, pallet),
                        onQueryChanged: (value) {
                          setState(() => _query = value.trim().toLowerCase());
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _RackMap(
                        racks: filteredRacks,
                        placedByLocation: placedByLocation,
                        query: _query,
                        onEditRack: (rack) =>
                            _showRackDialog(context, rack: rack),
                        onDeleteRack: (rack) => _deleteRack(context, rack),
                        onDepletePallet: (pallet) =>
                            _depletePallet(context, pallet),
                        onAccept: (pallet, rackId, level, position) async {
                          await _placePallet(
                            context,
                            pallet: pallet,
                            rackId: rackId,
                            level: level,
                            position: position,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _RackMap extends StatefulWidget {
  const _RackMap({
    required this.racks,
    required this.placedByLocation,
    required this.query,
    required this.onEditRack,
    required this.onDeleteRack,
    required this.onDepletePallet,
    required this.onAccept,
  });

  final List<Map<String, dynamic>> racks;
  final Map<String, List<Map<String, dynamic>>> placedByLocation;
  final String query;
  final ValueChanged<Map<String, dynamic>> onEditRack;
  final ValueChanged<Map<String, dynamic>> onDeleteRack;
  final ValueChanged<Map<String, dynamic>> onDepletePallet;
  final Future<void> Function(
    Map<String, dynamic> pallet,
    String rackId,
    int level,
    String position,
  )
  onAccept;

  @override
  State<_RackMap> createState() => _RackMapState();
}

class _RackMapState extends State<_RackMap> {
  final _scrollController = ScrollController();
  final _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _sectionKeys = {};
  List<_RackSectionInfo> _visibleSections = [];
  String? _selectedRackId;
  String _currentTitle = '';
  String _currentSubtitle = '';

  @override
  void initState() {
    super.initState();
    _selectedRackId = widget.racks.isEmpty
        ? null
        : widget.racks.first['rackId']?.toString();
    _scrollController.addListener(_scheduleCurrentSectionUpdate);
  }

  @override
  void didUpdateWidget(covariant _RackMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.racks.isEmpty) {
      _selectedRackId = null;
      _currentTitle = '';
      _currentSubtitle = '';
    } else if (_selectedRackId == null ||
        !widget.racks.any(
          (rack) => rack['rackId']?.toString() == _selectedRackId,
        )) {
      _selectedRackId = widget.racks.first['rackId']?.toString();
      _currentTitle = '';
      _currentSubtitle = '';
    }
    _scheduleCurrentSectionUpdate();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scheduleCurrentSectionUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleCurrentSectionUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateCurrentSection();
    });
  }

  void _selectRack(String rackId) {
    if (_selectedRackId == rackId) return;
    setState(() {
      _selectedRackId = rackId;
      _currentTitle = '';
      _currentSubtitle = '';
      _visibleSections = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _scheduleCurrentSectionUpdate();
    });
  }

  void _updateCurrentSection() {
    if (_visibleSections.isEmpty) return;
    final viewportContext = _viewportKey.currentContext;
    if (viewportContext == null) return;
    final viewportBox = viewportContext.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;

    _RackSectionInfo? current;
    _RackSectionInfo? firstBelow;
    for (final section in _visibleSections) {
      final sectionContext = section.key.currentContext;
      if (sectionContext == null) continue;
      final sectionBox = sectionContext.findRenderObject() as RenderBox?;
      if (sectionBox == null || !sectionBox.hasSize) continue;
      final top = sectionBox.localToGlobal(Offset.zero).dy - viewportTop;
      if (top <= 8) {
        current = section;
      } else {
        firstBelow ??= section;
      }
    }
    final next = current ?? firstBelow ?? _visibleSections.first;
    if (_currentTitle == next.title && _currentSubtitle == next.subtitle) {
      return;
    }
    setState(() {
      _currentTitle = next.title;
      _currentSubtitle = next.subtitle;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.racks.isEmpty) {
      return Center(
        child: Text(
          widget.query.isEmpty
              ? 'No hay racks creados. Usa + para agregar el primero.'
              : 'No hay pallets en racks con esa busqueda.',
        ),
      );
    }
    final selectedRackId =
        widget.racks.any(
          (rack) => rack['rackId']?.toString() == _selectedRackId,
        )
        ? _selectedRackId!
        : widget.racks.first['rackId']?.toString() ?? '';
    final selectedRackIndex = widget.racks.indexWhere(
      (rack) => rack['rackId']?.toString() == selectedRackId,
    );
    final rackIndex = selectedRackIndex < 0 ? 0 : selectedRackIndex;
    final rack = widget.racks[rackIndex];
    final rackId = rack['rackId']?.toString() ?? '';
    final rackNumber = _rackNumberFromIdOrName(rack, rackIndex + 1);
    final rackName = _rackDisplayName(rack, rackNumber);
    final levels = _levelsForRack(rack);
    final positions = _positionsForRack(rack);
    final sections = <_RackSectionInfo>[];
    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _RackControls(
            rackName: rackName,
            levelCount: levels.length,
            positionCount: positions.length,
            onEdit: () => widget.onEditRack(rack),
            onDelete: () => widget.onDeleteRack(rack),
          ),
        ),
      ),
    );
    for (final level in levels) {
      final hasVisiblePosition = positions.any((position) {
        if (widget.query.isEmpty) return true;
        final positionCode = _positionDisplayCode(
          rackNumber,
          positions,
          position,
        );
        final visibleLocation = [
          rackName,
          'rack $rackNumber',
          positionCode,
          position.label,
          'piso $level',
        ].map((value) => value.toLowerCase()).join(' ');
        if (visibleLocation.contains(widget.query)) return true;
        final locationCode = '$rackId-L$level-${position.code}';
        final pallets = widget.placedByLocation[locationCode] ?? [];
        return pallets.any((pallet) {
          final values = [
            pallet['palletId'],
            pallet['sku'],
            pallet['productName'],
            pallet['locationCode'],
            pallet['rackId'],
            pallet['position'],
          ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
          return values.contains(widget.query);
        });
      });
      if (!hasVisiblePosition) continue;
      final sectionId = '$rackId-$level';
      final sectionKey = _sectionKeys.putIfAbsent(sectionId, () => GlobalKey());
      final section = _RackSectionInfo(
        title: '$rackName - Piso $level',
        subtitle:
            '${positions.length} posiciones por piso - $rackNumber.1 a $rackNumber.${positions.length}',
        key: sectionKey,
      );
      sections.add(section);
      slivers.add(
        SliverToBoxAdapter(
          child: KeyedSubtree(
            key: sectionKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RackSectionTitle(
                  title: section.title,
                  subtitle: section.subtitle,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _RackLevelGrid(
                    rackId: rackId,
                    rackName: rackName,
                    rackNumber: rackNumber,
                    level: level,
                    positions: positions,
                    placedByLocation: widget.placedByLocation,
                    query: widget.query,
                    onDepletePallet: widget.onDepletePallet,
                    onAccept: widget.onAccept,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 12)));

    _visibleSections = sections;
    if (_visibleSections.isNotEmpty && _currentTitle.isEmpty) {
      _currentTitle = _visibleSections.first.title;
      _currentSubtitle = _visibleSections.first.subtitle;
      _scheduleCurrentSectionUpdate();
    }

    return Column(
      children: [
        _RackSelector(
          racks: widget.racks,
          selectedRackId: selectedRackId,
          onSelected: _selectRack,
        ),
        _CurrentRackHeader(title: _currentTitle, subtitle: _currentSubtitle),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _scheduleCurrentSectionUpdate();
              return false;
            },
            child: CustomScrollView(
              key: _viewportKey,
              controller: _scrollController,
              slivers: slivers,
            ),
          ),
        ),
      ],
    );
  }
}

class _RackSelector extends StatelessWidget {
  const _RackSelector({
    required this.racks,
    required this.selectedRackId,
    required this.onSelected,
  });

  final List<Map<String, dynamic>> racks;
  final String selectedRackId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        height: 46,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 10, right: 6),
              child: Icon(Icons.view_module_outlined, size: 18),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 5),
                itemCount: racks.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final rack = racks[index];
                  final rackId = rack['rackId']?.toString() ?? '';
                  final rackNumber = _rackNumberFromIdOrName(rack, index + 1);
                  final selected = rackId == selectedRackId;
                  return Tooltip(
                    message: 'Rack $rackNumber',
                    child: OutlinedButton(
                      onPressed: rackId.isEmpty
                          ? null
                          : () => onSelected(rackId),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        foregroundColor: selected ? Colors.white : Colors.black,
                        backgroundColor: selected ? Colors.black : Colors.white,
                        side: const BorderSide(color: Colors.black),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        '$rackNumber',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _RackSectionInfo {
  const _RackSectionInfo({
    required this.title,
    required this.subtitle,
    required this.key,
  });

  final String title;
  final String subtitle;
  final GlobalKey key;
}

class _RackControls extends StatelessWidget {
  const _RackControls({
    required this.rackName,
    required this.levelCount,
    required this.positionCount,
    required this.onEdit,
    required this.onDelete,
  });

  final String rackName;
  final int levelCount;
  final int positionCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rackName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$levelCount pisos · $positionCount posiciones por piso',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Editar rack',
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'Eliminar rack',
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentRackHeader extends StatelessWidget {
  const _CurrentRackHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          children: [
            const Icon(Icons.view_module_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
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

class _RackSectionTitle extends StatelessWidget {
  const _RackSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.view_module_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RackLevelGrid extends StatelessWidget {
  const _RackLevelGrid({
    required this.rackId,
    required this.rackName,
    required this.rackNumber,
    required this.level,
    required this.positions,
    required this.placedByLocation,
    required this.query,
    required this.onDepletePallet,
    required this.onAccept,
  });

  final String rackId;
  final String rackName;
  final int rackNumber;
  final int level;
  final List<_RackPosition> positions;
  final Map<String, List<Map<String, dynamic>>> placedByLocation;
  final String query;
  final ValueChanged<Map<String, dynamic>> onDepletePallet;
  final Future<void> Function(
    Map<String, dynamic> pallet,
    String rackId,
    int level,
    String position,
  )
  onAccept;

  @override
  Widget build(BuildContext context) {
    bool positionMatches(_RackPosition position) {
      if (query.isEmpty) return true;
      final positionCode = _positionDisplayCode(
        rackNumber,
        positions,
        position,
      );
      final visibleLocation = [
        'rack $rackNumber',
        positionCode,
        position.label,
        'piso $level',
      ].map((value) => value.toLowerCase()).join(' ');
      if (visibleLocation.contains(query)) return true;
      final locationCode = '$rackId-L$level-${position.code}';
      final pallets = placedByLocation[locationCode] ?? [];
      return pallets.any((pallet) {
        final values = [
          pallet['palletId'],
          pallet['sku'],
          pallet['productName'],
          pallet['locationCode'],
          pallet['rackId'],
          pallet['position'],
        ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
        return values.contains(query);
      });
    }

    final hasVisiblePosition = positions.any(positionMatches);
    if (!hasVisiblePosition) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: GridView.count(
          crossAxisCount: positions.length < 4 ? 4 : positions.length,
          childAspectRatio: 1.25,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: positions.map((position) {
            if (!positionMatches(position)) {
              return const SizedBox.shrink();
            }
            final locationCode = '$rackId-L$level-${position.code}';
            final pallets = placedByLocation[locationCode] ?? [];
            final positionCode = _positionDisplayCode(
              rackNumber,
              positions,
              position,
            );
            final visiblePositionMatches = [
              'rack $rackNumber',
              positionCode,
              position.label,
              'piso $level',
            ].map((value) => value.toLowerCase()).join(' ').contains(query);
            return _RackSlot(
              rackId: rackId,
              level: level,
              position: position,
              positionCode: positionCode,
              pallets: query.isEmpty || visiblePositionMatches
                  ? pallets
                  : pallets.where((pallet) {
                      final values =
                          [
                                pallet['palletId'],
                                pallet['sku'],
                                pallet['productName'],
                                pallet['locationCode'],
                                pallet['rackId'],
                                pallet['position'],
                              ]
                              .map(
                                (value) =>
                                    value?.toString().toLowerCase() ?? '',
                              )
                              .join(' ');
                      return values.contains(query);
                    }).toList(),
              onDepletePallet: onDepletePallet,
              onAccept: onAccept,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _RackSlot extends StatelessWidget {
  const _RackSlot({
    required this.rackId,
    required this.level,
    required this.position,
    required this.positionCode,
    required this.pallets,
    required this.onDepletePallet,
    required this.onAccept,
  });

  final String rackId;
  final int level;
  final _RackPosition position;
  final String positionCode;
  final List<Map<String, dynamic>> pallets;
  final ValueChanged<Map<String, dynamic>> onDepletePallet;
  final Future<void> Function(
    Map<String, dynamic> pallet,
    String rackId,
    int level,
    String position,
  )
  onAccept;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Map<String, dynamic>>(
      onAcceptWithDetails: (details) {
        onAccept(details.data, rackId, level, position.code);
      },
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? Colors.black : Colors.black26,
              width: active ? 2 : 1,
            ),
          ),
          child: pallets.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      positionCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    const Text(
                      'Vacia',
                      style: TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  ],
                )
              : _RackSlotPallets(
                  key: ValueKey('pallets-$rackId-$level-${position.code}'),
                  positionCode: positionCode,
                  pallets: pallets,
                  onDepletePallet: onDepletePallet,
                ),
        );
      },
    );
  }
}

class _RackSlotPallets extends StatefulWidget {
  const _RackSlotPallets({
    super.key,
    required this.positionCode,
    required this.pallets,
    required this.onDepletePallet,
  });

  final String positionCode;
  final List<Map<String, dynamic>> pallets;
  final ValueChanged<Map<String, dynamic>> onDepletePallet;

  @override
  State<_RackSlotPallets> createState() => _RackSlotPalletsState();
}

class _RackSlotPalletsState extends State<_RackSlotPallets> {
  int _currentIndex = 0;

  @override
  void didUpdateWidget(covariant _RackSlotPallets oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pallets.isEmpty || _currentIndex >= widget.pallets.length) {
      _currentIndex = 0;
    }
  }

  void _showNextPallet() {
    if (widget.pallets.length < 2) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.pallets.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pallets.isEmpty) return const SizedBox.shrink();
    final safeIndex = _currentIndex.clamp(0, widget.pallets.length - 1);
    final pallet = widget.pallets[safeIndex];
    final hasMultiple = widget.pallets.length > 1;
    return _PalletLongPressDraggable(
      pallet: pallet,
      child: Semantics(
        button: hasMultiple,
        label:
            '${pallet['sku'] ?? ''}, ${_palletBoxCount(pallet)} cajas, '
            'pallet ${safeIndex + 1} de ${widget.pallets.length}',
        child: GestureDetector(
          onTap: hasMultiple ? _showNextPallet : null,
          onDoubleTap: () => widget.onDepletePallet(pallet),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.positionCode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (hasMultiple)
                      Text(
                        '${safeIndex + 1}/${widget.pallets.length}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  pallet['sku']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_palletBoxCount(pallet)} cajas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9),
                ),
                if (hasMultiple) ...[
                  const SizedBox(height: 2),
                  _PalletPageIndicator(
                    currentIndex: safeIndex,
                    total: widget.pallets.length,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PalletPageIndicator extends StatelessWidget {
  const _PalletPageIndicator({required this.currentIndex, required this.total});

  final int currentIndex;
  final int total;

  @override
  Widget build(BuildContext context) {
    const maxDots = 5;
    final dotCount = total.clamp(0, maxDots);
    final maxStart = total > maxDots ? total - maxDots : 0;
    final start = (currentIndex - 2).clamp(0, maxStart);
    return SizedBox(
      height: 7,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var offset = 0; offset < dotCount; offset++)
            SizedBox(
              width: 8,
              height: 7,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: start + offset == currentIndex ? 6 : 4,
                  height: start + offset == currentIndex ? 6 : 4,
                  decoration: BoxDecoration(
                    color: start + offset == currentIndex
                        ? Colors.black
                        : Colors.black26,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

int _palletBoxCount(Map<String, dynamic> pallet) {
  final value = pallet['boxes'];
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class _PalletLongPressDraggable extends StatelessWidget {
  const _PalletLongPressDraggable({required this.pallet, required this.child});

  final Map<String, dynamic> pallet;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<Map<String, dynamic>>(
      data: pallet,
      delay: const Duration(milliseconds: 450),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: const Offset(-70, -64),
        child: _PalletDragFeedback(pallet: pallet),
      ),
      childWhenDragging: child,
      child: child,
    );
  }
}

class _PalletDragFeedback extends StatelessWidget {
  const _PalletDragFeedback({required this.pallet});

  final Map<String, dynamic> pallet;

  @override
  Widget build(BuildContext context) {
    final sku = pallet['sku']?.toString() ?? '';
    final name = pallet['productName']?.toString() ?? 'Producto';
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sku,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
            Text(
              '${_palletBoxCount(pallet)} cajas',
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutsideRackTarget extends StatelessWidget {
  const _OutsideRackTarget({required this.onMoveOutside});

  final ValueChanged<Map<String, dynamic>> onMoveOutside;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Map<String, dynamic>>(
      onAcceptWithDetails: (details) => onMoveOutside(details.data),
      builder: (context, candidateData, rejectedData) {
        final dragging = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: dragging ? const Color(0xFFE8F0FE) : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: dragging ? Colors.black : Colors.black26,
              width: dragging ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.outbox_outlined,
                color: dragging ? Colors.black : Colors.black54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dragging
                      ? 'Suelta para sacar del rack'
                      : 'Soltar aqui para sacar del rack',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PendingPalletsPanel extends StatelessWidget {
  const _PendingPalletsPanel({
    required this.pallets,
    required this.query,
    required this.onAddPallet,
    required this.onDropOutside,
    required this.onDepletePallet,
    required this.onQueryChanged,
  });

  final List<Map<String, dynamic>> pallets;
  final String query;
  final VoidCallback onAddPallet;
  final ValueChanged<Map<String, dynamic>> onDropOutside;
  final ValueChanged<Map<String, dynamic>> onDepletePallet;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: TextField(
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              labelText: 'Buscar pallet por SKU o producto',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Pallets sin ubicacion: ${pallets.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.icon(
                onPressed: onAddPallet,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Dar entrada'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _OutsideRackTarget(onMoveOutside: onDropOutside),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: pallets.isEmpty
              ? const Center(child: Text('No hay pallets pendientes.'))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  itemCount: pallets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final pallet = pallets[index];
                    return SizedBox(
                      width: 210,
                      child: _PalletLongPressDraggable(
                        pallet: pallet,
                        child: GestureDetector(
                          onDoubleTap: () => onDepletePallet(pallet),
                          child: _PalletCard(pallet: pallet),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PalletCard extends StatelessWidget {
  const _PalletCard({required this.pallet});

  final Map<String, dynamic> pallet;

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final sku = pallet['sku']?.toString() ?? '';
    final name = pallet['productName']?.toString() ?? 'Producto';
    final boxes = _toInt(pallet['boxes']);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Text(
            sku,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Flexible(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text('$boxes cajas', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _RackPosition {
  const _RackPosition(this.code, this.label);

  final String code;
  final String label;
}
