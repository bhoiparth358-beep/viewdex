import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../domain/universal_file.dart';
import '../domain/file_manager_state.dart';
import '../data/file_system_repository.dart';
import '../data/platform_file_system.dart';
import '../../../core/file_detection/file_type_detector.dart';
import '../../../core/services/permission_service.dart';


final fileTypeDetectorProvider = Provider<FileTypeDetector>((ref) {
  return DefaultFileTypeDetector();
});

final fileSystemRepositoryProvider = Provider<FileSystemRepository>((ref) {
  final detector = ref.watch(fileTypeDetectorProvider);
  return PlatformFileSystem(detector);
});

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

final fileManagerProvider =
    StateNotifierProvider<FileManagerNotifier, FileManagerState>((ref) {
  final repository = ref.watch(fileSystemRepositoryProvider);
  final permissionService = ref.watch(permissionServiceProvider);
  return FileManagerNotifier(repository, permissionService);
});

class FileManagerNotifier extends StateNotifier<FileManagerState> {
  final FileSystemRepository _repository;
  final PermissionService _permissionService;

  FileManagerNotifier(this._repository, this._permissionService)
      : super(const FileManagerState());

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final hasPermission = await _permissionService.hasStoragePermission();
    if (!hasPermission) {
      final granted = await _permissionService.requestStoragePermission();
      if (!granted) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Storage permission is required to view files.',
        );
        return;
      }
    }

    final rootResult = await _repository.getStorageRoot();
    rootResult.fold(
      (path) => navigateTo(path),
      (error) => state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to access storage: ${error.message}',
      ),
    );
  }

  Future<void> navigateTo(String path) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await _repository.listDirectory(path);

    result.fold(
      (files) {
        final newHistory = List<String>.from(state.pathHistory);
        if (state.currentPath.isNotEmpty &&
            (newHistory.isEmpty || newHistory.last != state.currentPath)) {
          newHistory.add(state.currentPath);
        }

        state = state.copyWith(
          files: _sortFiles(files),
          currentPath: path,
          pathHistory: newHistory,
          isLoading: false,
          selectedFiles: {},
          isSelectionMode: false,
          errorMessage: null,
        );
      },
      (error) => state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to open directory: ${error.message}',
      ),
    );
  }

  Future<void> goBack() async {
    if (state.pathHistory.isEmpty) return;

    final newHistory = List<String>.from(state.pathHistory);
    final previousPath = newHistory.removeLast();

    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _repository.listDirectory(previousPath);

    result.fold(
      (files) {
        state = state.copyWith(
          files: _sortFiles(files),
          currentPath: previousPath,
          pathHistory: newHistory,
          isLoading: false,
          selectedFiles: {},
          isSelectionMode: false,
          errorMessage: null,
        );
      },
      (error) => state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to go back: ${error.message}',
      ),
    );
  }

  Future<void> refresh() async {
    if (state.currentPath.isEmpty) return;

    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _repository.listDirectory(state.currentPath);

    result.fold(
      (files) => state = state.copyWith(
        files: _sortFiles(files),
        isLoading: false,
        errorMessage: null,
      ),
      (error) => state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to refresh: ${error.message}',
      ),
    );
  }

  Future<void> createFolder(String name) async {
    if (state.currentPath.isEmpty) return;

    state = state.copyWith(isLoading: true, errorMessage: null);
    final folderPath = p.join(state.currentPath, name);
    final result = await _repository.createDirectory(folderPath);

    result.fold(
      (_) => refresh(),
      (error) => state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to create folder: ${error.message}',
      ),
    );
  }

  Future<void> deleteSelected() async {
    if (state.selectedFiles.isEmpty) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    final errors = <String>[];
    for (final path in state.selectedFiles) {
      final result = await _repository.deleteFile(path);
      if (result.isFailure) {
        errors.add(p.basename(path));
      }
    }

    state = state.copyWith(
      selectedFiles: {},
      isSelectionMode: false,
      errorMessage: errors.isNotEmpty ? 'Failed to delete: ${errors.join(", ")}' : null,
    );
    await refresh();
  }

  Future<void> renameFile(String oldPath, String newName) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final dir = p.dirname(oldPath);
    final newPath = p.join(dir, newName);

    final result = await _repository.renameFile(oldPath, newPath);

    result.fold(
      (_) => refresh(),
      (error) => state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to rename: ${error.message}',
      ),
    );
  }

  void toggleViewMode() {
    final newMode =
        state.viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
    state = state.copyWith(viewMode: newMode);
  }

  void setSortMode(SortMode mode) {
    if (state.sortMode == mode) {
      toggleSortOrder();
    } else {
      state = state.copyWith(
        sortMode: mode,
        sortAscending: true,
        files: _sortFiles(state.files, overrideMode: mode, overrideAsc: true),
      );
    }
  }

  void toggleSortOrder() {
    final newAsc = !state.sortAscending;
    state = state.copyWith(
      sortAscending: newAsc,
      files: _sortFiles(state.files, overrideAsc: newAsc),
    );
  }

  void toggleSelection(String path) {
    final newSelection = Set<String>.from(state.selectedFiles);
    if (newSelection.contains(path)) {
      newSelection.remove(path);
    } else {
      newSelection.add(path);
    }

    state = state.copyWith(
      selectedFiles: newSelection,
      isSelectionMode: newSelection.isNotEmpty,
    );
  }

  void selectAll() {
    final allPaths = state.files.map((f) => f.path).toSet();
    state = state.copyWith(
      selectedFiles: allPaths,
      isSelectionMode: true,
    );
  }

  void clearSelection() {
    state = state.copyWith(
      selectedFiles: {},
      isSelectionMode: false,
    );
  }

  void enterSelectionMode() {
    state = state.copyWith(isSelectionMode: true);
  }

  List<UniversalFile> _sortFiles(
    List<UniversalFile> files, {
    SortMode? overrideMode,
    bool? overrideAsc,
  }) {
    final mode = overrideMode ?? state.sortMode;
    final asc = overrideAsc ?? state.sortAscending;

    final list = List<UniversalFile>.from(files);

    list.sort((a, b) {
      // Folders always first
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      int comparison;
      switch (mode) {
        case SortMode.name:
          comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortMode.size:
          comparison = a.size.compareTo(b.size);
        case SortMode.date:
          final aDate = a.modifiedDate ?? DateTime(1970);
          final bDate = b.modifiedDate ?? DateTime(1970);
          comparison = aDate.compareTo(bDate);
        case SortMode.type:
          final aExt = a.extension ?? '';
          final bExt = b.extension ?? '';
          comparison = aExt.compareTo(bExt);
          if (comparison == 0) {
            comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
      }

      return asc ? comparison : -comparison;
    });

    return list;
  }
}

final storageInfoProvider = FutureProvider<StorageInfo>((ref) async {
  final repository = ref.watch(fileSystemRepositoryProvider);
  final result = await repository.getStorageInfo();

  return result.fold(
    (info) => info,
    (error) => throw Exception('Failed to get storage info: ${error.message}'),
  );
});
