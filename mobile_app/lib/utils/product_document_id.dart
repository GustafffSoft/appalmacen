import 'dart:convert';

String productDocumentId(String sku) {
  const prefix = '__SKU_B64__';
  final cleanSku = sku.trim().toUpperCase();
  if (!cleanSku.contains('/') && !cleanSku.startsWith(prefix)) {
    return cleanSku;
  }
  final encoded = base64Url.encode(utf8.encode(cleanSku)).replaceAll('=', '');
  return '$prefix$encoded';
}
