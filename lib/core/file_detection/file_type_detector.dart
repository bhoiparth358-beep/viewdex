import '../../features/file_manager/domain/universal_file.dart';

abstract class FileTypeDetector {
  FileType detectType(String path, {String? mimeType});
}

class DefaultFileTypeDetector implements FileTypeDetector {
  static const Map<String, FileType> _extensionMap = {
    // PDF
    'pdf': FileType.pdf,
    
    // Archives
    'zip': FileType.archive,
    '7z': FileType.archive,
    'rar': FileType.archive,
    'tar': FileType.archive,
    'gz': FileType.archive,
    'tgz': FileType.archive,
    'bz2': FileType.archive,
    'xz': FileType.archive,
    
    // Documents
    'doc': FileType.document,
    'docx': FileType.document,
    'rtf': FileType.document,
    'odt': FileType.document,
    
    // Spreadsheets
    'xls': FileType.spreadsheet,
    'xlsx': FileType.spreadsheet,
    'ods': FileType.spreadsheet,
    'csv': FileType.spreadsheet,
    
    // Presentations
    'ppt': FileType.presentation,
    'pptx': FileType.presentation,
    'odp': FileType.presentation,
    
    // Images
    'jpg': FileType.image,
    'jpeg': FileType.image,
    'png': FileType.image,
    'gif': FileType.image,
    'bmp': FileType.image,
    'webp': FileType.image,
    'svg': FileType.image,
    'heic': FileType.image,
    'tiff': FileType.image,
    
    // Video
    'mp4': FileType.video,
    'avi': FileType.video,
    'mkv': FileType.video,
    'mov': FileType.video,
    'wmv': FileType.video,
    'flv': FileType.video,
    'webm': FileType.video,
    
    // Audio
    'mp3': FileType.audio,
    'wav': FileType.audio,
    'flac': FileType.audio,
    'm4a': FileType.audio,
    'aac': FileType.audio,
    'ogg': FileType.audio,
    
    // Text
    'txt': FileType.text,
    'md': FileType.text,
    'json': FileType.text,
    'xml': FileType.text,
    'html': FileType.text,
    'css': FileType.text,
    'dart': FileType.text,
    'yaml': FileType.text,
    'yml': FileType.text,
    'log': FileType.text,
  };

  @override
  FileType detectType(String path, {String? mimeType}) {
    final lastDotIndex = path.lastIndexOf('.');
    if (lastDotIndex != -1 && lastDotIndex < path.length - 1) {
      final extension = path.substring(lastDotIndex + 1).toLowerCase();
      if (_extensionMap.containsKey(extension)) {
        return _extensionMap[extension]!;
      }
    }

    if (mimeType != null) {
      final mimeTypeLower = mimeType.toLowerCase();
      if (mimeTypeLower.startsWith('image/')) return FileType.image;
      if (mimeTypeLower.startsWith('video/')) return FileType.video;
      if (mimeTypeLower.startsWith('audio/')) return FileType.audio;
      if (mimeTypeLower.startsWith('text/')) return FileType.text;
      if (mimeTypeLower == 'application/pdf') return FileType.pdf;
      if (mimeTypeLower.contains('zip') || mimeTypeLower.contains('archive')) return FileType.archive;
    }

    return FileType.unknown;
  }
}
