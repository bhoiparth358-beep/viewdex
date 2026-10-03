import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/library_providers.dart';
import '../../file_manager/domain/universal_file.dart';
import '../../file_manager/presentation/file_open_handler.dart';
import '../../../core/file_detection/file_type_detector.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FileTypeDetector _detector = DefaultFileTypeDetector();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  IconData _getIconForType(FileType type) {
    return switch (type) {
      FileType.folder => Icons.folder,
      FileType.pdf => Icons.picture_as_pdf,
      FileType.archive => Icons.archive,
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

  UniversalFile _buildUniversalFile(
      String path, FileType type, int size, DateTime modified) {
    final name = path.split(Platform.pathSeparator).last;
    return UniversalFile(
      name: name,
      path: path,
      extension: name.contains('.') ? name.split('.').last : null,
      size: size,
      modifiedDate: modified,
      fileType: type,
      isDirectory: FileSystemEntity.isDirectorySync(path),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Favorites', icon: Icon(Icons.favorite)),
            Tab(text: 'Recents', icon: Icon(Icons.access_time)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FavoritesTab(
            getIconForType: _getIconForType,
            buildFile: _buildUniversalFile,
            detector: _detector,
          ),
          _RecentsTab(
            getIconForType: _getIconForType,
            buildFile: _buildUniversalFile,
            detector: _detector,
          ),
        ],
      ),
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  final IconData Function(FileType) getIconForType;
  final UniversalFile Function(String, FileType, int, DateTime) buildFile;
  final FileTypeDetector detector;

  const _FavoritesTab({
    required this.getIconForType,
    required this.buildFile,
    required this.detector,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);

    if (favorites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No favorites yet'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final path = favorites[index];
        final file = File(path);
        final exists = file.existsSync();
        final name = path.split(Platform.pathSeparator).last;
        final type = detector.detectType(path);

        return Dismissible(
          key: Key('fav_$path'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16.0),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) {
            ref.read(favoritesProvider.notifier).removeFavorite(path);
          },
          child: ListTile(
            leading: Icon(getIconForType(type)),
            title: Text(name),
            subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing:
                !exists ? const Icon(Icons.error_outline, color: Colors.red) : null,
            onTap: exists
                ? () {
                    final stat = file.statSync();
                    final uFile =
                        buildFile(path, type, stat.size, stat.modified);
                    FileOpenHandler.openFile(context, uFile);
                  }
                : null,
          ),
        );
      },
    );
  }
}

class _RecentsTab extends ConsumerWidget {
  final IconData Function(FileType) getIconForType;
  final UniversalFile Function(String, FileType, int, DateTime) buildFile;
  final FileTypeDetector detector;

  const _RecentsTab({
    required this.getIconForType,
    required this.buildFile,
    required this.detector,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentFilesProvider);

    if (recents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No recent files'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: recents.length,
      itemBuilder: (context, index) {
        final path = recents[index];
        final file = File(path);
        final exists = file.existsSync();
        final name = path.split(Platform.pathSeparator).last;
        final type = detector.detectType(path);

        return ListTile(
          leading: Icon(getIconForType(type)),
          title: Text(name),
          subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing:
              !exists ? const Icon(Icons.error_outline, color: Colors.red) : null,
          onTap: exists
              ? () {
                  final stat = file.statSync();
                  final uFile =
                      buildFile(path, type, stat.size, stat.modified);
                  FileOpenHandler.openFile(context, uFile);
                }
              : null,
          onLongPress: () {
            ref.read(favoritesProvider.notifier).addFavorite(path);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$name added to favorites')),
            );
          },
        );
      },
    );
  }
}
