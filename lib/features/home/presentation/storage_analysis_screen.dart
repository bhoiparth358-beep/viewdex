import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../file_manager/domain/universal_file.dart';
import '../../file_manager/providers/file_manager_providers.dart';
import '../../search/providers/search_providers.dart';
import '../../../core/file_detection/file_type_detector.dart';

class CategoryStorageData {
  final FileType type;
  final String label;
  final IconData icon;
  final Color color;
  int totalBytes = 0;
  int fileCount = 0;

  CategoryStorageData({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
  });

  String get formattedSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class StorageAnalysisScreen extends ConsumerStatefulWidget {
  const StorageAnalysisScreen({super.key});

  @override
  ConsumerState<StorageAnalysisScreen> createState() => _StorageAnalysisScreenState();
}

class _StorageAnalysisScreenState extends ConsumerState<StorageAnalysisScreen> {
  bool _isAnalyzing = true;
  late Map<FileType, CategoryStorageData> _categories;

  @override
  void initState() {
    super.initState();
    _categories = {
      FileType.image: CategoryStorageData(
        type: FileType.image,
        label: 'Images',
        icon: Icons.image,
        color: Colors.purple,
      ),
      FileType.video: CategoryStorageData(
        type: FileType.video,
        label: 'Videos',
        icon: Icons.video_file,
        color: Colors.deepOrange,
      ),
      FileType.audio: CategoryStorageData(
        type: FileType.audio,
        label: 'Audio & Music',
        icon: Icons.audio_file,
        color: Colors.pink,
      ),
      FileType.document: CategoryStorageData(
        type: FileType.document,
        label: 'Documents & Office',
        icon: Icons.description,
        color: Colors.blue,
      ),
      FileType.pdf: CategoryStorageData(
        type: FileType.pdf,
        label: 'PDF Files',
        icon: Icons.picture_as_pdf,
        color: Colors.red,
      ),
      FileType.archive: CategoryStorageData(
        type: FileType.archive,
        label: 'Archives & ZIPs',
        icon: Icons.folder_zip,
        color: Colors.amber.shade700,
      ),
      FileType.unknown: CategoryStorageData(
        type: FileType.unknown,
        label: 'Other Files',
        icon: Icons.insert_drive_file,
        color: Colors.grey,
      ),
    };
    _startAnalysis();
  }

  Future<void> _startAnalysis() async {
    final detector = ref.read(fileTypeDetectorProvider);
    final repo = ref.read(fileSystemRepositoryProvider);
    final rootResult = await repo.getStorageRoot();

    final rootPath = rootResult.fold(
      (path) => path,
      (error) => '/storage/emulated/0',
    );

    try {
      final rootDir = Directory(rootPath);
      if (await rootDir.exists()) {
        // Scan files up to depth 4 to be fast and responsive
        await _scanDirectory(rootDir, detector, 0);
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _scanDirectory(
      Directory dir, FileTypeDetector detector, int depth) async {
    if (depth > 4) return;
    try {
      final entities = await dir.list(followLinks: false).toList();
      for (final entity in entities) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue; // Skip hidden

        if (entity is File) {
          try {
            final size = await entity.length();
            final type = detector.detectType(entity.path);
            final targetCategory = _categories[type] ?? _categories[FileType.unknown]!;
            targetCategory.totalBytes += size;
            targetCategory.fileCount += 1;
          } catch (_) {}
        } else if (entity is Directory) {
          await _scanDirectory(entity, detector, depth + 1);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final storageInfoAsync = ref.watch(storageInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Breakdown'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            storageInfoAsync.when(
              data: (info) {
                final totalGB = info.totalBytes / (1024 * 1024 * 1024);
                final usedGB = info.usedBytes / (1024 * 1024 * 1024);
                final freeGB = info.freeBytes / (1024 * 1024 * 1024);
                final percent = totalGB > 0 ? (usedGB / totalGB) : 0.0;

                return Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device Storage Space',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: percent,
                            minHeight: 12,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${usedGB.toStringAsFixed(1)} GB Used (${(percent * 100).toStringAsFixed(0)}%)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${freeGB.toStringAsFixed(1)} GB Free',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total Capacity: ${totalGB.toStringAsFixed(1)} GB',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => const SizedBox(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'What is taking up space?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (_isAnalyzing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ..._categories.values.map((cat) {
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cat.color.withValues(alpha: 0.15),
                    child: Icon(cat.icon, color: cat.color),
                  ),
                  title: Text(cat.label,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${cat.fileCount} files found'),
                  trailing: Text(
                    cat.formattedSize,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  onTap: () {
                    ref.read(searchFilterProvider.notifier).state = cat.type;
                    context.go('/search');
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
