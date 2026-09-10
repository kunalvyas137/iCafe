import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/store_settings.dart';

/// Reads and writes the single `settings/store` document.
class SettingsService {
  static const String collection = 'settings';
  static const String storeDocId = 'store';

  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection(collection).doc(storeDocId);

  static Stream<StoreSettings> watch() {
    return _doc.snapshots().map((snap) => StoreSettings.fromMap(snap.data()));
  }

  static Future<StoreSettings> load() async {
    final snap = await _doc.get();
    return StoreSettings.fromMap(snap.data());
  }

  static Future<void> save(StoreSettings settings) {
    return _doc.set(settings.toMap(), SetOptions(merge: true));
  }
}
