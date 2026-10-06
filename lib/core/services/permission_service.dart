import 'dart:io';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../logging/app_logger.dart';

class PermissionService {
  Future<bool> requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        // Android 11+ (API 30+): request "All files access" (MANAGE_EXTERNAL_STORAGE)
        final manageStatus =
            await ph.Permission.manageExternalStorage.request();
        if (manageStatus.isGranted) return true;

        // Fallback for Android 10 and older
        final storageStatus = await ph.Permission.storage.request();
        return storageStatus.isGranted;
      } else if (Platform.isIOS) {
        return true;
      }
      return true;
    } catch (e) {
      AppLogger.error('Failed to request storage permission',
          tag: 'Permission', error: e);
      return false;
    }
  }

  Future<bool> hasStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        final manageGranted =
            await ph.Permission.manageExternalStorage.isGranted;
        if (manageGranted) return true;

        final storageGranted = await ph.Permission.storage.isGranted;
        return storageGranted;
      } else if (Platform.isIOS) {
        return true;
      }
      return true;
    } catch (e) {
      AppLogger.error('Failed to check storage permission',
          tag: 'Permission', error: e);
      return false;
    }
  }

  Future<void> openAppSettings() async {
    try {
      await ph.openAppSettings();
    } catch (e) {
      AppLogger.error('Failed to open app settings',
          tag: 'Permission', error: e);
    }
  }
}
