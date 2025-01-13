import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../resources/designs/app_colors.dart';

class UpdatePromptDialog extends StatelessWidget {
  final String currentVersion;
  final String newVersion;
  final List<String> changelogs;
  final VoidCallback onUpdate;

  const UpdatePromptDialog({
    Key? key,
    required this.currentVersion,
    required this.newVersion,
    required this.changelogs,
    required this.onUpdate,
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
          children: [
            // Update Icon with Animation
            TweenAnimationBuilder(
              duration: const Duration(milliseconds: 800),
              tween: Tween<double>(begin: 0, end: 1),
              builder: (context, double value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.lightOrange,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      size: 40,
                      color: AppColors.primaryColor,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Update Available',
              style: GoogleFonts.ubuntu(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            // Version Info
            Text(
              'Version $newVersion',
              style: GoogleFonts.ubuntu(
                fontSize: 16,
                color: AppColors.primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            // Changelogs
            if (changelogs.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: AppColors.lightOrange,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What\'s New:',
                        style: GoogleFonts.ubuntu(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...changelogs.map((log) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '•',
                                  style: TextStyle(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    log,
                                    style: GoogleFonts.ubuntu(
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Buttons
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
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Later',
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
                    onPressed: onUpdate,
                    child: Text(
                      'Update Now',
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
