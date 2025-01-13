import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'models/latest_version_fetch_model.dart';

class LatestVersionFetch {
  final String url =
      "https://raw.githubusercontent.com/sagarchaulagai/aradia-updates/refs/heads/main/latest_version.txt";
  static const platform = MethodChannel('app_update_channel');

  Future<Either<String, LatestVersionFetchModel>> getLatestVersion() async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return Right(LatestVersionFetchModel.fromJson(json));
      } else {
        return Left("Failed to fetch latest version");
      }
    } catch (e) {
      return Left("Failed to fetch latest version");
    }
  }

  Future<String?> getApkPath(String version) async {
    final directory = await getExternalStorageDirectory();
    final file = File('${directory!.path}/$version.apk');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  Future<bool> downloadUpdate(String version) async {
    final String apkUrl =
        "https://raw.githubusercontent.com/sagarchaulagai/aradia-updates/refs/heads/main/$version/app-release.apk";

    try {
      final response = await http.get(Uri.parse(apkUrl));
      if (response.statusCode == 200) {
        final directory = await getExternalStorageDirectory();
        final file = File('${directory!.path}/$version.apk');
        await file.writeAsBytes(response.bodyBytes);
        return true;
      }
      return false;
    } catch (e) {
      print('Error downloading update: $e');
      return false;
    }
  }

  Future<void> installUpdate(String version) async {
    try {
      final apkPath = await getApkPath(version);
      if (apkPath != null) {
        // Try to install using custom method channel first
        try {
          await platform.invokeMethod('installApk', {'apkPath': apkPath});
          return;
        } catch (e) {
          print('Method channel failed, trying OpenFile: $e');
        }

        // Fallback to OpenFile
        final result = await OpenFile.open(apkPath);
        if (result.type != ResultType.done) {
          print('OpenFile error: ${result.message}');
        }
      }
    } catch (e) {
      print('Installation error: $e');
    }
  }
}
