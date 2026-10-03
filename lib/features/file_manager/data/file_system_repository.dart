import '../domain/universal_file.dart';
import '../../../core/errors/result.dart';

class StorageInfo {
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;

  const StorageInfo({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
  });

  double get usagePercent {
    if (totalBytes == 0) return 0.0;
    return (usedBytes / totalBytes) * 100;
  }
}

abstract class FileSystemRepository {
  Future<Result<List<UniversalFile>>> listDirectory(String path);
  Future<Result<UniversalFile>> getFileInfo(String path);
  Future<Result<void>> createDirectory(String path);
  Future<Result<void>> deleteFile(String path);
  Future<Result<void>> renameFile(String oldPath, String newPath);
  Future<Result<void>> copyFile(String sourcePath, String destPath);
  Future<Result<void>> moveFile(String sourcePath, String destPath);
  Future<Result<bool>> exists(String path);
  Future<Result<String>> getStorageRoot();
  Future<Result<StorageInfo>> getStorageInfo();
}
