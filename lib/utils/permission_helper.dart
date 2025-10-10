import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../resources/designs/app_colors.dart';

@immutable
class PermissionHelper {
  const PermissionHelper._();

  static Future<bool> requestStorageAndMediaPermissions() async {
    PermissionStatus storageStatus;
    PermissionStatus photoStatus;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        photoStatus = await Permission.photos.status;
        if (!photoStatus.isGranted) {
          photoStatus = await Permission.photos.request();
        }

        return photoStatus.isGranted;
      } else {
        storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          storageStatus = await Permission.storage.request();
        }
        return storageStatus.isGranted;
      }
    } else if (Platform.isIOS) {
      photoStatus = await Permission.photos.status;
      if (!photoStatus.isGranted) {
        photoStatus = await Permission.photos.request();
      }

      return photoStatus.isGranted;
    }
    return true;
  }

  static Future<PermissionStatus> getInstallPackagesPermissionStatus() async {
    if (Platform.isAndroid) {
      return await Permission.requestInstallPackages.status;
    }
    return PermissionStatus.granted;
  }

  static Future<PermissionStatus> requestInstallPackagesPermission() async {
    if (Platform.isAndroid) {
      return await Permission.requestInstallPackages.request();
    }
    return PermissionStatus.granted;
  }

  static Future<bool> openAppSettingsPage() async {
    return await openAppSettings();
  }

  /// Download permission handler for different Android API levels
  /// Returns true if all required permissions are granted
  static Future<bool> requestDownloadPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        // Android 13+ (API 33+) - Request notification permission for download notifications
        final notification = await Permission.notification.status;
        if (notification.isDenied) {
          final result = await Permission.notification.request();
          return result.isGranted;
        }
        return notification.isGranted;
      } else if (sdkInt >= 30) {
        // Android 10-12 (API 30-32) - No storage permissions needed for MediaStore
        // Files will be downloaded to temp directory then moved via MediaStore
        return true;
      } else {
        // Android 9 and below (API 28 and below) - Request WRITE_EXTERNAL_STORAGE
        final storage = await Permission.storage.status;
        if (storage.isDenied) {
          final result = await Permission.storage.request();
          return result.isGranted;
        }
        return storage.isGranted;
      }
    }
    return true; // iOS or other platforms
  }

  /// Shows a user-friendly permission dialog for download permissions
  /// Returns true if user grants permission, false otherwise
  static Future<bool> handleDownloadPermissionWithDialog(
      BuildContext context) async {
    final hasPermission = await requestDownloadPermissions();

    if (hasPermission) {
      return true;
    }

    // Show dialog to explain why we need permissions
    if (!context.mounted) return false;

    // Determine which permission is needed based on Android version
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    final isNotificationPermission = sdkInt >= 33;

    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              isNotificationPermission ? Icons.notifications_rounded : Icons.download_rounded,
              color: AppColors.primaryColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(isNotificationPermission ? 'Notification Permission Required' : 'Storage Permission Required'),
          ],
        ),
        content: Text(
          isNotificationPermission 
            ? 'To show download progress and completion notifications, we need notification permission.'
            : 'For the app to function properly, we need access to your device storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (shouldOpenSettings == true) {
      await openAppSettings();
    }

    return false;
  }

  /// Handles checking and requesting install packages permission with a dialog UI
  /// Returns true if permission is granted and update can proceed
  static Future<bool> handleUpdatePermission(BuildContext context) async {
    final permissionStatus = await Permission.requestInstallPackages.status;

    if (permissionStatus.isGranted) {
      return true;
    } else {
      if (!context.mounted) return false;

      final shouldRequestPermission = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => PermissionDialog(
          onContinue: () => Navigator.of(context).pop(true),
          onNotNow: () => Navigator.of(context).pop(false),
        ),
      );

      if (shouldRequestPermission == true) {
        final newPermissionStatus =
            await Permission.requestInstallPackages.request();

        if (newPermissionStatus.isGranted) {
          return true;
        } else if (newPermissionStatus.isDenied ||
            newPermissionStatus.isPermanentlyDenied) {
          // Re-prompt with dialog offering to go to settings
          if (!context.mounted) return false;

          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => PermissionDialog(
              onContinue: () async {
                Navigator.of(context).pop(true);
              },
              onNotNow: () => Navigator.of(context).pop(false),
            ),
          );

          if (shouldOpenSettings == true) {
            await openAppSettings();
          }
          return false;
        }
      }
      return false;
    }
  }
}

/// Dialog for requesting installation permission
class PermissionDialog extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onNotNow;

  const PermissionDialog({
    super.key,
    required this.onContinue,
    required this.onNotNow,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryColor.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightOrange,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.security_rounded,
                size: 40,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Text(
                'Permission Required',
                textAlign: TextAlign.center,
                style: GoogleFonts.ubuntu(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'To keep your app up-to-date with the latest features and improvements, we need permission to install updates.',
              textAlign: TextAlign.center,
              style: GoogleFonts.ubuntu(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: AppColors.primaryColor,
                    ),
                    onPressed: onNotNow,
                    child: Text(
                      'Not Now',
                      style: GoogleFonts.ubuntu(
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onContinue,
                    child: Text(
                      'Continue',
                      style: GoogleFonts.ubuntu(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
