import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/utils/product_document_id.dart';

void main() {
  test('normal SKU keeps its existing Firestore document id', () {
    expect(productDocumentId(' 936833 '), '936833');
  });

  test('SKU with slash uses the backend-compatible encoded id', () {
    expect(productDocumentId('abc/123'), '__SKU_B64__QUJDLzEyMw');
  });
}
