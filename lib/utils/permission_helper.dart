import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show immutable;
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
  
  /// Handles checking and requesting install packages permission with a dialog UI
  /// Returns true if permission is granted and update can proceed
  static Future<bool> handleUpdatePermission(BuildContext context) async {
    final permissionStatus = await Permission.requestInstallPackages.status;

    if (permissionStatus.isGranted) {
      return true;
    } else {
      final shouldRequestPermission = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => PermissionDialog(
          onContinue: () => Navigator.of(context).pop(true),
          onNotNow: () => Navigator.of(context).pop(false),
        ),
      );

      if (shouldRequestPermission == true) {
        final newPermissionStatus = await Permission.requestInstallPackages.request();
        
        if (newPermissionStatus.isGranted) {
          return true;
        } else if (newPermissionStatus.isDenied || newPermissionStatus.isPermanentlyDenied) {
          // Re-prompt with dialog offering to go to settings
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
    Key? key,
    required this.onContinue,
    required this.onNotNow,
  }) : super(key: key);

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