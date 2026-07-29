// lib/widgets/media_upload_tile.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_upload_service.dart';

/// Centralized Reusable Media Upload & Preview Tile.
///
/// Handles picking from Camera, Gallery, or Files, converting to compressed
/// Base64, and displaying instant visual previews for Employee & Student documents.
class MediaUploadTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final String? initialValue; // Base64 data URI or HTTP URL
  final ValueChanged<String?>? onChanged; // Returns Base64 string or null on clear
  final bool isDocument;
  final bool readOnly;

  const MediaUploadTile({
    super.key,
    required this.label,
    required this.icon,
    this.initialValue,
    this.onChanged,
    this.isDocument = false,
    this.readOnly = false,
  });

  @override
  State<MediaUploadTile> createState() => _MediaUploadTileState();
}

class _MediaUploadTileState extends State<MediaUploadTile> {
  String? _currentValue;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
  }

  @override
  void didUpdateWidget(MediaUploadTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      setState(() => _currentValue = widget.initialValue);
    }
  }

  Future<void> _pickFromCamera() async {
    if (widget.readOnly) return;
    setState(() => _isProcessing = true);
    final b64 = await ImageUploadService.pickAndProcessImage(source: ImageSource.camera);
    setState(() => _isProcessing = false);
    if (b64 != null) {
      setState(() => _currentValue = b64);
      widget.onChanged?.call(b64);
    }
  }

  Future<void> _pickFromGallery() async {
    if (widget.readOnly) return;
    setState(() => _isProcessing = true);
    final b64 = widget.isDocument
        ? await ImageUploadService.pickDocumentFile()
        : await ImageUploadService.pickAndProcessImage(source: ImageSource.gallery);
    setState(() => _isProcessing = false);
    if (b64 != null) {
      setState(() => _currentValue = b64);
      widget.onChanged?.call(b64);
    }
  }

  void _clearValue() {
    if (widget.readOnly) return;
    setState(() => _currentValue = null);
    widget.onChanged?.call(null);
  }

  void _showDocumentPreview() {
    final val = _currentValue;
    if (val == null || val.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(widget.icon, color: const Color(0xFF00695C)),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Center(
            child: _buildPreviewImage(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildPreviewImage() {
    if (_currentValue == null || _currentValue!.isEmpty) {
      return Icon(widget.icon, size: 28, color: const Color(0xFF00695C));
    }

    final val = _currentValue!;

    // 1. HTTP URL
    if (val.startsWith('http://') || val.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          val,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.grey),
        ),
      );
    }

    // 2. Base64 String / Data URI
    final Uint8List? bytes = ImageUploadService.decodeBase64ToBytes(val);
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.insert_drive_file_rounded, color: Colors.blue),
        ),
      );
    }

    // 3. Local File Path fallback
    try {
      final file = File(val);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.insert_drive_file_rounded, color: Colors.blue),
          ),
        );
      }
    } catch (_) {}

    return Icon(widget.icon, size: 28, color: const Color(0xFF00695C));
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = _currentValue != null && _currentValue!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hasValue ? Colors.teal.shade300 : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF00695C).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00695C)),
                    )
                  : _buildPreviewImage(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF1E293B),
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasValue ? 'Uploaded' : 'No file selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: hasValue ? Colors.teal.shade700 : Colors.grey.shade500,
                    fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (widget.readOnly)
            if (hasValue)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.visibility_rounded, color: Color(0xFF00695C), size: 18),
                onPressed: _showDocumentPreview,
                tooltip: 'Preview Document',
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('Not Uploaded', style: TextStyle(fontSize: 10, color: Colors.grey)),
              )
          else if (hasValue)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
              onPressed: _clearValue,
              tooltip: 'Remove',
            )
          else ...[
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF00695C), size: 18),
              onPressed: _pickFromCamera,
              tooltip: 'Take Photo',
            ),
            const SizedBox(width: 2),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.folder_open_rounded, color: Color(0xFF00695C), size: 18),
              onPressed: _pickFromGallery,
              tooltip: 'Choose File',
            ),
          ],
        ],
      ),
    );
  }
}
