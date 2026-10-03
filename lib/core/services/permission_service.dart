import 'dart:io';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../logging/app_logger.dart';

class PermissionService {
  Future<bool> requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        // Try MANAGE_EXTERNAL_STORAGE first (Android 11+)
        final manageStatus =
            await ph.Permission.manageExternalStorage.request();
        if (manageStatus.isGranted) return true;

        // Fall back to regular storage permission
        final storageStatus = await ph.Permission.storage.request();
        return storageStatus.isGranted;
      } else if (Platform.isIOS) {
        // iOS uses document picker, no broad storage permission needed
        return true;
      }
      return true; // Desktop: permissions usually implicit
    } catch (e) {
      AppLogger.error('Failed to request storage permission',
          tag: 'Permission', error: e);
      return false;
    }
  }

  Future<bool> hasStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        if (await ph.Permission.manageExternalStorage.isGranted) return true;
        return await ph.Permission.storage.isGranted;
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
