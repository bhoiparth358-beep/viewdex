import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../data/archive_service.dart';
import '../../../core/errors/result.dart';
import '../../../core/file_detection/file_type_detector.dart';
import '../../file_manager/domain/universal_file.dart';
import '../../file_manager/presentation/file_open_handler.dart';

class ArchiveViewerScreen extends ConsumerStatefulWidget {
  final String path;

  const ArchiveViewerScreen({super.key, required this.path});

  @override
  ConsumerState<ArchiveViewerScreen> createState() => _ArchiveViewerScreenState();
}

class _ArchiveViewerScreenState extends ConsumerState<ArchiveViewerScreen> {
  final _archiveService = ArchiveService();
  bool _isLoading = true;
  String? _error;
  List<ArchiveEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  Future<void> _loadArchive() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _archiveService.listContents(widget.path);
    
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      switch (result) {
        case Success(:final data):
          _entries = data;
        case Failure(:final error):
          _error = error.message;
      }
    });
  }

  Future<void> _extractAll() async {
    final destPath = p.join(p.dirname(widget.path), '${p.basenameWithoutExtension(widget.path)}_extracted');
    
    setState(() {
      _isLoading = true;
    });

    final result = await _archiveService.extractAll(widget.path, destPath);
    
    if (!mounted) return;
    
    setState(() {
      _isLoading = false;
    });

    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extracted to $destPath')),
        );
      case Failure(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${error.message}')),
        );
    }
  }

  Future<void> _extractFile(String entryName) async {
    final destPath = p.dirname(widget.path);
    
    setState(() {
      _isLoading = true;
    });

    final result = await _archiveService.extractFile(widget.path, entryName, destPath);
    
    if (!mounted) return;
    
    setState(() {
      _isLoading = false;
    });

    switch (result) {
      case Success():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extracted $entryName')),
        );
      case Failure(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${error.message}')),
        );
    }
  }

  Future<void> _previewFile(ArchiveEntry entry) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Extracting preview...')),
    );

    final result = await _archiveService.extractToTemp(widget.path, entry.name);
    if (!mounted) return;

    if (result is Success<String>) {
      final tempPath = result.data;
      final detector = DefaultFileTypeDetector();
      final fileType = detector.detectType(tempPath);
      final uFile = UniversalFile(
        name: p.basename(tempPath),
        path: tempPath,
        size: entry.size,
        fileType: fileType,
        isDirectory: false,
      );
      FileOpenHandler.openFile(context, uFile);
    } else if (result is Failure<String>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to preview: ${result.error.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.basename(widget.path), style: const TextStyle(fontSize: 16)),
            if (_entries != null)
              Text(
                '${_entries!.length} items',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          if (_entries != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.unarchive),
              tooltip: 'Extract All',
              onPressed: _extractAll,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadArchive,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_entries == null || _entries!.isEmpty) {
      return const Center(child: Text('Archive is empty'));
    }

    return ListView.builder(
      itemCount: _entries!.length,
      itemBuilder: (context, index) {
        final entry = _entries![index];
        final formattedSize = _formatSize(entry.size);
        final compressedSize = _formatSize(entry.compressedSize);
        
        return ListTile(
          leading: Icon(
            entry.isDirectory ? Icons.folder : Icons.insert_drive_file,
            color: entry.isDirectory ? Colors.amber : Colors.blue,
          ),
          title: Text(entry.name),
          subtitle: Text('Size: $formattedSize (Compressed: $compressedSize)'),
          onTap: entry.isDirectory ? null : () {
            showModalBottomSheet(
              context: context,
              builder: (ctx) => SafeArea(
                child: Wrap(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.visibility),
                      title: const Text('Open / Preview file'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _previewFile(entry);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.download),
                      title: const Text('Extract this file'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _extractFile(entry.name);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
