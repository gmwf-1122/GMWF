// lib/services/auto_update_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class UpdateInfo {
  final String latestVersion;
  final String minRequiredVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool forceUpdate;
  final bool hasUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.minRequiredVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.forceUpdate,
    required this.hasUpdate,
  });
}

class AutoUpdateService {
  /// Current installed version of the GMWF application.
  static const String currentVersion = '1.2.6';

  /// Default GitHub repository configuration for auto-updates.
  static const String defaultRepoOwner = 'gmwf-1122';
  static const String defaultRepoName = 'GMWF';

  /// Compares two semver strings (e.g. "1.2.4" vs "1.2.5").
  /// Returns 1 if v2 > v1, -1 if v1 > v2, 0 if equal.
  static int compareVersions(String v1, String v2) {
    try {
      final parts1 = v1.replaceAll(RegExp(r'[^\d.]'), '').split('.').map(int.parse).toList();
      final parts2 = v2.replaceAll(RegExp(r'[^\d.]'), '').split('.').map(int.parse).toList();

      final maxLength = parts1.length > parts2.length ? parts1.length : parts2.length;
      for (int i = 0; i < maxLength; i++) {
        final val1 = i < parts1.length ? parts1[i] : 0;
        final val2 = i < parts2.length ? parts2[i] : 0;
        if (val2 > val1) return 1;
        if (val1 > val2) return -1;
      }
    } catch (e) {
      debugPrint('[AutoUpdateService] Version comparison error: $e');
    }
    return 0;
  }

  /// Primary update check method: checks GitHub Releases first, then Firestore fallback.
  static Future<UpdateInfo?> checkForUpdates({
    String? repoOwner,
    String? repoName,
    String? personalAccessToken,
  }) async {
    // Web users run in the browser and do not use binary desktop/mobile installers.
    if (kIsWeb) {
      return null;
    }

    final owner = repoOwner ?? defaultRepoOwner;
    final name = repoName ?? defaultRepoName;

    // 1. Try checking GitHub Releases (gmwf-1122/GMWF)
    final ghInfo = await checkGitHubReleases(
      repoOwner: owner,
      repoName: name,
      personalAccessToken: personalAccessToken,
    );

    if (ghInfo != null) {
      return ghInfo;
    }

    // 2. Fallback to Firestore app_config/version
    return checkFirestoreVersion();
  }

  /// Checks Firestore `app_config/version` for available updates.
  static Future<UpdateInfo?> checkFirestoreVersion() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('version').get();
      if (!doc.exists) {
        debugPrint('[AutoUpdateService] app_config/version document does not exist yet');
        return null;
      }

      final data = doc.data()!;
      final latestVersion = (data['latestVersion'] ?? currentVersion).toString();
      final minRequiredVersion = (data['minRequiredVersion'] ?? currentVersion).toString();
      final downloadUrl = (data['downloadUrl'] ?? '').toString();
      final releaseNotes = (data['releaseNotes'] ?? 'Bug fixes and performance improvements.').toString();
      final forceUpdateFlag = data['forceUpdate'] as bool? ?? false;

      final isHigher = compareVersions(currentVersion, latestVersion) > 0;
      final isMinRequiredHigher = compareVersions(currentVersion, minRequiredVersion) > 0;

      final forceUpdate = forceUpdateFlag || isMinRequiredHigher;

