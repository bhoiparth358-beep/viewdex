import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/router.dart';
import '../../../core/file_detection/file_type_detector.dart';
import '../domain/universal_file.dart';

class FileOpenHandler {
  const FileOpenHandler._();

  /// Opens a file from a string file path (e.g. from external intent or recents).
  static void openFilePath(BuildContext context, String path) {
    final name = p.basename(path);
    final file = File(path);
    final exists = file.existsSync();
    final detector = DefaultFileTypeDetector();
    final type = detector.detectType(path);
    final ext = name.contains('.') ? name.split('.').last : null;
    final size = exists ? file.statSync().size : 0;

    final uFile = UniversalFile(
      name: name,
      path: path,
      extension: ext,
      size: size,
      fileType: type,
      isDirectory: false,
    );
    openFile(context, uFile);
  }

  static void openFile(BuildContext context, UniversalFile file) {
    if (file.fileType == FileType.folder) {
      return;
    }

    // Record in recent files
    SharedPreferences.getInstance().then((prefs) {
      final list = prefs.getStringList('recent_files') ?? [];
      final updated = [file.path, ...list.where((p) => p != file.path)];
      if (updated.length > 50) updated.removeLast();
      prefs.setStringList('recent_files', updated);
    }).catchError((_) {});

    final ext = file.extension?.toLowerCase() ??
        _extractExtension(file.name);

    // In-app PDF Viewer
    if (ext == 'pdf' || file.fileType == FileType.pdf) {
      context.push('/viewer/pdf', extra: file.path);
      return;
    }

    // In-app DOCX Word Document Viewer
    if (ext == 'docx') {
      context.push('/viewer/docx', extra: file.path);
      return;
    }

    // In-app XLSX Excel Spreadsheet Viewer
    if (ext == 'xlsx' || ext == 'xls' || file.fileType == FileType.spreadsheet) {
      context.push('/viewer/xlsx', extra: file.path);
      return;
    }

    // In-app PPTX PowerPoint Presentation Viewer
    if (ext == 'pptx' || ext == 'ppt' || file.fileType == FileType.presentation) {
      context.push('/viewer/pptx', extra: file.path);
      return;
    }

    // Fallback for other generic documents (ODT, RTF, etc.)
    if (file.fileType == FileType.document) {
      OpenFilex.open(file.path).then((result) {
        if (result.type != ResultType.done && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not open $ext file: ${result.message}. Try installing an Office app.',
              ),
            ),
          );
        }
      });
      return;
    }

    final route = AppRouter.viewerRouteForFileType(
      file.fileType,
      extension: ext,
    );

    if (file.fileType == FileType.video) {
      context.push(route, extra: {'path': file.path, 'isAudio': false});
    } else {
      context.push(route, extra: file.path);
    }
  }

  /// Extracts extension from filename when [UniversalFile.extension] is null.
  static String _extractExtension(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < name.length - 1) {
      return name.substring(dotIndex + 1).toLowerCase();
    }
    return '';
  }
}
