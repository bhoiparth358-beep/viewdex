import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'file_system_repository.dart';
import '../domain/universal_file.dart';
import '../../../core/errors/result.dart';
import '../../../core/file_detection/file_type_detector.dart';
import '../../../core/logging/app_logger.dart';

class PlatformFileSystem implements FileSystemRepository {
  final FileTypeDetector _fileTypeDetector;

  PlatformFileSystem(this._fileTypeDetector);

  @override
  Future<Result<List<UniversalFile>>> listDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        return Failure(FileError('Directory not found: $path'));
      }

      final entities = await dir.list().toList();
      final files = <UniversalFile>[];

      for (final entity in entities) {
        try {
          final file = await _entityToUniversalFile(entity);
          files.add(file);
        } catch (e) {
          // Skip files we can't read (permission denied, etc.)
          AppLogger.warning('Skipping unreadable entity: ${entity.path}', tag: 'FileSystem');
        }
      }

      // Sort: folders first, then by name
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      return Success(files);
    } catch (e) {
      AppLogger.error('Failed to list directory: $path', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to list directory: ${e.toString()}', e));
    }
  }

  @override
  Future<Result<UniversalFile>> getFileInfo(String path) async {
    try {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.notFound) {
        return Failure(FileError('File not found: $path'));
      }

      final entity = type == FileSystemEntityType.directory
          ? Directory(path) as FileSystemEntity
          : File(path) as FileSystemEntity;
      final file = await _entityToUniversalFile(entity);
      return Success(file);
    } catch (e) {
      AppLogger.error('Failed to get file info: $path', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to get file info: ${e.toString()}', e));
    }
  }

  @override
  Future<Result<void>> createDirectory(String path) async {
    try {
      await Directory(path).create(recursive: true);
      return const Success(null);
    } catch (e) {
      AppLogger.error('Failed to create directory: $path', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to create directory: ${e.toString()}', e));
    }
  }

  @override
  Future<Result<void>> deleteFile(String path) async {
    try {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(path).delete();
      } else if (type == FileSystemEntityType.link) {
        await Link(path).delete();
      } else {
        return Failure(FileError('Path not found: $path'));
      }
      return const Success(null);
    } catch (e) {
      AppLogger.error('Failed to delete: $path', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to delete: ${e.toString()}', e));
    }
  }

  @override
  Future<Result<void>> renameFile(String oldPath, String newPath) async {
    try {
      final type = await FileSystemEntity.type(oldPath);
      if (type == FileSystemEntityType.directory) {
        await Directory(oldPath).rename(newPath);
      } else if (type == FileSystemEntityType.file) {
        await File(oldPath).rename(newPath);
      } else {
        return Failure(FileError('Path not found: $oldPath'));
      }
      return const Success(null);
    } catch (e) {
      AppLogger.error('Failed to rename $oldPath to $newPath', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to rename: ${e.toString()}', e));
    }
  }

  @override
  Future<Result<void>> copyFile(String sourcePath, String destPath) async {
    try {
      final type = await FileSystemEntity.type(sourcePath);
      if (type == FileSystemEntityType.file) {
        await File(sourcePath).copy(destPath);
      } else if (type == FileSystemEntityType.directory) {
        await _copyDirectory(Directory(sourcePath), Directory(destPath));
      } else {
        return Failure(FileError('Source not found: $sourcePath'));
      }
      return const Success(null);
    } catch (e) {
      AppLogger.error('Failed to copy $sourcePath to $destPath', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to copy: ${e.toString()}', e));
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final destPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  @override
  Future<Result<void>> moveFile(String sourcePath, String destPath) async {
    try {
      // Try rename first (fast, same filesystem)
      final renameResult = await renameFile(sourcePath, destPath);
      if (renameResult.isSuccess) return renameResult;

      // Fallback to copy + delete
      final copyResult = await copyFile(sourcePath, destPath);
      if (copyResult.isFailure) return copyResult;
      return await deleteFile(sourcePath);
    } catch (e) {
      AppLogger.error('Failed to move $sourcePath to $destPath', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to move: ${e.toString()}', e));
    }
  }

  @override
  Future<Result<bool>> exists(String path) async {
    try {
      final type = await FileSystemEntity.type(path);
      return Success(type != FileSystemEntityType.notFound);
    } catch (e) {
      AppLogger.error('Failed to check exists: $path', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to check existence: ${e.toString()}', e));
    }
  }

  @override
  Future<Result<String>> getStorageRoot() async {
    try {
      if (Platform.isAndroid) {
        return const Success('/storage/emulated/0');
      } else if (Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        return Success(dir.path);
      }
      return Success(Directory.current.path);
    } catch (e) {
      AppLogger.error('Failed to get storage root', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to get storage root: ${e.toString()}', e));
    }
  }

  static const MethodChannel _storageChannel =
      MethodChannel('com.viewdex.app/storage');

  @override
  Future<Result<StorageInfo>> getStorageInfo() async {
    try {
      if (Platform.isAndroid) {
        final Map<dynamic, dynamic>? res =
            await _storageChannel.invokeMethod('getStorageInfo');
        if (res != null) {
          final total = (res['totalBytes'] as num?)?.toInt() ?? 0;
          final used = (res['usedBytes'] as num?)?.toInt() ?? 0;
          final free = (res['freeBytes'] as num?)?.toInt() ?? 0;
          if (total > 0) {
            return Success(StorageInfo(
              totalBytes: total,
              usedBytes: used,
              freeBytes: free,
            ));
          }
        }
      }
      return const Success(StorageInfo(
        totalBytes: 128 * 1024 * 1024 * 1024,
        usedBytes: 64 * 1024 * 1024 * 1024,
        freeBytes: 64 * 1024 * 1024 * 1024,
      ));
    } catch (e) {
      AppLogger.error('Failed to get storage info', tag: 'FileSystem', error: e);
      return Failure(FileError('Failed to get storage info: ${e.toString()}', e));
    }
  }

  Future<UniversalFile> _entityToUniversalFile(FileSystemEntity entity) async {
    final stat = await entity.stat();
    final name = p.basename(entity.path);
    final isDir = entity is Directory;
    final ext = isDir ? null : p.extension(name).replaceFirst('.', '');

    String? mimeType;
    FileType fileType;

    if (isDir) {
      fileType = FileType.folder;
    } else {
      mimeType = lookupMimeType(entity.path);
      fileType = _fileTypeDetector.detectType(entity.path, mimeType: mimeType);
    }

    return UniversalFile(
      name: name,
      path: entity.path,
      extension: ext,
      mimeType: mimeType,
      size: stat.size,
      modifiedDate: stat.modified,
      fileType: fileType,
      isDirectory: isDir,
    );
  }
}
