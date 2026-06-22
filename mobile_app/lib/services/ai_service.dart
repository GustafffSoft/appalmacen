import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> generateSalesMessage({
    required Map<String, dynamic> prospect,
    required List<Map<String, dynamic>> products,
    required String channel,
    required String language,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/api/v1/ai/sales-message');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'prospectName': prospect['businessName']?.toString() ?? 'Cliente',
        'prospectType': prospect['businessType']?.toString() ?? '',
        'area': prospect['area']?.toString() ?? '',
        'notes': prospect['notes']?.toString() ?? '',
        'likelyProducts': prospect['likelyProducts'] ?? <String>[],
        'channel': channel,
        'language': language,
        'products': products
            .map((product) {
              return {
                'sku': product['sku']?.toString() ?? '',
                'name': product['name']?.toString() ?? 'Producto',
                'category': product['category']?.toString() ?? '',
                'salePrice': _toDouble(product['salePrice']),
                'marginPct': _toDouble(product['marginPct']),
              };
            })
            .toList(growable: false),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'AI backend error (${response.statusCode}): ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['message']?.toString() ?? '';
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
