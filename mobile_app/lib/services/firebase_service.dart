import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class FirebaseService {
  FirebaseService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOrders() {
    return _firestore.collection('orders').orderBy('createdAt', descending: true).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchProducts() {
    return _firestore.collection('products').orderBy('name').snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrder(String orderId) {
    return _firestore.collection('orders').doc(orderId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPalletPlan(String orderId) {
    return _firestore.collection('pallet_plans').doc(orderId).snapshots();
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
    required double lengthIn,
    required double widthIn,
    required double heightIn,
    required double weightKg,
  }) async {
    final docRef = _firestore.collection('products').doc(sku);
    final existing = await docRef.get();
    if (existing.exists) {
      throw Exception('El SKU $sku ya existe. Usa otro SKU o edita el producto.');
    }

    await docRef.set({
      'sku': sku,
      'name': name,
      'secondName': secondName,
      'lengthCm': lengthIn,
      'widthCm': widthIn,
      'heightCm': heightIn,
      'weightKg': weightKg,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateProduct({
    required String sku,
    required String name,
    String? secondName,
    required double lengthIn,
    required double widthIn,
    required double heightIn,
    required double weightKg,
  }) async {
    await _firestore.collection('products').doc(sku).set({
      'sku': sku,
      'name': name,
      'secondName': secondName,
      'lengthCm': lengthIn,
      'widthCm': widthIn,
      'heightCm': heightIn,
      'weightKg': weightKg,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> _getDownloadUrlWithRetry(Reference ref) async {
    FirebaseException? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await ref.getDownloadURL();
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
      await ref.putData(bytes, metadata);
      return;
    }

    await ref.putFile(File(file.path), metadata);
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
      await _uploadXFile(
        ref,
        files[index],
        contentType: 'image/jpeg',
      );
      final downloadUrl = await _getDownloadUrlWithRetry(ref);
      uploaded.add({
        'imagePath': filePath,
        'imageUrl': downloadUrl,
      });
    }
    return uploaded;
  }

  Future<Map<String, String>> uploadOrderImage({
    required String orderId,
    required XFile file,
  }) async {
    final filePath = 'orders/$orderId/original.jpg';
    final ref = _storage.ref(filePath);

    await _uploadXFile(
      ref,
      file,
      contentType: 'image/jpeg',
    );

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

    await _firestore.collection('orders').doc(orderId).set(
          payload,
          SetOptions(merge: true),
        );
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
