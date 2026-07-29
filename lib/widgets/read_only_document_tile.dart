// lib/widgets/read_only_document_tile.dart
import 'package:flutter/material.dart';
import '../services/image_upload_service.dart';

/// Read-only document tile for displaying student and guardian documents (B-Form, CNIC, etc.).
/// Allows users (e.g. parents) to view thumbnails and tap to enlarge & zoom full-screen.
/// Does NOT contain any edit, upload, or delete capabilities.
class ReadOnlyDocumentTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? documentUri;

  const ReadOnlyDocumentTile({
    super.key,
    required this.label,
    required this.icon,
    this.documentUri,
  });

  bool get _hasDoc => documentUri != null && documentUri!.trim().isNotEmpty;

  void _showEnlargedDialog(BuildContext context) {
    if (!_hasDoc) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.black,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 600),
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: _buildImageWidget(documentUri!),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black,
                child: const Text(
                  'Pinch or double tap to zoom • Read Only',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageWidget(String uri) {
    if (uri.startsWith('data:image') || uri.startsWith('data:application') || !uri.startsWith('http')) {
      final bytes = ImageUploadService.decodeBase64ToBytes(uri);
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.contain);
      }
    }
    return Image.network(
      uri,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
              SizedBox(height: 8),
              Text('Unable to display image', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    if (!_hasDoc) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(icon, color: Colors.grey.shade400, size: 24),
      );
    }

    final uri = documentUri!;
    Widget imageWidget;
    if (uri.startsWith('data:image') || uri.startsWith('data:application') || !uri.startsWith('http')) {
      final bytes = ImageUploadService.decodeBase64ToBytes(uri);
      if (bytes != null) {
        imageWidget = Image.memory(bytes, fit: BoxFit.cover, width: 48, height: 48);
      } else {
        imageWidget = Icon(icon, color: Colors.grey, size: 24);
      }
    } else {
      imageWidget = Image.network(
        uri,
        fit: BoxFit.cover,
        width: 48,
        height: 48,
        errorBuilder: (_, __, ___) => Icon(icon, color: Colors.grey, size: 24),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: imageWidget,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _buildThumbnail(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _hasDoc ? 'Document available (Tap to Enlarge)' : 'No document uploaded',
                  style: TextStyle(
                    fontSize: 11,
                    color: _hasDoc ? const Color(0xFF059669) : Colors.grey.shade500,
                    fontWeight: _hasDoc ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (_hasDoc)
            InkWell(
              onTap: () => _showEnlargedDialog(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF4C4DDC).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF4C4DDC).withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in_rounded, size: 16, color: Color(0xFF4C4DDC)),
                    SizedBox(width: 4),
                    Text(
                      'Enlarge',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4C4DDC),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
