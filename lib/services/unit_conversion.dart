// Vendors bill in whatever unit suits them — 1000 ml of milk for a material
// stocked in litres — so a delivered quantity has to be converted into the
// material's own unit before it touches stock.

/// How many base units (g, ml, or pieces) one of the named unit is worth.
const _factors = <String, ({String dimension, double factor})>{
  'g': (dimension: 'mass', factor: 1),
  'gm': (dimension: 'mass', factor: 1),
  'gms': (dimension: 'mass', factor: 1),
  'gram': (dimension: 'mass', factor: 1),
  'grams': (dimension: 'mass', factor: 1),
  'kg': (dimension: 'mass', factor: 1000),
  'kgs': (dimension: 'mass', factor: 1000),
  'kilo': (dimension: 'mass', factor: 1000),
  'kilos': (dimension: 'mass', factor: 1000),
  'kilogram': (dimension: 'mass', factor: 1000),
  'kilograms': (dimension: 'mass', factor: 1000),
  'ml': (dimension: 'volume', factor: 1),
  'millilitre': (dimension: 'volume', factor: 1),
  'millilitres': (dimension: 'volume', factor: 1),
  'milliliter': (dimension: 'volume', factor: 1),
  'milliliters': (dimension: 'volume', factor: 1),
  'l': (dimension: 'volume', factor: 1000),
  'lt': (dimension: 'volume', factor: 1000),
  'ltr': (dimension: 'volume', factor: 1000),
  'ltrs': (dimension: 'volume', factor: 1000),
  'litre': (dimension: 'volume', factor: 1000),
  'litres': (dimension: 'volume', factor: 1000),
  'liter': (dimension: 'volume', factor: 1000),
  'liters': (dimension: 'volume', factor: 1000),
  'pc': (dimension: 'count', factor: 1),
  'pcs': (dimension: 'count', factor: 1),
  'piece': (dimension: 'count', factor: 1),
  'pieces': (dimension: 'count', factor: 1),
  'nos': (dimension: 'count', factor: 1),
  'no': (dimension: 'count', factor: 1),
  'unit': (dimension: 'count', factor: 1),
  'units': (dimension: 'count', factor: 1),
  'ea': (dimension: 'count', factor: 1),
  'each': (dimension: 'count', factor: 1),
};

String _normalise(String unit) => unit.trim().toLowerCase().replaceAll('.', '');

/// Converts [quantity] from [fromUnit] into [toUnit], or returns null when
/// the two cannot be compared — an unknown unit, or mass against volume.
/// Identical unit strings always convert, so custom units such as `crate`
/// keep working.
double? convertQuantity(double quantity, String fromUnit, String toUnit) {
  final from = _normalise(fromUnit);
  final to = _normalise(toUnit);
  if (from == to) return quantity;
  if (from.isEmpty || to.isEmpty) return null;

  final fromSpec = _factors[from];
  final toSpec = _factors[to];
  if (fromSpec == null || toSpec == null) return null;
  if (fromSpec.dimension != toSpec.dimension) return null;

  return quantity * fromSpec.factor / toSpec.factor;
}

/// Whether a quantity written in [fromUnit] can be booked against a material
/// stocked in [toUnit].
bool unitsAreCompatible(String fromUnit, String toUnit) =>
    convertQuantity(1, fromUnit, toUnit) != null;
