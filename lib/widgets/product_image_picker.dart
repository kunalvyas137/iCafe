import 'package:flutter/material.dart';
import '../services/image_upload_service.dart';

/// Widget embedded in the Add/Edit Product dialog.
///
/// Shows the current product image (or a placeholder), and buttons to:
///   - Pick from file (all platforms, primary web method)
///   - Snap a photo (native camera, non-web platforms)
///   - Enter / paste a URL manually
///
/// Calls [onChanged] with the new URL whenever the image changes.
class ProductImagePicker extends StatefulWidget {
  const ProductImagePicker({
    super.key,
    this.initialUrl,
    required this.onChanged,
  });

  final String? initialUrl;
  final void Function(String? url) onChanged;

  @override
  State<ProductImagePicker> createState() => _ProductImagePickerState();
}

class _ProductImagePickerState extends State<ProductImagePicker> {
  String? _url;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

  Future<void> _pick(ImagePickerSource source) async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await ImageUploadService.pickAndUpload(source: source);
      if (url != null) {
        setState(() => _url = url);
        widget.onChanged(url);
      }
    } catch (e) {
      setState(() => _error = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _enterUrl(BuildContext context) async {
    final controller = TextEditingController(text: _url ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter image URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com/image.jpg',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      setState(() {
        _url = result.isEmpty ? null : result;
        _error = null;
      });
      widget.onChanged(_url);
    }
  }

  void _remove() {
    setState(() => _url = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Preview ─────────────────────────────────────────────────
        Center(
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _url != null
                    ? Image.network(
                        _url!,
                        width: 140,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              if (_uploading)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black38),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ),
              if (_url != null && !_uploading)
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: _remove,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // ── Error ────────────────────────────────────────────────────
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
        // ── Buttons ──────────────────────────────────────────────────
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            // File picker (works on web + desktop)
            OutlinedButton.icon(
              onPressed: _uploading ? null : () => _pick(ImagePickerSource.file),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Pick File'),
            ),
            // Camera (non-web platforms)
            if (ImageUploadService.hasCameraSupport)
              OutlinedButton.icon(
                onPressed: _uploading ? null : () => _pick(ImagePickerSource.camera),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Camera'),
              ),
            // URL fallback
            OutlinedButton.icon(
              onPressed: _uploading ? null : () => _enterUrl(context),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Paste URL'),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      width: 140,
      height: 120,
      color: Colors.grey.shade200,
      child: const Icon(Icons.fastfood, size: 48, color: Colors.grey),
    );
  }
}
