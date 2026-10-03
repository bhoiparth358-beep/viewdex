enum FileType {
  folder,
  pdf,
  archive,
  document,
  spreadsheet,
  presentation,
  image,
  video,
  audio,
  text,
  unknown
}

class UniversalFile {
  final String name;
  final String path;
  final String? extension;
  final String? mimeType;
  final int size;
  final DateTime? modifiedDate;
  final FileType fileType;
  final bool isDirectory;

  const UniversalFile({
    required this.name,
    required this.path,
    this.extension,
    this.mimeType,
    required this.size,
    this.modifiedDate,
    required this.fileType,
    required this.isDirectory,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  UniversalFile copyWith({
    String? name,
    String? path,
    String? extension,
    String? mimeType,
    int? size,
    DateTime? modifiedDate,
    FileType? fileType,
    bool? isDirectory,
  }) {
    return UniversalFile(
      name: name ?? this.name,
      path: path ?? this.path,
      extension: extension ?? this.extension,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      fileType: fileType ?? this.fileType,
      isDirectory: isDirectory ?? this.isDirectory,
    );
  }
}
