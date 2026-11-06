import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../file_manager/domain/universal_file.dart';
import '../../file_manager/presentation/file_open_handler.dart';
import '../../file_manager/providers/file_manager_providers.dart';
import '../../../core/errors/result.dart';
import '../../../core/file_detection/file_type_detector.dart';

/// Scans the entire device storage and shows all files matching a given [FileType].
/// Used when tapping Quick Access items (Images, Videos, Audio, Docs, PDFs, Archives).
class CategoryFilesScreen extends ConsumerStatefulWidget {
  final FileType fileType;
  final String label;

  const CategoryFilesScreen({
    super.key,
    required this.fileType,
    required this.label,
  });

  @override
  ConsumerState<CategoryFilesScreen> createState() =>
      _CategoryFilesScreenState();
}

class _CategoryFilesScreenState extends ConsumerState<CategoryFilesScreen> {
  List<UniversalFile> _files = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanFiles();
  }

  Future<void> _scanFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _files = [];
    });

    try {
      final repository = ref.read(fileSystemRepositoryProvider);
      final detector = ref.read(fileTypeDetectorProvider);
      final rootResult = await repository.getStorageRoot();

      String rootPath;
      if (rootResult is Success<String>) {
        rootPath = rootResult.data;
      } else {
        setState(() {
          _error = 'Could not access storage.';
          _isLoading = false;
        });
        return;
      }

      final results = <UniversalFile>[];
      await _searchDirectory(Directory(rootPath), detector, results);

      // Sort by modified date, newest first
      results.sort((a, b) {
        final aDate = a.modifiedDate ?? DateTime(1970);
        final bDate = b.modifiedDate ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });

      if (mounted) {
        setState(() {
          _files = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error scanning files: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _searchDirectory(
    Directory dir,
    FileTypeDetector detector,
    List<UniversalFile> results,
  ) async {
    if (results.length >= 500) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (results.length >= 500) return;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;

        if (entity is Directory) {
          await _searchDirectory(entity, detector, results);
        } else if (entity is File) {
          final fileType = detector.detectType(entity.path);
          if (fileType == widget.fileType) {
            final ext = name.contains('.') ? name.split('.').last : null;
            try {
              final stat = await entity.stat();
              results.add(UniversalFile(
                name: name,
                path: entity.path,
                extension: ext,
                size: stat.size,
                modifiedDate: stat.modified,
                fileType: fileType,
                isDirectory: false,
              ));
            } catch (_) {
              // Skip unreadable files
            }
          }
        }
      }
    } catch (_) {
      // Skip unreadable directories
    }
  }

  IconData _getIconForType(FileType type) {
    return switch (type) {
      FileType.folder => Icons.folder,
      FileType.pdf => Icons.picture_as_pdf,
      FileType.archive => Icons.folder_zip,
      FileType.document => Icons.description,
      FileType.spreadsheet => Icons.table_chart,
      FileType.presentation => Icons.slideshow,
      FileType.image => Icons.image,
      FileType.video => Icons.video_file,
      FileType.audio => Icons.audio_file,
      FileType.text => Icons.text_snippet,
      FileType.unknown => Icons.insert_drive_file,
    };
  }

  Color _getColorForType(FileType type) {
    return switch (type) {
      FileType.folder => Colors.blue,
      FileType.pdf => Colors.red,
      FileType.archive => Colors.amber.shade700,
      FileType.document => Colors.blue,
      FileType.spreadsheet => Colors.green,
      FileType.presentation => Colors.orange,
      FileType.image => Colors.purple,
      FileType.video => Colors.deepOrange,
      FileType.audio => Colors.pink,
      FileType.text => Colors.grey,
      FileType.unknown => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_files.length} file${_files.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Scanning for ${widget.label.toLowerCase()}...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _scanFiles,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getIconForType(widget.fileType),
              size: 64,
              color: _getColorForType(widget.fileType).withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No ${widget.label.toLowerCase()} found',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _scanFiles,
      child: ListView.builder(
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  _getColorForType(file.fileType).withValues(alpha: 0.15),
              child: Icon(
                _getIconForType(file.fileType),
                color: _getColorForType(file.fileType),
              ),
            ),
            title:
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${file.formattedSize}  •  ${file.path}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => FileOpenHandler.openFile(context, file),
          );
        },
      ),
    );
  }
}
