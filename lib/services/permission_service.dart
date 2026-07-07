import 'dart:io';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Manages all runtime permission requests for the app.
/// Uses media_store_plus to detect SDK version properly.
class PermissionService {
  PermissionService._();

  static const _kLastVersionKey = 'permission_check_version';
  static int _cachedSdkInt = 0;

  // ── SDK Helpers ────────────────────────────────────────────────────────────

  /// Returns the device's Android SDK integer via media_store_plus.
  static Future<int> getSdkInt() async {
    if (_cachedSdkInt != 0) return _cachedSdkInt;
    if (!Platform.isAndroid) return 0;
    _cachedSdkInt = await MediaStore().getPlatformSDKInt();
    return _cachedSdkInt;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the list of permissions needed based on the device's API level.
  static Future<List<Permission>> getRequiredPermissions() async {
    if (!Platform.isAndroid) return [];
    final sdk = await getSdkInt();
    final perms = <Permission>[
      Permission.notification,
    ];

    // We no longer require storage permissions as we use scoped storage (app's data directory)
    
    // Battery optimization ignore is needed for stable background downloads
    perms.add(Permission.ignoreBatteryOptimizations);

    return perms;
  }

  /// Returns true if all critical permissions are granted for the current API level.
  static Future<bool> hasRequiredPermissions() async {
    if (!Platform.isAndroid) return true;
    final perms = await getRequiredPermissions();
    for (final p in perms) {
      // notification and ignoreBatteryOptimizations permissions are optional — don't block on them
      if (p == Permission.notification) continue;
      if (p == Permission.ignoreBatteryOptimizations) continue;
      if (!await p.isGranted) return false;
    }
    return true;
  }

  /// Returns true if the app needs to show the permission screen.
  static Future<bool> needsPermissionCheck() async {
    if (!Platform.isAndroid) return false;
    if (await hasRequiredPermissions()) return false; // Already granted — skip

    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    final lastCheckedVersion = prefs.getString(_kLastVersionKey);

    // Show gate on first launch OR on version upgrade with no permission
    return lastCheckedVersion == null || lastCheckedVersion != currentVersion;
  }

  /// Mark the current version as having completed the permission check.
  static Future<void> markPermissionCheckDone() async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    await prefs.setString(_kLastVersionKey, info.version);
  }

  /// Request all required permissions. Each permission triggers a system dialog.
  /// Returns a map of permission -> status after all requests.
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    if (!Platform.isAndroid) return {};
    final perms = await getRequiredPermissions();
    return await perms.request();
  }

  /// Request a single permission. Returns the final status.
  static Future<PermissionStatus> requestSingle(Permission permission) async {
    return await permission.request();
  }

  /// Open system app settings page for the app.
  static Future<void> openSettings() => openAppSettings();
}

