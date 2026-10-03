import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../file_manager/providers/file_manager_providers.dart';
import '../../file_manager/domain/universal_file.dart';
import '../../file_manager/presentation/file_open_handler.dart';
import '../../library/providers/library_providers.dart';
import '../../search/providers/search_providers.dart';
import '../../../core/file_detection/file_type_detector.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageInfoAsync = ref.watch(storageInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Viewdex'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome to Viewdex',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              _buildStorageCard(context, storageInfoAsync),
              const SizedBox(height: 24),
              Text(
                'Quick Access',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _buildQuickAccess(context, ref),
              const SizedBox(height: 24),
              Text(
                'Recent Files',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _buildRecentFiles(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStorageCard(BuildContext context, AsyncValue storageInfoAsync) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage,
                    color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  'Internal Storage',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            storageInfoAsync.when(
              data: (info) {
                final totalGB = info.totalBytes / (1024 * 1024 * 1024);
                final usedGB = info.usedBytes / (1024 * 1024 * 1024);
                final freeGB = info.freeBytes / (1024 * 1024 * 1024);
                final usagePercent = totalGB > 0 ? usedGB / totalGB : 0.0;

                return Column(
                  children: [
                    LinearProgressIndicator(
                      value: usagePercent,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${usedGB.toStringAsFixed(1)} GB used'),
                        Text('${freeGB.toStringAsFixed(1)} GB free'),
                      ],
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Column(
                children: [
                  const LinearProgressIndicator(value: 0.5),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('64.0 GB used'),
                      Text('64.0 GB free'),
                    ],
                  ),
                  Text(
                    'Access limited or initializing',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAccess(BuildContext context, WidgetRef ref) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        _QuickAccessItem(
          icon: Icons.image,
          label: 'Images',
          color: Colors.purple,
          onTap: () {
            ref.read(searchFilterProvider.notifier).state = FileType.image;
            context.go('/search');
          },
        ),
        _QuickAccessItem(
          icon: Icons.video_file,
          label: 'Videos',
          color: Colors.deepOrange,
          onTap: () {
            ref.read(searchFilterProvider.notifier).state = FileType.video;
            context.go('/search');
          },
        ),
        _QuickAccessItem(
          icon: Icons.audio_file,
          label: 'Audio',
          color: Colors.pink,
          onTap: () {
            ref.read(searchFilterProvider.notifier).state = FileType.audio;
            context.go('/search');
          },
        ),
        _QuickAccessItem(
          icon: Icons.description,
          label: 'Docs',
          color: Colors.blue,
          onTap: () {
            ref.read(searchFilterProvider.notifier).state = FileType.document;
            context.go('/search');
          },
        ),
        _QuickAccessItem(
          icon: Icons.picture_as_pdf,
          label: 'PDFs',
          color: Colors.red,
          onTap: () {
            ref.read(searchFilterProvider.notifier).state = FileType.pdf;
            context.go('/search');
          },
        ),
        _QuickAccessItem(
          icon: Icons.folder_zip,
          label: 'Archives',
          color: Colors.amber,
          onTap: () {
            ref.read(searchFilterProvider.notifier).state = FileType.archive;
            context.go('/search');
          },
        ),
        _QuickAccessItem(
          icon: Icons.folder,
          label: 'Files',
          color: Colors.teal,
          onTap: () => context.go('/files'),
        ),
        _QuickAccessItem(
          icon: Icons.more_horiz,
          label: 'More',
          color: Colors.grey,
          onTap: () => context.go('/library'),
        ),
      ],
    );
  }

  Widget _buildRecentFiles(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentFilesProvider);

    if (recents.isEmpty) {
      return Card(
        elevation: 0,
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.history, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text('No recent files yet',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    }

    final topRecents = recents.take(5).toList();
    final detector = DefaultFileTypeDetector();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: topRecents.length,
      itemBuilder: (context, index) {
        final path = topRecents[index];
        final name = path.split(Platform.pathSeparator).last;
        final file = File(path);
        final exists = file.existsSync();
        final type = detector.detectType(path);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(_getIconForType(type),
                color: Theme.of(context).colorScheme.primary),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: exists
              ? () {
                  final stat = file.statSync();
                  final uFile = UniversalFile(
                    name: name,
                    path: path,
                    size: stat.size,
                    fileType: type,
                    isDirectory: false,
                  );
                  FileOpenHandler.openFile(context, uFile);
                }
              : null,
        );
      },
    );
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
}

class _QuickAccessItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAccessItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
