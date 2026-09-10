import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

class AiInventoryService {
  // TODO: Replace with secure storage or environment variable
  static const String _apiKey = 'REPLACE_WITH_YOUR_GEMINI_API_KEY';

  static Future<void> scanInvoice(XFile imageFile) async {
    final model = GenerativeModel(
      model: 'gemini-1.5-flash-latest',
      apiKey: _apiKey,
    );

    final bytes = await imageFile.readAsBytes();
    final prompt = TextPart('''
You are an expert OCR and inventory management assistant.
Extract all line items from this vendor purchase invoice/receipt.
For each item, provide the name, quantity, and unit price.
Format the response strictly as a JSON array of objects with keys: "name", "quantity" (as number), "price" (as number).
Do not include any other text or markdown block formatting.
''');
    final imageParts = [DataPart('image/jpeg', bytes)];

    try {
      final response = await model.generateContent([
        Content.multi([prompt, ...imageParts]),
      ]);
      print(response.text);
      // TODO: Parse JSON and merge into local database state
    } catch (e) {
      print('Error parsing invoice: $e');
    }
  }
}
