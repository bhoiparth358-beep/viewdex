import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../file_manager/domain/universal_file.dart';
import '../../file_manager/providers/file_manager_providers.dart';
import '../../../core/errors/result.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchFilterProvider = StateProvider<FileType?>((ref) => null);

final searchResultsProvider = FutureProvider<List<UniversalFile>>((ref) async {
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final filter = ref.watch(searchFilterProvider);

  if (query.length < 2) return const [];

  final repository = ref.read(fileSystemRepositoryProvider);
  final detector = ref.read(fileTypeDetectorProvider);
  final rootResult = await repository.getStorageRoot();

  String rootPath;
  if (rootResult is Success<String>) {
    rootPath = rootResult.data;
  } else {
    return const [];
  }

  final results = <UniversalFile>[];

  Future<void> searchDirectory(Directory dir) async {
    if (results.length >= 50) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (results.length >= 50) return;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;

        if (entity is Directory) {
          if (name.toLowerCase().contains(query)) {
            results.add(UniversalFile(
              name: name,
              path: entity.path,
              size: 0,
              fileType: FileType.folder,
              isDirectory: true,
            ));
          }
          await searchDirectory(entity);
        } else if (entity is File) {
          if (name.toLowerCase().contains(query)) {
            final ext = name.contains('.') ? name.split('.').last : null;
            final fileType = detector.detectType(entity.path);
            if (filter == null || fileType == filter) {
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
            }
          }
        }
      }
    } catch (_) {
      // Skip unreadable directories
    }
  }

  await searchDirectory(Directory(rootPath));
  return results;
});
