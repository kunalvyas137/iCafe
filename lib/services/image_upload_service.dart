import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

enum ImagePickerSource { gallery, camera, file }

class ImageUploadService {
  static final _storage = FirebaseStorage.instance;

  /// Pick an image and upload it to Firebase Storage.
  ///
  /// [source]:
  ///   - [ImagePickerSource.file]    — file picker (web-friendly)
  ///   - [ImagePickerSource.gallery] — native gallery (mobile / macOS)
  ///   - [ImagePickerSource.camera]  — camera (mobile only)
  ///
  /// Returns the public download URL, or null if the user cancelled / error.
  static Future<String?> pickAndUpload({
    required ImagePickerSource source,
    String folder = 'product_images',
  }) async {
    Uint8List? bytes;
    String extension = 'jpg';

    if (source == ImagePickerSource.file) {
      // FilePicker.pickFiles returns List<PlatformFile> (non-null, can be empty)
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return null;
      final file = files.first;
      bytes = await file.readAsBytes();
      extension = file.extension ?? 'jpg';
    } else {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source == ImagePickerSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked == null) return null;
      bytes = await picked.readAsBytes();
      final parts = picked.name.split('.');
      if (parts.length > 1) extension = parts.last.toLowerCase();
    }

    if (bytes.isEmpty) return null;
    return _upload(bytes, extension: extension, folder: folder);
  }

  static Future<String?> _upload(
    Uint8List bytes, {
    required String extension,
    required String folder,
  }) async {
    const uuid = Uuid();
    final filename = '${uuid.v4()}.$extension';
    final ref = _storage.ref().child('$folder/$filename');
    final metadata = SettableMetadata(
      contentType: _mimeType(extension),
      cacheControl: 'public, max-age=31536000',
    );
    final snapshot = await ref.putData(bytes, metadata);
    return await snapshot.ref.getDownloadURL();
  }

  /// Delete an image stored in Firebase Storage by its download URL.
  static Future<void> deleteByUrl(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (_) {}
  }

  static String _mimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  /// True when the device has a camera accessible via image_picker.
  static bool get hasCameraSupport =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
}
