import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
