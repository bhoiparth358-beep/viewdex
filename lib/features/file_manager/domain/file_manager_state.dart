import 'universal_file.dart';

enum ViewMode { list, grid }
enum SortMode { name, size, date, type }

class FileManagerState {
  final List<UniversalFile> files;
  final String currentPath;
  final List<String> pathHistory;
  final bool isLoading;
  final String? errorMessage;
  final ViewMode viewMode;
  final SortMode sortMode;
  final bool sortAscending;
  final Set<String> selectedFiles;
  final bool isSelectionMode;

  const FileManagerState({
    this.files = const [],
    this.currentPath = '',
    this.pathHistory = const [],
    this.isLoading = false,
    this.errorMessage,
    this.viewMode = ViewMode.list,
    this.sortMode = SortMode.name,
    this.sortAscending = true,
    this.selectedFiles = const {},
    this.isSelectionMode = false,
  });

  FileManagerState copyWith({
    List<UniversalFile>? files,
    String? currentPath,
    List<String>? pathHistory,
    bool? isLoading,
    String? errorMessage,
    ViewMode? viewMode,
    SortMode? sortMode,
    bool? sortAscending,
    Set<String>? selectedFiles,
    bool? isSelectionMode,
  }) {
    return FileManagerState(
      files: files ?? this.files,
      currentPath: currentPath ?? this.currentPath,
      pathHistory: pathHistory ?? this.pathHistory,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      viewMode: viewMode ?? this.viewMode,
      sortMode: sortMode ?? this.sortMode,
      sortAscending: sortAscending ?? this.sortAscending,
      selectedFiles: selectedFiles ?? this.selectedFiles,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
    );
  }
}
