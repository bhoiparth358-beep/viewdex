import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';

class ImageViewerScreen extends StatelessWidget {
  final String filePath;

  const ImageViewerScreen({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    final fileName = file.uri.pathSegments.last;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              if (file.existsSync()) {
                Share.shareXFiles([XFile(filePath)]);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showInfoDialog(context, file);
            },
          ),
        ],
      ),
      body: file.existsSync()
          ? PhotoView(
              imageProvider: FileImage(file),
              backgroundDecoration: const BoxDecoration(
                color: Colors.black,
              ),
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Text('Error loading image', style: TextStyle(color: Colors.white)),
              ),
            )
          : const Center(
              child: Text('File not found', style: TextStyle(color: Colors.white)),
            ),
    );
  }

  void _showInfoDialog(BuildContext context, File file) async {
    int size = 0;
    DateTime? modified;
    if (file.existsSync()) {
      size = await file.length();
      modified = await file.lastModified();
    }
    
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Image Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Path: ${file.path}'),
              Text('Size: ${(size / 1024).toStringAsFixed(2)} KB'),
              Text('Modified: ${modified?.toString() ?? "Unknown"}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }
}
