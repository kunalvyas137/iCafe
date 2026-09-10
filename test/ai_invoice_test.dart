import 'package:flutter_test/flutter_test.dart';
import 'package:icafe/models/raw_material.dart';
import 'package:icafe/services/ai_inventory_service.dart';
import 'package:icafe/services/invoice_matcher.dart';

RawMaterial _material(String name, {String unit = 'kg'}) => RawMaterial(
  id: name.toLowerCase(),
  name: name,
  unit: unit,
  currentStock: 0,
  reorderLevel: 0,
);

void main() {
  group('parsing the model reply', () {
    test('a plain JSON array is read line by line', () {
      final lines = AiInventoryService.parseInvoiceResponse('''
[{"name": "Milk", "quantity": 12, "unit": "l", "price": 62.5}]
''');

      expect(lines, hasLength(1));
      expect(lines.first.name, 'Milk');
      expect(lines.first.quantity, 12);
      expect(lines.first.unit, 'l');
      expect(lines.first.unitPrice, 62.5);
    });

    test('a markdown code fence is stripped', () {
      final lines = AiInventoryService.parseInvoiceResponse('''
```json
[{"name": "Coffee beans", "quantity": 2, "unit": "kg"}]
```
''');

      expect(lines.single.name, 'Coffee beans');
      expect(lines.single.unitPrice, isNull);
    });

    test('items wrapped in an object are found', () {
      final lines = AiInventoryService.parseInvoiceResponse(
        '{"invoice_number": "A-1", "items": [{"name": "Sugar", "qty": 5}]}',
      );

      expect(lines.single.name, 'Sugar');
      expect(lines.single.quantity, 5);
    });

    test('numbers written as strings with units are recovered', () {
      final lines = AiInventoryService.parseInvoiceResponse(
        '[{"name": "Tea", "quantity": "2.5 kg", "price": "1,250.00"}]',
      );

      expect(lines.single.quantity, 2.5);
      expect(lines.single.unitPrice, 1250);
    });

    test('trailing prose around the array does not break parsing', () {
      final lines = AiInventoryService.parseInvoiceResponse(
        'Here you go:\n[{"name": "Butter", "quantity": 3}]\nHope that helps!',
      );

      expect(lines.single.name, 'Butter');
    });

    test('a missing quantity falls back to one unit', () {
      final lines = AiInventoryService.parseInvoiceResponse(
        '[{"name": "Paper cups"}]',
      );

      expect(lines.single.quantity, 1);
    });

    test('unusable replies raise instead of silently importing nothing', () {
      expect(
        () => AiInventoryService.parseInvoiceResponse('I cannot read this.'),
        throwsA(isA<AiInvoiceException>()),
      );
      expect(
        () => AiInventoryService.parseInvoiceResponse('[]'),
        throwsA(isA<AiInvoiceException>()),
      );
      expect(
        () => AiInventoryService.parseInvoiceResponse('[{"quantity": 3}]'),
        throwsA(isA<AiInvoiceException>()),
      );
    });
  });

  group('matching lines to stocked materials', () {
    final materials = [
      _material('Milk', unit: 'l'),
      _material('Coffee Beans'),
      _material('Sugar'),
    ];

    ParsedInvoiceLine line(String name) =>
        ParsedInvoiceLine(name: name, quantity: 1);

    test('an exact name wins regardless of case', () {
      expect(matchMaterial(line('sugar'), materials)?.id, 'sugar');
    });

    test('a vendor description containing the material matches it', () {
      expect(
        matchMaterial(line('Amul Full Cream Milk 1L'), materials)?.id,
        'milk',
      );
    });

    test('packaging words alone are not a match', () {
      expect(matchMaterial(line('1 kg pack'), materials), isNull);
    });

    test('unknown items stay unmatched so they are created explicitly', () {
      expect(matchMaterial(line('Paper napkins'), materials), isNull);
    });

    test('partial word overlap still finds the material', () {
      expect(
        matchMaterial(line('Roasted coffee arabica'), materials)?.id,
        'coffee beans',
      );
    });
  });
}
