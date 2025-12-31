import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static const String versionUrl =
      'https://raw.githubusercontent.com/Amirchelios/NG_manager/refs/heads/main/version.txt';
  static const String adminUrl =
      'https://raw.githubusercontent.com/Amirchelios/NG_manager/refs/heads/main/admin.txt';

  Future<String?> _fetchRemoteVersion() async {
    try {
      final response = await http
          .get(Uri.parse(versionUrl))
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw Exception('Network timeout');
            },
          );
      if (response.statusCode != 200) {
        return null;
      }
      final version = response.body.trim();
      return version.isEmpty ? null : version;
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return null;
    }
  }

  Future<String?> checkForAdminUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final localVersion = info.version.trim();
    final remoteVersion = await _fetchRemoteVersion();
    if (remoteVersion == null) {
      return null;
    }
    final hasUpdate = _compareVersions(remoteVersion, localVersion) > 0;
    return hasUpdate ? remoteVersion : null;
  }

  void showAdminUpdateDialog(BuildContext context, String version) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('آپدیت جدید موجود است'),
        content: Text(
          'برنامه ورژن جدیدی داره ($version) از ادمین نسخه جدید رو دریافت کنید',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بعداً'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _launchAdminChat();
            },
            child: const Text('ارتباط با ادمین'),
          ),
        ],
      ),
    );
  }

  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (aParts.length < 3) {
      aParts.add(0);
    }
    while (bParts.length < 3) {
      bParts.add(0);
    }
    for (var i = 0; i < 3; i++) {
      if (aParts[i] != bParts[i]) {
        return aParts[i].compareTo(bParts[i]);
      }
    }
    return 0;
  }

  // Launch URL
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
      // If context is available, we could show a localized error message
      // For now, keeping the debug print as it's mainly for development
    }
  }

  Future<void> _launchAdminChat() async {
    try {
      final response = await http.get(Uri.parse(adminUrl)).timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) return;
      final adminId = response.body.trim();
      if (adminId.isEmpty) return;
      final tgUrl = Uri.parse('https://t.me/$adminId');
      await _launchUrl(tgUrl.toString());
    } catch (e) {
      debugPrint('Error launching admin chat: $e');
    }
  }
}
