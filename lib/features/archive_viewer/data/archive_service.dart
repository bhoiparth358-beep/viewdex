import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/errors/result.dart';

class ArchiveEntry {
  final String name;
  final int size;
  final bool isDirectory;
  final int compressedSize;
  final DateTime? lastModified;

  const ArchiveEntry({
    required this.name,
    required this.size,
    required this.isDirectory,
    required this.compressedSize,
    this.lastModified,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class ArchiveService {
  static const int _maxTotalSize = 2 * 1024 * 1024 * 1024; // 2 GB limit
  static const int _maxSingleFileSize = 500 * 1024 * 1024; // 500 MB limit

  Future<Result<List<ArchiveEntry>>> listContents(String archivePath) async {
    try {
      final file = File(archivePath);
      if (!await file.exists()) {
        return Failure(ArchiveError('File not found: $archivePath'));
      }

      final bytes = await file.readAsBytes();
      final archive = _decodeArchive(archivePath, bytes);
      if (archive == null) {
        return Failure(
            ArchiveError('Unsupported archive format: ${p.extension(archivePath)}'));
      }

      final entries = archive.map((e) {
        return ArchiveEntry(
          name: e.name,
          size: e.size,
          isDirectory: !e.isFile,
          compressedSize: e.size,
          lastModified: DateTime.fromMillisecondsSinceEpoch(
              e.lastModTime * 1000),
        );
      }).toList();

      return Success(entries);
    } catch (e) {
      return Failure(ArchiveError('Failed to list archive contents: $e'));
    }
  }

  Future<Result<void>> extractAll(
      String archivePath, String destinationPath) async {
    try {
      final file = File(archivePath);
      final bytes = await file.readAsBytes();

      final archive = _decodeArchive(archivePath, bytes);
      if (archive == null) {
        return const Failure(ArchiveError('Unsupported archive format'));
      }

      // Security check: Zip-Slip & Decompression Bomb
      final destCanonical = p.canonicalize(destinationPath);
      int totalUncompressedSize = 0;

      for (final entry in archive) {
        if (!entry.isFile) continue;

        totalUncompressedSize += entry.size;
        if (entry.size > _maxSingleFileSize || totalUncompressedSize > _maxTotalSize) {
          return const Failure(ArchiveError(
              'Security error: Archive exceeds maximum allowed decompressed size (potential decompression bomb).'));
        }

        final targetPath = p.canonicalize(p.join(destinationPath, entry.name));
        if (!targetPath.startsWith(destCanonical)) {
          return Failure(ArchiveError(
              'Security error: Path traversal attempt detected ("${entry.name}").'));
        }
      }

      extractArchiveToDisk(archive, destinationPath);
      return const Success(null);
    } catch (e) {
      return Failure(ArchiveError('Failed to extract archive: $e'));
    }
  }

  Future<Result<void>> extractFile(
      String archivePath, String entryName, String destinationPath) async {
    try {
      final file = File(archivePath);
      final bytes = await file.readAsBytes();

      final archive = _decodeArchive(archivePath, bytes);
      if (archive == null) {
        return const Failure(ArchiveError('Unsupported archive format'));
      }

      final fileToExtract = archive.findFile(entryName);
      if (fileToExtract == null) {
        return Failure(ArchiveError('Entry not found: $entryName'));
      }

      // Security checks
      if (fileToExtract.size > _maxSingleFileSize) {
        return const Failure(ArchiveError('Security error: File exceeds maximum allowed size.'));
      }

      final destCanonical = p.canonicalize(destinationPath);
      final targetPath = p.canonicalize(p.join(destinationPath, entryName));
      if (!targetPath.startsWith(destCanonical)) {
        return Failure(ArchiveError('Security error: Path traversal attempt detected ("$entryName").'));
      }

      final outFile = File(targetPath);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(fileToExtract.content as List<int>);

      return const Success(null);
    } catch (e) {
      return Failure(ArchiveError('Failed to extract file: $e'));
    }
  }

  Future<Result<String>> createZip(
      List<String> sourcePaths, String destZipPath) async {
    try {
      final archive = Archive();

      for (final srcPath in sourcePaths) {
        final entity = FileSystemEntity.typeSync(srcPath);
        final baseName = p.basename(srcPath);

        if (entity == FileSystemEntityType.file) {
          final file = File(srcPath);
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(baseName, bytes.length, bytes));
        } else if (entity == FileSystemEntityType.directory) {
          final dir = Directory(srcPath);
          final parentLength = dir.parent.path.length + 1;

          await for (final item in dir.list(recursive: true, followLinks: false)) {
            if (item is File) {
              final relativePath = item.path.substring(parentLength);
              final bytes = await item.readAsBytes();
              archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
            }
          }
        }
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        return const Failure(ArchiveError('Failed to encode ZIP archive.'));
      }

      final outFile = File(destZipPath);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(zipData);

      return Success(destZipPath);
    } catch (e) {
      return Failure(ArchiveError('Failed to create ZIP archive: $e'));
    }
  }

  Future<Result<String>> extractToTemp(String archivePath, String entryName) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'viewdex_archive_preview'));
      await cacheDir.create(recursive: true);

      final extractResult = await extractFile(archivePath, entryName, cacheDir.path);
      if (extractResult is Failure<void>) {
        return Failure(extractResult.error);
      }

      return Success(p.join(cacheDir.path, entryName));
    } catch (e) {
      return Failure(ArchiveError('Failed to extract temporary preview file: $e'));
    }
  }

  Archive? _decodeArchive(String archivePath, List<int> bytes) {
    final ext = p.extension(archivePath).toLowerCase();
    final lowerPath = archivePath.toLowerCase();

    if (ext == '.zip') {
      return ZipDecoder().decodeBytes(bytes);
    } else if (ext == '.tar') {
      return TarDecoder().decodeBytes(bytes);
    } else if (lowerPath.endsWith('.tar.gz') || lowerPath.endsWith('.tgz')) {
      final gzipBytes = GZipDecoder().decodeBytes(bytes);
      return TarDecoder().decodeBytes(gzipBytes);
    }
    return null;
  }
}
