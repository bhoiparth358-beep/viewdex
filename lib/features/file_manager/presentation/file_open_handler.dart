import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/router.dart';
import '../domain/universal_file.dart';

class FileOpenHandler {
  const FileOpenHandler._();

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

    if (file.fileType == FileType.document ||
        file.fileType == FileType.spreadsheet ||
        file.fileType == FileType.presentation) {
      OpenFilex.open(file.path).then((result) {
        if (result.type != ResultType.done && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open file: ${result.message}')),
          );
        }
      });
      return;
    }

    final route = AppRouter.viewerRouteForFileType(file.fileType);

    if (file.fileType == FileType.video) {
      context.push(route, extra: {'path': file.path, 'isAudio': false});
    } else {
      context.push(route, extra: file.path);
    }
  }
}
