import '../models/raw_material.dart';
import 'ai_inventory_service.dart';

/// Guesses which stocked material an invoice line refers to. Vendors write
/// "Amul Full Cream Milk 1L" where the till has "Milk", so an exact match is
/// tried first, then containment either way, then a shared-word overlap.
RawMaterial? matchMaterial(
  ParsedInvoiceLine line,
  Iterable<RawMaterial> materials,
) {
  final lineWords = _words(line.name);
  if (lineWords.isEmpty) return null;
  final lineText = lineWords.join(' ');

  RawMaterial? bestPartial;
  var bestOverlap = 0;

  for (final material in materials) {
    final materialWords = _words(material.name);
    if (materialWords.isEmpty) continue;
    final materialText = materialWords.join(' ');

    if (materialText == lineText) return material;

    if (lineText.contains(materialText) || materialText.contains(lineText)) {
      final overlap = materialWords.length + 100;
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestPartial = material;
      }
      continue;
    }

    final overlap = materialWords.where(lineWords.contains).length;
    if (overlap > bestOverlap) {
      bestOverlap = overlap;
      bestPartial = material;
    }
  }

  return bestOverlap > 0 ? bestPartial : null;
}

List<String> _words(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty && !_noise.contains(word))
    .toList();

const _noise = {
  'kg',
  'kgs',
  'g',
  'gm',
  'gms',
  'l',
  'ltr',
  'ltrs',
  'litre',
  'litres',
  'ml',
  'pc',
  'pcs',
  'pack',
  'packet',
  'box',
  'x',
};