      return UpdateInfo(
        latestVersion: latestVersion,
        minRequiredVersion: minRequiredVersion,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        forceUpdate: forceUpdate,
        hasUpdate: isHigher && downloadUrl.isNotEmpty,
      );
    } catch (e) {
      debugPrint('[AutoUpdateService] Failed to check Firestore version: $e');
    }
    return null;
  }

  /// Checks GitHub Releases API for updates (supports public or private repo with token).
  static Future<UpdateInfo?> checkGitHubReleases({
    required String repoOwner,
    required String repoName,
    String? personalAccessToken,
  }) async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final headers = <String, String>{
        'Accept': 'application/vnd.github.v3+json',
        if (personalAccessToken != null && personalAccessToken.isNotEmpty)
          'Authorization': 'Bearer $personalAccessToken',
      };

      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tag = (data['tag_name'] ?? '').toString().replaceAll('v', '');
        final notes = (data['body'] ?? 'Performance improvements and security updates.').toString();

        String downloadUrl = '';
        final assets = data['assets'] as List?;
        if (assets != null && assets.isNotEmpty) {
          if (defaultTargetPlatform == TargetPlatform.android) {
            // Strictly look for .apk assets on Android
            final apkAsset = assets.firstWhere(
              (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.apk'),
              orElse: () => null,
            );
            if (apkAsset != null) {
              downloadUrl = apkAsset['browser_download_url'] ?? apkAsset['url'] ?? '';
            }
          } else if (defaultTargetPlatform == TargetPlatform.windows) {
            // Strictly look for .exe or .msi assets on Windows Desktop
            final exeAsset = assets.firstWhere(
              (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.exe') ||
                     (a['name'] ?? '').toString().toLowerCase().endsWith('.msi'),
              orElse: () => null,
            );
            if (exeAsset != null) {
              downloadUrl = exeAsset['browser_download_url'] ?? exeAsset['url'] ?? '';
            }
          } else if (defaultTargetPlatform == TargetPlatform.macOS) {
            final macAsset = assets.firstWhere(
              (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.dmg') ||
                     (a['name'] ?? '').toString().toLowerCase().endsWith('.pkg'),
              orElse: () => null,
            );
            if (macAsset != null) {
              downloadUrl = macAsset['browser_download_url'] ?? macAsset['url'] ?? '';
            }
          }
        }

        final isHigher = compareVersions(currentVersion, tag) > 0;
        final hasUpdate = isHigher && downloadUrl.isNotEmpty;

        return UpdateInfo(
          latestVersion: tag,
          minRequiredVersion: currentVersion,
          downloadUrl: downloadUrl,
          releaseNotes: notes,
          forceUpdate: false,
          hasUpdate: hasUpdate,
        );
      }
    } catch (e) {
      debugPrint('[AutoUpdateService] Failed to fetch GitHub Release: $e');
    }
    return null;
  }

  /// Opens the installer or update download URL in the browser / system handler.
  static Future<bool> launchUpdateUrl(String url) async {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[AutoUpdateService] Failed to launch update URL: $e');
    }
    return false;
  }

  /// Direct in-app stream download with progress callback and auto-installer launch.
  static Future<bool> downloadAndInstallUpdate(
    String downloadUrl, {
    required Function(double progress, String statusMessage) onProgress,
  }) async {
    if (downloadUrl.isEmpty) return false;

    if (kIsWeb) {
      return launchUpdateUrl(downloadUrl);
    }

    try {
      onProgress(0.02, 'Connecting to update server...');
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        onProgress(0.0, 'Direct download unavailable. Opening browser...');
        return launchUpdateUrl(downloadUrl);
      }

      final contentLength = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();

      String fileName = 'GMWF_Setup_Update.exe';
      if (defaultTargetPlatform == TargetPlatform.android) {
        fileName = 'GMWF_Update.apk';
      }

      final filePath = path.join(tempDir.path, fileName);
      final file = File(filePath);
      final sink = file.openWrite();

      int receivedBytes = 0;
      await response.stream.forEach((chunk) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        if (contentLength > 0) {
          final progress = (receivedBytes / contentLength).clamp(0.0, 1.0);
          final percent = (progress * 100).toInt();
          final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          onProgress(progress, 'Downloading... $percent% ($mbReceived MB / $mbTotal MB)');
        } else {
          final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress(0.5, 'Downloading... $mbReceived MB');
        }
      });

      await sink.flush();
      await sink.close();
      client.close();

      onProgress(1.0, 'Download finished! Launching installer...');
      await Future.delayed(const Duration(milliseconds: 600));

      if (defaultTargetPlatform == TargetPlatform.windows) {
        debugPrint('[AutoUpdateService] Launching Windows installer: $filePath');
        await Process.start(filePath, []);
        return true;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final fileUri = Uri.file(filePath);
        if (await canLaunchUrl(fileUri)) {
          await launchUrl(fileUri, mode: LaunchMode.externalApplication);
          return true;
        } else {
          return launchUpdateUrl(downloadUrl);
        }
      } else {
        return launchUpdateUrl(downloadUrl);
      }
    } catch (e) {
      debugPrint('[AutoUpdateService] In-app download error: $e. Falling back to browser launch.');
      return launchUpdateUrl(downloadUrl);
    }
  }

  /// Downloads and executes silent installer for headless server instances.
  static Future<bool> performSilentHeadlessUpdate(String downloadUrl) async {
    if (downloadUrl.isEmpty || kIsWeb) return false;
    try {
      debugPrint('[AutoUpdateService] Starting silent headless update from: $downloadUrl');
      final tempDir = await getTemporaryDirectory();
      final filePath = path.join(tempDir.path, 'gmwf_update_installer.exe');
      final file = File(filePath);

      final res = await http.get(Uri.parse(downloadUrl)).timeout(const Duration(minutes: 5));
      if (res.statusCode == 200) {
        await file.writeAsBytes(res.bodyBytes);
        debugPrint('[AutoUpdateService] Silent installer downloaded to: $filePath');

        if (defaultTargetPlatform == TargetPlatform.windows) {
          debugPrint('[AutoUpdateService] Executing Inno Setup silent install flags...');
          // /verysilent runs installer silently, replaces gmwf.exe & dlls, and launches app
          await Process.start(filePath, ['/verysilent', '/suppressmsgboxes']);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[AutoUpdateService] Silent headless update failed: $e');
    }
    return false;
  }
}
