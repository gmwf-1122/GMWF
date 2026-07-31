// lib/services/auto_update_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:open_filex/open_filex.dart';

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
  static const String currentVersion = '1.2.9';

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

  /// Checks Firestore `app_config/version` for available updates with platform-specific fallback.
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
      final releaseNotes = (data['releaseNotes'] ?? 'Bug fixes and performance improvements.').toString();
      final forceUpdateFlag = data['forceUpdate'] as bool? ?? false;

      // Check platform-specific download URLs first, fallback to generic downloadUrl
      String rawUrl = '';
      if (defaultTargetPlatform == TargetPlatform.windows) {
        rawUrl = (data['windowsDownloadUrl'] ?? data['downloadUrl'] ?? '').toString();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        rawUrl = (data['androidDownloadUrl'] ?? data['downloadUrl'] ?? '').toString();
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        rawUrl = (data['macOSDownloadUrl'] ?? data['downloadUrl'] ?? '').toString();
      } else {
        rawUrl = (data['downloadUrl'] ?? '').toString();
      }

      // Sanitize URL if Firestore has cross-platform extension mismatch
      String downloadUrl = rawUrl;
      final cleanTag = latestVersion.startsWith('v') ? latestVersion : 'v$latestVersion';
      if (defaultTargetPlatform == TargetPlatform.windows && downloadUrl.toLowerCase().endsWith('.apk')) {
        downloadUrl = 'https://github.com/$defaultRepoOwner/$defaultRepoName/releases/download/$cleanTag/GMWF-v$latestVersion.exe';
      } else if (defaultTargetPlatform == TargetPlatform.android && downloadUrl.toLowerCase().endsWith('.exe')) {
        downloadUrl = 'https://github.com/$defaultRepoOwner/$defaultRepoName/releases/download/$cleanTag/GMWF-v$latestVersion.apk';
      }

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
        'User-Agent': 'GMWF-App/1.0',
        if (personalAccessToken != null && personalAccessToken.isNotEmpty)
          'Authorization': 'Bearer $personalAccessToken',
      };

      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawTag = (data['tag_name'] ?? '').toString();
        final tag = rawTag.replaceAll('v', '');
        final notes = (data['body'] ?? 'Performance improvements and security updates.').toString();

        String downloadUrl = '';
        final assets = data['assets'] as List?;
        if (assets != null && assets.isNotEmpty) {
          if (defaultTargetPlatform == TargetPlatform.android) {
            // Pick standard APK asset over 32-bit if multiple exist
            final apkAssets = assets.where(
              (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.apk'),
            ).toList();

            if (apkAssets.isNotEmpty) {
              final preferredApk = apkAssets.firstWhere(
                (a) => !(a['name'] ?? '').toString().toLowerCase().contains('-32bit'),
                orElse: () => apkAssets.first,
              );
              downloadUrl = (preferredApk['browser_download_url'] ?? preferredApk['url'] ?? '').toString();
            }
          } else if (defaultTargetPlatform == TargetPlatform.windows) {
            final exeAsset = assets.firstWhere(
              (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.exe') ||
                     (a['name'] ?? '').toString().toLowerCase().endsWith('.msi') ||
                     (a['name'] ?? '').toString().toLowerCase().endsWith('.zip'),
              orElse: () => null,
            );
            if (exeAsset != null) {
              downloadUrl = (exeAsset['browser_download_url'] ?? exeAsset['url'] ?? '').toString();
            }
          } else if (defaultTargetPlatform == TargetPlatform.macOS) {
            final macAsset = assets.firstWhere(
              (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.dmg') ||
                     (a['name'] ?? '').toString().toLowerCase().endsWith('.pkg'),
              orElse: () => null,
            );
            if (macAsset != null) {
              downloadUrl = (macAsset['browser_download_url'] ?? macAsset['url'] ?? '').toString();
            }
          }
        }

        // Direct binary release URL fallback per platform if asset is missing or html URL was returned
        if (downloadUrl.isEmpty || downloadUrl.contains('/releases/tag/') || downloadUrl.endsWith('/releases/latest')) {
          final cleanTag = rawTag.isNotEmpty ? rawTag : 'v$tag';
          if (defaultTargetPlatform == TargetPlatform.android) {
            downloadUrl = 'https://github.com/$repoOwner/$repoName/releases/download/$cleanTag/GMWF-v$tag.apk';
          } else if (defaultTargetPlatform == TargetPlatform.windows) {
            downloadUrl = 'https://github.com/$repoOwner/$repoName/releases/download/$cleanTag/GMWF-v$tag.exe';
          } else {
            downloadUrl = 'https://github.com/$repoOwner/$repoName/releases/download/$cleanTag/GMWF-v$tag.dmg';
          }
        }

        final isHigher = compareVersions(currentVersion, tag) > 0;
        final hasUpdate = isHigher;

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

  /// Opens the installer or update download URL in external application if needed.
  static Future<bool> launchUpdateUrl(String url) async {
    final targetUrl = url.isNotEmpty ? url : 'https://github.com/gmwf-1122/GMWF/releases/latest';
    try {
      final uri = Uri.parse(targetUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[AutoUpdateService] Failed to launch update URL: $e');
    }
    return false;
  }

  /// Downloads binary asset directly using HttpClient (handles HTTP 302/301 redirects and streams to file).
  static Future<File?> _downloadFileWithHttpClient(
    String url,
    String targetFilePath, {
    required Function(double progress, String statusMessage) onProgress,
  }) async {
    try {
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 15);
      httpClient.userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      String currentUrl = url;
      HttpClientResponse? response;
      int redirects = 0;

      while (redirects < 8) {
        final uri = Uri.parse(currentUrl);
        final request = await httpClient.getUrl(uri);
        request.headers.set('User-Agent', 'GMWF-App/1.0 (Windows; Android)');
        request.headers.set('Accept', '*/*');
        request.followRedirects = true;

        response = await request.close();

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers.value('location');
          if (location != null && location.isNotEmpty) {
            currentUrl = Uri.parse(currentUrl).resolve(location).toString();
            redirects++;
            debugPrint('[AutoUpdateService] Following redirect ($redirects) to: $currentUrl');
            continue;
          }
        }
        break;
      }

      if (response == null || response.statusCode != 200) {
        debugPrint('[AutoUpdateService] HTTP Download failed with status: ${response?.statusCode}');
        httpClient.close();
        return null;
      }

      final contentLength = response.contentLength;
      int receivedBytes = 0;
      final file = File(targetFilePath);
      final sink = file.openWrite();

      await response.forEach((chunk) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        if (contentLength > 0) {
          final progress = (receivedBytes / contentLength).clamp(0.0, 1.0);
          final percent = (progress * 100).toInt();
          final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          onProgress(progress, 'Downloading update... $percent% ($mbReceived MB / $mbTotal MB)');
        } else {
          final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress(0.5, 'Downloading update... $mbReceived MB');
        }
      });

      await sink.flush();
      await sink.close();
      httpClient.close();

      return file;
    } catch (e) {
      debugPrint('[AutoUpdateService] Download error: $e');
    }
    return null;
  }

  /// Direct in-app stream download with progress callback and silent installer launch.
  static Future<bool> downloadAndInstallUpdate(
    String downloadUrl, {
    required Function(double progress, String statusMessage) onProgress,
  }) async {
    if (kIsWeb) {
      onProgress(1.0, 'Updates are not applicable for web version.');
      return false;
    }

    String effectiveUrl = downloadUrl;

    // Resolve URL if it's pointing to HTML release tag or empty
    if (effectiveUrl.isEmpty || effectiveUrl.endsWith('/releases/latest') || effectiveUrl.contains('/releases/tag/')) {
      final info = await checkForUpdates();
      if (info != null && info.downloadUrl.isNotEmpty && !info.downloadUrl.contains('/releases/tag/')) {
        effectiveUrl = info.downloadUrl;
      }
    }

    onProgress(0.01, 'Connecting to update server...');

    String fileName = 'GMWF_Setup_Update.exe';
    if (defaultTargetPlatform == TargetPlatform.android) {
      fileName = 'GMWF_Update.apk';
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      fileName = 'GMWF_Update.dmg';
    }

    final tempDir = await getTemporaryDirectory();
    final filePath = path.join(tempDir.path, fileName);

    final downloadedFile = await _downloadFileWithHttpClient(
      effectiveUrl,
      filePath,
      onProgress: onProgress,
    );

    if (downloadedFile == null || !await downloadedFile.exists()) {
      onProgress(0.0, 'Download failed. Please check internet connection.');
      return false;
    }

    onProgress(1.0, 'Installing update... Please wait.');
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        debugPrint('[AutoUpdateService] Launching Windows installer: $filePath');
        bool processStarted = false;
        try {
          // Launch Inno Setup silent installer
          await Process.start(filePath, ['/verysilent', '/suppressmsgboxes', '/norestart', '/sp-']);
          processStarted = true;
        } catch (e) {
          debugPrint('[AutoUpdateService] Process.start failed ($e), attempting OpenFilex launch...');
          final result = await OpenFilex.open(filePath);
          processStarted = result.type == ResultType.done;
        }

        if (processStarted) {
          onProgress(1.0, 'Installer launched! Closing app to complete update...');
          await Future.delayed(const Duration(seconds: 2));
          exit(0);
        } else {
          onProgress(0.0, 'Failed to launch installer. Please run installer manually.');
          return false;
        }
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        debugPrint('[AutoUpdateService] Launching Android Package Installer for: $filePath');
        onProgress(1.0, 'Launching Package Installer...');

        // Trigger native Android installer via FileProvider
        final result = await OpenFilex.open(filePath, type: "application/vnd.android.package-archive");
        debugPrint('[AutoUpdateService] OpenFilex result: ${result.type} - ${result.message}');

        if (result.type == ResultType.done) {
          onProgress(1.0, 'Package installer opened. Complete installation on your screen.');
          return true;
        } else if (result.type == ResultType.permissionDenied) {
          onProgress(0.0, 'Permission denied: Please allow "Install unknown apps" for GMWF in Android settings.');
          // Fallback to opening browser link if permissions block in-app install
          try {
            final uri = Uri.parse(effectiveUrl);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
          return false;
        } else {
          // Fallback to browser URL if direct APK launch fails on older devices
          debugPrint('[AutoUpdateService] OpenFilex failed (${result.message}), opening browser download URL fallback...');
          try {
            final uri = Uri.parse(effectiveUrl);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return true;
          } catch (e) {
            onProgress(0.0, 'Failed to open installer: ${result.message}');
            return false;
          }
        }
      } else {
        final result = await OpenFilex.open(filePath);
        return result.type == ResultType.done;
      }
    } catch (e) {
      debugPrint('[AutoUpdateService] Installation trigger error: $e');
      onProgress(0.0, 'Failed to launch installer: $e');
      return false;
    }
  }

  /// Downloads and executes silent installer for headless server instances.
  static Future<bool> performSilentHeadlessUpdate(String downloadUrl) async {
    if (kIsWeb) return false;
    try {
      debugPrint('[AutoUpdateService] Starting silent headless update from: $downloadUrl');
      final tempDir = await getTemporaryDirectory();
      final filePath = path.join(tempDir.path, 'gmwf_update_installer.exe');

      String effectiveUrl = downloadUrl;
      if (effectiveUrl.isEmpty || effectiveUrl.contains('/releases/tag/') || effectiveUrl.endsWith('/releases/latest')) {
        final info = await checkForUpdates();
        if (info != null && info.downloadUrl.isNotEmpty) {
          effectiveUrl = info.downloadUrl;
        }
      }

      final downloadedFile = await _downloadFileWithHttpClient(
        effectiveUrl,
        filePath,
        onProgress: (progress, statusMessage) {
          debugPrint('[SilentHeadlessUpdate] $statusMessage');
        },
      );

      if (downloadedFile != null && await downloadedFile.exists()) {
        debugPrint('[AutoUpdateService] Silent installer downloaded to: $filePath');
        if (defaultTargetPlatform == TargetPlatform.windows) {
          debugPrint('[AutoUpdateService] Executing Inno Setup silent install flags...');
          await Process.start(filePath, ['/verysilent', '/suppressmsgboxes', '/norestart', '/sp-']);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[AutoUpdateService] Silent headless update failed: $e');
    }
    return false;
  }
}

