import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class FirebaseService {
  FirebaseService({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOrders() {
    return _firestore
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchProducts() {
    return _firestore.collection('products').orderBy('name').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchProspects() {
    return _firestore
        .collection('prospects')
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSuppliers() {
    return _firestore
        .collection('suppliers')
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSupplierPrices() {
    return _firestore
        .collection('supplier_prices')
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSalesMessages() {
    return _firestore
        .collection('sales_messages')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrder(String orderId) {
    return _firestore.collection('orders').doc(orderId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPalletPlan(
    String orderId,
  ) {
    return _firestore.collection('pallet_plans').doc(orderId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchWarehousePallets() {
    return _firestore
        .collection('warehouse_pallets')
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchWarehouseRacks() {
    return _firestore.collection('warehouse_racks').orderBy('name').snapshots();
  }

  Future<String> createOrder({
    required List<Map<String, dynamic>> items,
    Map<String, dynamic>? invoiceData,
  }) async {
    final docRef = _firestore.collection('orders').doc();
    final payload = <String, dynamic>{
      'status': 'new',
      'items': items,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (invoiceData != null) {
      payload.addAll(invoiceData);
    }
    await docRef.set(payload);
    return docRef.id;
  }

  Future<void> createProduct({
    required String sku,
    required String name,
    String? secondName,
    required String category,
    required double cost,
    required double salePrice,
    required int unitsPerCase,
    required String productStatus,
    required double lengthIn,
    required double widthIn,
    required double heightIn,
    required double weightKg,
  }) async {
    final docRef = _firestore.collection('products').doc(sku);
    final existing = await docRef.get();
    if (existing.exists) {
      throw Exception(
        'El SKU $sku ya existe. Usa otro SKU o edita el producto.',
      );
    }

    await docRef.set({
      'sku': sku,
      'name': name,
      'secondName': secondName,
      'category': category,
      'cost': cost,
      'salePrice': salePrice,
      'stockQty': 0,
      'unitsPerCase': unitsPerCase,
      'productStatus': productStatus,
      'lengthCm': lengthIn,
      'widthCm': widthIn,
      'heightCm': heightIn,
      'weightKg': weightKg,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> createMinimalProduct({
    required String name,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('El nombre del producto es obligatorio.');
    }

    final generatedId = _firestore.collection('products').doc().id;
    final sku = 'MAN-${generatedId.substring(0, 10).toUpperCase()}';
    final product = <String, dynamic>{
      'sku': sku,
      'name': cleanName,
      'secondName': null,
      'category': 'Sin categoria',
      'cost': 0.0,
      'salePrice': 0.0,
      'stockQty': 0,
      'unitsPerCase': 1,
      'productStatus': 'activo',
      'lengthCm': 0.0,
      'widthCm': 0.0,
      'heightCm': 0.0,
      'weightKg': 0.0,
      'pendingDetails': true,
      'creationSource': 'warehouse_pallet_entry',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _firestore.collection('products').doc(sku).set(product);
    return {'sku': sku, 'name': cleanName};
  }

  Future<void> updateProduct({
    required String sku,
    required String name,
    String? secondName,
    required String category,
    required double cost,
    required double salePrice,
    required int unitsPerCase,
    required String productStatus,
    required double lengthIn,
    required double widthIn,
    required double heightIn,
    required double weightKg,
  }) async {
    await _firestore.collection('products').doc(sku).set({
      'sku': sku,
      'name': name,
      'secondName': secondName,
      'category': category,
      'cost': cost,
      'salePrice': salePrice,
      'unitsPerCase': unitsPerCase,
      'productStatus': productStatus,
      'lengthCm': lengthIn,
      'widthCm': widthIn,
      'heightCm': heightIn,
      'weightKg': weightKg,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveWarehousePalletLocation({
    required String palletId,
    required String sku,
    required String productName,
    required int boxes,
    required String rackId,
    required int level,
    required String position,
  }) async {
    await _firestore.collection('warehouse_pallets').doc(palletId).set({
      'palletId': palletId,
      'sku': sku,
      'productName': productName,
      'boxes': boxes,
      'rackId': rackId,
      'level': level,
      'position': position,
      'locationCode': '$rackId-L$level-$position',
      'status': 'ubicado',
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, int>> consumeFirstFloorLocation({
    required String rackId,
    required String position,
    required String excludingPalletId,
  }) async {
    final locationCode = '$rackId-L1-$position';
    final snapshot = await _firestore
        .collection('warehouse_pallets')
        .where('locationCode', isEqualTo: locationCode)
        .get();
    final pallets = snapshot.docs.where((doc) {
      if (doc.id == excludingPalletId) return false;
      final boxes = (doc.data()['boxes'] as num?)?.toInt() ?? 0;
      return boxes > 0;
    }).toList();
    if (pallets.isEmpty) return {'pallets': 0, 'boxes': 0};

    final boxesBySku = <String, int>{};
    for (final doc in pallets) {
      final data = doc.data();
      final sku = data['sku']?.toString() ?? '';
      final boxes = (data['boxes'] as num?)?.toInt() ?? 0;
      if (sku.isNotEmpty && boxes > 0) {
        boxesBySku.update(sku, (value) => value + boxes, ifAbsent: () => boxes);
      }
    }

    await _firestore.runTransaction((transaction) async {
      final productSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final sku in boxesBySku.keys) {
        final ref = _firestore.collection('products').doc(sku);
        productSnapshots[sku] = await transaction.get(ref);
      }
      for (final entry in boxesBySku.entries) {
        final ref = _firestore.collection('products').doc(entry.key);
        final current =
            (productSnapshots[entry.key]?.data()?['stockQty'] as num?)
                ?.toInt() ??
            0;
        transaction.set(ref, {
          'stockQty': (current - entry.value).clamp(0, 1 << 31),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      for (final doc in pallets) {
        transaction.set(doc.reference, {
          'previousBoxes': doc.data()['boxes'],
          'boxes': 0,
          'previousLocationCode': locationCode,
          'rackId': '',
          'level': 0,
          'position': '',
          'locationCode': '',
          'status': 'agotado',
          'depletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
    return {
      'pallets': pallets.length,
      'boxes': boxesBySku.values.fold(0, (total, boxes) => total + boxes),
    };
  }

  Future<String> createWarehousePalletEntry({
    required String sku,
    required String productName,
    required int boxes,
    required XFile photo,
  }) async {
    final palletId = 'PAL-${DateTime.now().millisecondsSinceEpoch}';
    final filePath = 'warehouse_pallets/$palletId/original.jpg';
    final palletRef = _firestore.collection('warehouse_pallets').doc(palletId);
    final batch = _firestore.batch();
    batch.set(palletRef, {
      'palletId': palletId,
      'sku': sku,
      'productName': productName,
      'boxes': boxes,
      'photoPath': filePath,
      'photoUrl': '',
      'photoUrls': <String>[],
      'photoUploadStatus': 'pending',
      'palletName': 'Pallet $sku',
      'rackId': '',
      'level': 0,
      'position': '',
      'locationCode': '',
      'status': 'sin_ubicacion',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_firestore.collection('products').doc(sku), {
      'stockQty': FieldValue.increment(boxes),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit().timeout(const Duration(seconds: 20));

    unawaited(
      _uploadWarehousePalletPhoto(
        palletId: palletId,
        filePath: filePath,
        photo: photo,
      ),
    );

    return palletId;
  }

  Future<void> _uploadWarehousePalletPhoto({
    required String palletId,
    required String filePath,
    required XFile photo,
  }) async {
    final palletRef = _firestore.collection('warehouse_pallets').doc(palletId);
    final ref = _storage.ref(filePath);
    try {
      await _uploadXFile(ref, photo, contentType: 'image/jpeg');
      final photoUrl = await _getDownloadUrlWithRetry(ref);
      await palletRef.set({
        'photoUrl': photoUrl,
        'photoUrls': FieldValue.arrayUnion([photoUrl]),
        'photoUploadStatus': 'complete',
        'photoUploadError': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      await palletRef.set({
        'photoUploadStatus': 'failed',
        'photoUploadError': error.toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> updateWarehousePalletDetails({
    required String palletId,
    required String palletName,
  }) async {
    final palletRef = _firestore.collection('warehouse_pallets').doc(palletId);
    await palletRef.set({
      'palletName': palletName.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<int> depleteWarehousePallet(String palletId) async {
    final palletRef = _firestore.collection('warehouse_pallets').doc(palletId);
    return _firestore.runTransaction((transaction) async {
      final palletSnapshot = await transaction.get(palletRef);
      if (!palletSnapshot.exists) throw Exception('El pallet no existe.');
      final data = palletSnapshot.data()!;
      final boxes = (data['boxes'] as num?)?.toInt() ?? 0;
      final sku = data['sku']?.toString() ?? '';
      if (boxes <= 0 || sku.isEmpty) return 0;

      final productRef = _firestore.collection('products').doc(sku);
      final productSnapshot = await transaction.get(productRef);
      final currentStock =
          (productSnapshot.data()?['stockQty'] as num?)?.toInt() ?? 0;
      transaction.set(productRef, {
        'stockQty': (currentStock - boxes).clamp(0, 1 << 31),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.set(palletRef, {
        'previousBoxes': boxes,
        'boxes': 0,
        'previousRackId': data['rackId'] ?? '',
        'previousLevel': data['level'] ?? 0,
        'previousPosition': data['position'] ?? '',
        'previousLocationCode': data['locationCode'] ?? '',
        'rackId': '',
        'level': 0,
        'position': '',
        'locationCode': '',
        'status': 'agotado',
        'depletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return boxes;
    });
  }

  Future<List<String>> addWarehousePalletImages({
    required String palletId,
    required List<XFile> images,
  }) async {
    final urls = <String>[];
    for (var index = 0; index < images.length; index++) {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final filePath =
          'warehouse_pallets/$palletId/gallery/${stamp}_$index.jpg';
      final ref = _storage.ref(filePath);
      await _uploadXFile(ref, images[index], contentType: 'image/jpeg');
      urls.add(await _getDownloadUrlWithRetry(ref));
    }
    if (urls.isNotEmpty) {
      await _firestore.collection('warehouse_pallets').doc(palletId).set({
        'photoUrls': FieldValue.arrayUnion(urls),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    return urls;
  }

  Future<void> clearWarehousePalletLocation(String palletId) async {
    await _firestore.collection('warehouse_pallets').doc(palletId).set({
      'rackId': '',
      'level': 0,
      'position': '',
      'locationCode': '',
      'status': 'sin_ubicacion',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveWarehouseRack({
    required String rackId,
    required String name,
    required int levels,
    required int positionsPerLevel,
    required int rackNumber,
  }) async {
    await _firestore.collection('warehouse_racks').doc(rackId).set({
      'rackId': rackId,
      'name': name,
      'rackNumber': rackNumber,
      'levels': levels,
      'positionsPerLevel': positionsPerLevel,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteWarehouseRack(String rackId) async {
    final pallets = await _firestore
        .collection('warehouse_pallets')
        .where('rackId', isEqualTo: rackId)
        .get();
    final batch = _firestore.batch();
    for (final doc in pallets.docs) {
      batch.set(doc.reference, {
        'rackId': '',
        'level': 0,
        'position': '',
        'locationCode': '',
        'status': 'sin_ubicacion',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    batch.delete(_firestore.collection('warehouse_racks').doc(rackId));
    await batch.commit();
  }

  Future<String> saveProspect({
    String? prospectId,
    required String businessName,
    required String businessType,
    required String phone,
    required String email,
    required String address,
    required String area,
    required List<String> likelyProducts,
    required String status,
    required String notes,
  }) async {
    final docRef = prospectId == null || prospectId.isEmpty
        ? _firestore.collection('prospects').doc()
        : _firestore.collection('prospects').doc(prospectId);

    await docRef.set({
      'businessName': businessName,
      'businessType': businessType,
      'phone': phone,
      'email': email,
      'address': address,
      'area': area,
      'likelyProducts': likelyProducts,
      'status': status,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      if (prospectId == null || prospectId.isEmpty)
        'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  Future<String> saveSupplier({
    String? supplierId,
    required String name,
    required String contact,
    required String phone,
    required String website,
    required String productFocus,
    required String paymentTerms,
    required String notes,
  }) async {
    final docRef = supplierId == null || supplierId.isEmpty
        ? _firestore.collection('suppliers').doc()
        : _firestore.collection('suppliers').doc(supplierId);

    await docRef.set({
      'name': name,
      'contact': contact,
      'phone': phone,
      'website': website,
      'productFocus': productFocus,
      'paymentTerms': paymentTerms,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      if (supplierId == null || supplierId.isEmpty)
        'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  Future<String> saveSupplierPrice({
    String? supplierPriceId,
    required String productSku,
    required String productName,
    required String supplierId,
    required String supplierName,
    required double caseCost,
    required double shippingCost,
    required int unitsPerCase,
    required int minimumOrderQty,
    required String sourceUrl,
    required String notes,
  }) async {
    final docRef = supplierPriceId == null || supplierPriceId.isEmpty
        ? _firestore.collection('supplier_prices').doc()
        : _firestore.collection('supplier_prices').doc(supplierPriceId);

    final totalCost = caseCost + shippingCost;
    final unitCost = unitsPerCase <= 0 ? 0 : totalCost / unitsPerCase;

    await docRef.set({
      'productSku': productSku,
      'productName': productName,
      'supplierId': supplierId,
      'supplierName': supplierName,
      'caseCost': caseCost,
      'shippingCost': shippingCost,
      'totalCost': totalCost,
      'unitsPerCase': unitsPerCase,
      'unitCost': unitCost,
      'minimumOrderQty': minimumOrderQty,
      'sourceUrl': sourceUrl,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
      if (supplierPriceId == null || supplierPriceId.isEmpty)
        'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  Future<String> saveSalesMessage({
    required String prospectId,
    required String prospectName,
    required String prospectType,
    required List<String> productSkus,
    required List<String> productNames,
    required String channel,
    required String language,
    required String message,
  }) async {
    final docRef = _firestore.collection('sales_messages').doc();

    await docRef.set({
      'prospectId': prospectId,
      'prospectName': prospectName,
      'prospectType': prospectType,
      'productSkus': productSkus,
      'productNames': productNames,
      'channel': channel,
      'language': language,
      'message': message,
      'status': 'draft',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  Future<void> updateSalesMessage({
    required String messageId,
    required String status,
    required String followUpDate,
    required String followUpNotes,
  }) async {
    await _firestore.collection('sales_messages').doc(messageId).set({
      'status': status,
      'followUpDate': followUpDate,
      'followUpNotes': followUpNotes,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> _getDownloadUrlWithRetry(Reference ref) async {
    FirebaseException? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await ref.getDownloadURL().timeout(const Duration(seconds: 15));
      } on FirebaseException catch (error) {
        lastError = error;
        if (error.code != 'object-not-found' || attempt == 3) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    throw lastError ?? Exception('No se pudo obtener download URL');
  }

  Future<void> _uploadXFile(
    Reference ref,
    XFile file, {
    required String contentType,
  }) async {
    final metadata = SettableMetadata(contentType: contentType);
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      await ref.putData(bytes, metadata).timeout(const Duration(seconds: 45));
      return;
    }

    await ref
        .putFile(File(file.path), metadata)
        .timeout(const Duration(seconds: 45));
  }

  Future<List<Map<String, String>>> uploadInvoicePages({
    required String invoiceNumber,
    required List<XFile> files,
  }) async {
    final uploaded = <Map<String, String>>[];
    for (var index = 0; index < files.length; index++) {
      final pageNo = index + 1;
      final filePath = 'invoices/$invoiceNumber/page_$pageNo.jpg';
      final ref = _storage.ref(filePath);
      await _uploadXFile(ref, files[index], contentType: 'image/jpeg');
      final downloadUrl = await _getDownloadUrlWithRetry(ref);
      uploaded.add({'imagePath': filePath, 'imageUrl': downloadUrl});
    }
    return uploaded;
  }

  Future<List<Map<String, String>>> uploadProductCatalogImages({
    required String batchId,
    required List<XFile> files,
  }) async {
    final uploaded = <Map<String, String>>[];
    for (var index = 0; index < files.length; index++) {
      final imageNo = index + 1;
      final filePath = 'product_scans/$batchId/image_$imageNo.jpg';
      final ref = _storage.ref(filePath);
      await _uploadXFile(ref, files[index], contentType: 'image/jpeg');
      final downloadUrl = await _getDownloadUrlWithRetry(ref);
      uploaded.add({'imagePath': filePath, 'imageUrl': downloadUrl});
    }
    return uploaded;
  }

  Future<Map<String, String>> uploadOrderImage({
    required String orderId,
    required XFile file,
  }) async {
    final filePath = 'orders/$orderId/original.jpg';
    final ref = _storage.ref(filePath);

    await _uploadXFile(ref, file, contentType: 'image/jpeg');

    final downloadUrl = await _getDownloadUrlWithRetry(ref);

    await _firestore.collection('orders').doc(orderId).set({
      'status': 'uploaded',
      'imagePath': filePath,
      'imageUrl': downloadUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return {'imagePath': filePath, 'imageUrl': downloadUrl};
  }

  Future<void> updateOrderStatus(
    String orderId,
    String status, {
    Map<String, dynamic>? extra,
  }) async {
    final payload = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (extra != null) {
      payload.addAll(extra);
    }

    await _firestore
        .collection('orders')
        .doc(orderId)
        .set(payload, SetOptions(merge: true));
  }

  Future<void> savePalletPlan(
    String orderId,
    Map<String, dynamic> palletPayload,
  ) async {
    await _firestore.collection('pallet_plans').doc(orderId).set({
      ...palletPayload,
      'orderId': orderId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
