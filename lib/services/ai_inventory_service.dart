import 'dart:convert';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class AiInvoiceException implements Exception {
  AiInvoiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ParsedInvoiceLine {
  const ParsedInvoiceLine({
    required this.name,
    required this.quantity,
    this.unit = '',
    this.unitPrice,
    this.type = 'raw_material',
  });

  final String name;
  final double quantity;
  final String unit;
  final double? unitPrice;
  final String type;
}

class AiInventoryService {
  /// Supplied at build time: `flutter run --dart-define=GEMINI_API_KEY=...`.
  static const String apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static bool get isConfigured => apiKey.isNotEmpty;

  static const String _prompt = '''
You are an expert OCR and inventory management assistant.
Extract all line items from this vendor purchase invoice/receipt.
For each item, provide the name, the quantity received, the unit of measure
(kg, g, l, ml, pcs), the unit price, and a classification type.
The "type" must be exactly "mrp" if the item is a finished good sold directly to customers (e.g. cans of soda, bottled water), or exactly "raw_material" if it is an ingredient used to prepare other items (e.g. coffee beans, sugar, milk).
Format the response strictly as a JSON array of objects with keys:
"name" (string), "quantity" (number), "unit" (string), "price" (number), "type" (string).
Do not include any other text or markdown block formatting.
''';

  /// Reads [bytes] with Gemini and returns the line items it found.
  /// Nothing is written to Firestore here — the caller reviews and matches the
  /// lines to raw materials first.
  static Future<List<ParsedInvoiceLine>> scanFile(
    Uint8List bytes,
    String mimeType,
  ) async {
    if (!isConfigured) {
      throw AiInvoiceException(
        'No Gemini API key in this build. Rebuild with '
        '--dart-define=GEMINI_API_KEY=<key> to use invoice scanning.',
      );
    }

    final model = GenerativeModel(
      model: 'gemini-flash-latest',
      apiKey: apiKey,
    );

    GenerateContentResponse? response;
    int retries = 3;
    while (retries > 0) {
      try {
        if (mimeType == 'application/pdf') {
          // Upload the PDF to the File API first
          final uri = Uri.parse("https://generativelanguage.googleapis.com/upload/v1beta/files?key=$apiKey");
          final request = http.Request('POST', uri);
          request.headers['X-Goog-Upload-Protocol'] = 'raw';
          request.headers['X-Goog-Upload-Header-Content-Type'] = mimeType;
          request.bodyBytes = bytes;
          
          final uploadResp = await request.send();
          final body = await uploadResp.stream.bytesToString();
          if (uploadResp.statusCode != 200) {
            throw AiInvoiceException('Failed to upload PDF to Gemini: $body');
          }
          
          final json = jsonDecode(body);
          final fileUri = Uri.parse(json['file']['uri'] as String);

          response = await model.generateContent([
            Content.multi([TextPart(_prompt), FilePart(fileUri)]),
          ]);
        } else {
          response = await model.generateContent([
            Content.multi([TextPart(_prompt), DataPart(mimeType, bytes)]),
          ]);
        }
        break; // Success, exit retry loop
      } catch (e) {
        if (e.toString().contains('503') && retries > 1) {
          retries--;
          await Future.delayed(const Duration(seconds: 2));
          continue; // Retry on 503
        }
        throw AiInvoiceException('Could not reach Gemini: $e');
      }
    }

    final text = response?.text;
    if (text == null || text.trim().isEmpty) {
      throw AiInvoiceException('Gemini returned an empty response.');
    }
    return parseInvoiceResponse(text);
  }

  /// Parses the model's reply. Gemini often wraps JSON in a ```json fence or
  /// an object such as `{"items": [...]}`, and returns numbers as strings with
  /// units attached, so all of that is tolerated here.
  static List<ParsedInvoiceLine> parseInvoiceResponse(String response) {
    final json = _decode(_stripFences(response));

    final List<dynamic> rawLines;
    if (json is List) {
      rawLines = json;
    } else if (json is Map<String, dynamic>) {
      final list = json.values.firstWhere(
        (value) => value is List,
        orElse: () => null,
      );
      if (list is! List) {
        throw AiInvoiceException('No invoice items found in the response.');
      }
      rawLines = list;
    } else {
      throw AiInvoiceException('No invoice items found in the response.');
    }

    final lines = <ParsedInvoiceLine>[];
    for (final raw in rawLines) {
      if (raw is! Map) continue;
      final name = (raw['name'] ?? raw['item'] ?? raw['description'] ?? '')
          .toString()
          .trim();
      if (name.isEmpty) continue;

      final quantity = _toDouble(raw['quantity'] ?? raw['qty']);
      lines.add(
        ParsedInvoiceLine(
          name: name,
          quantity: quantity == null || quantity <= 0 ? 1 : quantity,
          unit: (raw['unit'] ?? raw['uom'] ?? '').toString().trim(),
          unitPrice: _toDouble(raw['price'] ?? raw['unitPrice'] ?? raw['rate']),
          type: (raw['type'] ?? 'raw_material').toString().trim().toLowerCase() == 'mrp' ? 'mrp' : 'raw_material',
        ),
      );
    }

    if (lines.isEmpty) {
      throw AiInvoiceException('No invoice items found in the response.');
    }
    return lines;
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      // Trailing prose is common; fall back to the outermost bracketed span.
      final start = text.indexOf('[');
      final end = text.lastIndexOf(']');
      if (start != -1 && end > start) {
        try {
          return jsonDecode(text.substring(start, end + 1));
        } on FormatException {
          // fall through
        }
      }
      throw AiInvoiceException('Gemini did not return readable JSON.');
    }
  }

  static String _stripFences(String text) {
    var cleaned = text.trim();
    if (!cleaned.startsWith('```')) return cleaned;
    cleaned = cleaned.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    final end = cleaned.lastIndexOf('```');
    if (end != -1) cleaned = cleaned.substring(0, end);
    return cleaned.trim();
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final match = RegExp(
        r'-?\d+(\.\d+)?',
      ).firstMatch(value.replaceAll(',', ''));
      if (match != null) return double.tryParse(match.group(0)!);
    }
    return null;
  }

  static String _mimeTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
}
