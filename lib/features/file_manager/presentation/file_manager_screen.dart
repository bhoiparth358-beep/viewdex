import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../providers/file_manager_providers.dart';
import '../domain/universal_file.dart';
import '../domain/file_manager_state.dart';
import 'file_open_handler.dart';

class FileManagerScreen extends ConsumerStatefulWidget {
  const FileManagerScreen({super.key});

  @override
  ConsumerState<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends ConsumerState<FileManagerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(fileManagerProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fileManagerProvider);
    final notifier = ref.read(fileManagerProvider.notifier);

    return Scaffold(
      appBar: state.isSelectionMode
          ? _buildSelectionAppBar(state, notifier)
          : _buildNormalAppBar(state, notifier),
      body: _buildBody(state, notifier),
      floatingActionButton:
          state.isSelectionMode || state.isLoading || state.errorMessage != null
              ? null
              : FloatingActionButton(
                  onPressed: () => _showNewFolderDialog(notifier),
                  child: const Icon(Icons.create_new_folder),
                ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(
      FileManagerState state, FileManagerNotifier notifier) {
    final folderName = state.currentPath.isEmpty
        ? 'Files'
        : p.basename(state.currentPath);

    return AppBar(
      title: Text(folderName),
      leading: state.pathHistory.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => notifier.goBack(),
            )
          : null,
      actions: [
        IconButton(
          icon: Icon(state.viewMode == ViewMode.list
              ? Icons.grid_view
              : Icons.view_list),
          onPressed: () => notifier.toggleViewMode(),
        ),
        PopupMenuButton<SortMode>(
          icon: const Icon(Icons.sort),
          onSelected: (mode) => notifier.setSortMode(mode),
          itemBuilder: (context) => [
            _buildSortMenuItem(SortMode.name, 'Name', state),
            _buildSortMenuItem(SortMode.size, 'Size', state),
            _buildSortMenuItem(SortMode.date, 'Date', state),
            _buildSortMenuItem(SortMode.type, 'Type', state),
          ],
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'refresh') notifier.refresh();
            if (value == 'select_all') notifier.selectAll();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            PopupMenuItem(value: 'select_all', child: Text('Select All')),
          ],
        ),
      ],
    );
  }

  PopupMenuItem<SortMode> _buildSortMenuItem(
      SortMode mode, String label, FileManagerState state) {
    final isSelected = state.sortMode == mode;
    return PopupMenuItem(
      value: mode,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          if (isSelected)
            Icon(
              state.sortAscending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 16,
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(
      FileManagerState state, FileManagerNotifier notifier) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => notifier.clearSelection(),
      ),
      title: Text('${state.selectedFiles.length} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          onPressed: () => notifier.selectAll(),
        ),
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: state.selectedFiles.isEmpty
              ? null
              : () {
                  final validFiles = state.selectedFiles
                      .where((p) => !FileSystemEntity.isDirectorySync(p))
                      .map((p) => XFile(p))
                      .toList();
                  if (validFiles.isNotEmpty) {
                    Share.shareXFiles(validFiles);
                  }
                },
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: state.selectedFiles.isEmpty
              ? null
              : () => _showDeleteConfirmDialog(notifier),
        ),
      ],
    );
  }

  Widget _buildBody(FileManagerState state, FileManagerNotifier notifier) {
    if (state.isLoading && state.files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(state.errorMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => notifier.initialize(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('This folder is empty',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => notifier.refresh(),
      child: state.viewMode == ViewMode.list
          ? _buildListView(state, notifier)
          : _buildGridView(state, notifier),
    );
  }

  Widget _buildListView(FileManagerState state, FileManagerNotifier notifier) {
    return ListView.builder(
      itemCount: state.files.length,
      itemBuilder: (context, index) {
        final file = state.files[index];
        final isSelected = state.selectedFiles.contains(file.path);

        return ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3),
          leading: _getFileIcon(file.fileType, isSelected),
          title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_getSubtitle(file)),
          trailing: state.isSelectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => notifier.toggleSelection(file.path),
                )
              : PopupMenuButton<String>(
                  onSelected: (val) =>
                      _handleFileAction(val, file, notifier),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'open', child: Text('Open')),
                    PopupMenuItem(value: 'share', child: Text('Share')),
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'properties', child: Text('Properties')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
          onTap: () => _onFileTap(file, state, notifier),
          onLongPress: () {
            notifier.enterSelectionMode();
            notifier.toggleSelection(file.path);
          },
        );
      },
    );
  }

  Widget _buildGridView(FileManagerState state, FileManagerNotifier notifier) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: state.files.length,
      itemBuilder: (context, index) {
        final file = state.files[index];
        final isSelected = state.selectedFiles.contains(file.path);

        return InkWell(
          onTap: () => _onFileTap(file, state, notifier),
          onLongPress: () {
            notifier.enterSelectionMode();
            notifier.toggleSelection(file.path);
          },
          child: Card(
            color: isSelected
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.5)
                : null,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                          child: _getFileIcon(file.fileType, false, size: 48)),
                      const SizedBox(height: 8),
                      Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (!file.isDirectory) ...[
                        const SizedBox(height: 4),
                        Text(
                          file.formattedSize,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (state.isSelectionMode)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => notifier.toggleSelection(file.path),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getSubtitle(UniversalFile file) {
    final parts = <String>[];
    if (file.isDirectory) {
      parts.add('Folder');
    } else {
      parts.add(file.formattedSize);
    }
    if (file.modifiedDate != null) {
      parts.add(DateFormat('MMM d, yyyy').format(file.modifiedDate!));
    }
    return parts.join(' • ');
  }

  void _onFileTap(
      UniversalFile file, FileManagerState state, FileManagerNotifier notifier) {
    if (state.isSelectionMode) {
      notifier.toggleSelection(file.path);
    } else if (file.isDirectory) {
      notifier.navigateTo(file.path);
    } else {
      FileOpenHandler.openFile(context, file);
    }
  }

  Widget _getFileIcon(FileType type, bool isSelected, {double size = 24}) {
    if (isSelected) {
      return CircleAvatar(
        radius: size / 2 + 4,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.check,
            color: Theme.of(context).colorScheme.onPrimary,
            size: size * 0.8),
      );
    }

    final (iconData, color) = switch (type) {
      FileType.folder => (Icons.folder, Theme.of(context).colorScheme.primary),
      FileType.pdf => (Icons.picture_as_pdf, Colors.red),
      FileType.archive => (Icons.folder_zip, Colors.amber.shade700),
      FileType.document => (Icons.description, Colors.blue),
      FileType.spreadsheet => (Icons.table_chart, Colors.green),
      FileType.presentation => (Icons.slideshow, Colors.orange),
      FileType.image => (Icons.image, Colors.purple),
      FileType.video => (Icons.video_file, Colors.deepOrange),
      FileType.audio => (Icons.audio_file, Colors.pink),
      FileType.text => (Icons.text_snippet, Colors.grey),
      FileType.unknown => (Icons.insert_drive_file, Colors.grey),
    };

    return Icon(iconData, color: color, size: size);
  }

  void _handleFileAction(
      String action, UniversalFile file, FileManagerNotifier notifier) {
    switch (action) {
      case 'open':
        if (file.isDirectory) {
          notifier.navigateTo(file.path);
        } else {
          FileOpenHandler.openFile(context, file);
        }
      case 'rename':
        _showRenameDialog(file, notifier);
      case 'share':
        if (!file.isDirectory) {
          Share.shareXFiles([XFile(file.path)]);
        }
      case 'properties':
        _showPropertiesDialog(file);
      case 'delete':
        notifier.enterSelectionMode();
        notifier.toggleSelection(file.path);
        _showDeleteConfirmDialog(notifier);
    }
  }

  void _showNewFolderDialog(FileManagerNotifier notifier) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                notifier.createFolder(controller.text.trim());
              }
              Navigator.pop(ctx);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(UniversalFile file, FileManagerNotifier notifier) {
    final controller = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != file.name) {
                notifier.renameFile(file.path, newName);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(FileManagerNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Files'),
        content: const Text(
            'Are you sure you want to delete the selected files? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              notifier.deleteSelected();
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showPropertiesDialog(UniversalFile file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Properties'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${file.name}'),
            const SizedBox(height: 8),
            Text('Path: ${file.path}'),
            const SizedBox(height: 8),
            Text('Size: ${file.isDirectory ? "-" : file.formattedSize}'),
            const SizedBox(height: 8),
            if (file.modifiedDate != null)
              Text(
                  'Modified: ${DateFormat('MMM d, yyyy h:mm a').format(file.modifiedDate!)}'),
            if (file.mimeType != null) ...[
              const SizedBox(height: 8),
              Text('Type: ${file.mimeType}'),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }
}
