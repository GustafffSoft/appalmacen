import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'backend_api_client.dart';
import 'firebase_service.dart';

class OrderService {
  OrderService(
    this._firebaseService, {
    http.Client? client,
    BackendApiClient? apiClient,
  }) : _apiClient = apiClient ?? BackendApiClient(client: client);

  final FirebaseService _firebaseService;
  final BackendApiClient _apiClient;

  Future<String> createOrder({
    required List<Map<String, dynamic>> items,
    Map<String, dynamic>? invoiceData,
  }) {
    return _firebaseService.createOrder(items: items, invoiceData: invoiceData);
  }

  Future<Map<String, dynamic>> scanInvoicePages({
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/api/v1/invoices/scan-pages');
    final response = await _apiClient.postJson(uri, payload: payload);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'No se pudo escanear invoice: ${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> scanProductCatalog({
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/api/v1/products/scan-catalog');
    final response = await _apiClient.postJson(uri, payload: payload);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'No se pudieron escanear productos: '
        '${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registerInvoice({
    required Map<String, dynamic> payload,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/api/v1/invoices/register');
    final response = await _apiClient.postJson(uri, payload: payload);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'No se pudo registrar invoice: ${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> seedProductsCatalog() async {
    final uri = Uri.parse('$backendBaseUrl/api/v1/products/seed');
    final response = await _apiClient.postJson(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'No se pudo sembrar catalogo: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> processOrder({
    required String orderId,
    String? imageUrl,
    double allowOverhangCm = 0,
    Map<String, dynamic>? pallet,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/api/v1/orders/$orderId/process');

    final payload = <String, dynamic>{
      'allowOverhangCm': allowOverhangCm,
      'pallet':
          pallet ??
          {
            'lengthCm': 48,
            'widthCm': 40,
            'maxHeightCm': 84,
            'maxWeightKg': 900,
          },
    };

    final cleanImageUrl = imageUrl?.trim();
    if (cleanImageUrl != null && cleanImageUrl.isNotEmpty) {
      payload['imageUrl'] = cleanImageUrl;
    }

    final response = await _apiClient.postJson(uri, payload: payload);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Backend error (${response.statusCode}): ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    await _firebaseService.savePalletPlan(orderId, body);
    await _firebaseService.updateOrderStatus(orderId, 'processed');
    return body;
  }
}
