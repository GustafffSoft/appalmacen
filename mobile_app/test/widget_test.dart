import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/pages/add_product_page.dart';
import 'package:mobile_app/pages/margin_calculator_page.dart';

void main() {
  testWidgets('Margin calculator renders the commercial MVP tool', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MarginCalculatorPage()));

    expect(find.text('Calculadora de Margen'), findsOneWidget);
    expect(find.text('Costo total'), findsOneWidget);
    expect(find.text('Precios sugeridos'), findsOneWidget);
  });

  testWidgets('Product deletion requires admin access and exact SKU', (
    WidgetTester tester,
  ) async {
    const product = <String, dynamic>{
      'sku': 'TEST-100',
      'name': 'Producto de prueba',
    };
    await tester.pumpWidget(
      const MaterialApp(
        home: AddProductPage(initialProduct: product, canDelete: true),
      ),
    );

    expect(find.byTooltip('Eliminar producto'), findsOneWidget);
    await tester.tap(find.byTooltip('Eliminar producto'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Esta accion es permanente. Solo se permitira si no quedan cajas ni pallets activos.',
      ),
      findsOneWidget,
    );
    final deleteButton = find.widgetWithText(FilledButton, 'Eliminar');
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'TEST-100');
    await tester.pump();

    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNotNull);
  });
}
