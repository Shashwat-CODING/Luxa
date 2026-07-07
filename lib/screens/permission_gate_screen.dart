import 'package:flutter/cupertino.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/permission_service.dart';

/// Full-screen permission gate shown on first install or after an app update.
/// Requests all required permissions via system dialogs immediately.
class PermissionGateScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const PermissionGateScreen({super.key, required this.onComplete});

  @override
  State<PermissionGateScreen> createState() => _PermissionGateScreenState();
}

class _PermissionGateScreenState extends State<PermissionGateScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _isRequesting = false;
  bool _allGranted = false;
  bool _anyPermanentlyDenied = false;
  // Track whether we went to Settings so we can recheck on resume
  bool _awaitingSettingsReturn = false;

  late final AnimationController _pulse;

  // Tracks what permissions are needed and their labels
  List<({Permission permission, String label, String description, IconData icon})> _permItems = [];
  Map<Permission, PermissionStatus> _statuses = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);
    _loadPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingSettingsReturn) {
      _awaitingSettingsReturn = false;
      _refreshStatuses();
    }
  }

  Future<void> _loadPermissions() async {
    final sdk = await PermissionService.getSdkInt();
    final items = <({Permission permission, String label, String description, IconData icon})>[];

    // Notification — always needed
    items.add((
      permission: Permission.notification,
      label: 'Notifications',
      description: 'Show download progress and alerts',
      icon: FluentIcons.alert_24_filled,
    ));

    // We no longer require storage permissions as we use scoped storage


    // Background Access / Battery Optimization
    items.add((
      permission: Permission.ignoreBatteryOptimizations,
      label: 'Background Access',
      description: 'Keep downloads running when the app is minimized',
      icon: FluentIcons.battery_charge_24_regular,
    ));

    if (!mounted) return;
    setState(() => _permItems = items);
    await _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    if (!mounted) return;
    final Map<Permission, PermissionStatus> statuses = {};
    for (final item in _permItems) {
      statuses[item.permission] = await item.permission.status;
    }

    final allGranted = statuses.values
        .where((s) => true)
        .every((s) => s.isGranted);
    final anyPerm = statuses.entries
        .where((e) => e.key != Permission.ignoreBatteryOptimizations)
        .any((e) => e.value.isPermanentlyDenied);

    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _allGranted = allGranted;
      _anyPermanentlyDenied = anyPerm;
    });

    if (allGranted) {
      await PermissionService.markPermissionCheckDone();
      widget.onComplete();
    }
  }

  /// Requests all non-granted permissions one by one.
  /// This shows the actual system dialogs.
  Future<void> _requestAllPermissions() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);

    try {
      // Request all permissions at once — each will show its own system dialog
      final perms = _permItems.map((e) => e.permission).toList();
      final statuses = await perms.request();

      if (!mounted) return;
      setState(() {
        _statuses = statuses;
        _isRequesting = false;
        _allGranted = statuses.values.every((s) => s.isGranted);
        _anyPermanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
      });

      if (_allGranted) {
        await PermissionService.markPermissionCheckDone();
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  /// Opens app settings for permanently denied permissions.
  Future<void> _openAppSettings() async {
    _awaitingSettingsReturn = true;
    await openAppSettings();
  }

  Future<void> _skip() async {
    await PermissionService.markPermissionCheckDone();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF080808),
      child: Stack(
        children: [
          // Background glow blobs
          Positioned(
            top: -size.height * 0.15,
            left: -size.width * 0.3,
            child: _GlowBlob(
              color: const Color(0xFFE50914).withValues(alpha: 0.18),
              size: size.width * 0.9,
            ),
          ),
          Positioned(
            bottom: -size.height * 0.1,
            right: -size.width * 0.2,
            child: _GlowBlob(
              color: const Color(0xFF9C27B0).withValues(alpha: 0.10),
              size: size.width * 0.7,
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 48),

                  // Animated icon
                  ScaleTransition(
                    scale: _pulse,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFE50914).withValues(alpha: 0.22),
                            const Color(0xFFE50914).withValues(alpha: 0.03),
                          ],
                        ),
                        border: Border.all(
                          color: const Color(0xFFE50914).withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        FluentIcons.shield_keyhole_24_filled,
                        color: Color(0xFFE50914),
                        size: 42,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text(
                    'App Permissions',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      color: CupertinoColors.white,
                      height: 1.1,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Grant the following permissions so Luxa can save downloads and send you updates.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: CupertinoColors.white.withValues(alpha: 0.54),
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Permission list
                  if (_permItems.isEmpty)
                    const CupertinoActivityIndicator(
                      color: Color(0xFFE50914),
                    )
                  else
                    Column(
                      children: _permItems.map((item) {
                        final status = _statuses[item.permission];
                        return _PermissionTile(
                          icon: item.icon,
                          label: item.label,
                          description: item.description,
                          status: status,
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 32),

                  // Primary button
                  SizedBox(
                    width: double.infinity,
                    child: _isRequesting
                        ? const Center(
                            child: CupertinoActivityIndicator(
                              color: Color(0xFFE50914),
                            ),
                          )
                        : _anyPermanentlyDenied
                            ? CupertinoButton(
                                color: const Color(0xFFE57373),
                                borderRadius: BorderRadius.circular(16),
                                onPressed: _openAppSettings,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(FluentIcons.settings_24_filled, size: 20, color: CupertinoColors.white),
                                    const SizedBox(width: 8),
                                    Text('Open App Settings', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: CupertinoColors.white)),
                                  ],
                                ),
                              )
                            : CupertinoButton(
                                color: const Color(0xFFE50914),
                                borderRadius: BorderRadius.circular(16),
                                onPressed: _requestAllPermissions,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(FluentIcons.shield_checkmark_24_filled, size: 20, color: CupertinoColors.white),
                                    const SizedBox(width: 8),
                                    Text('Grant All Permissions', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: CupertinoColors.white)),
                                  ],
                                ),
                              ),
                  ),

                  const SizedBox(height: 10),

                  CupertinoButton(
                    onPressed: _skip,
                    child: Text(
                      'Continue Without Permissions',
                      style: GoogleFonts.outfit(
                        color: CupertinoColors.white.withValues(alpha: 0.28),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Permission Tile ───────────────────────────────────────────────────────────

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final PermissionStatus? status;

  const _PermissionTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final granted = status?.isGranted ?? false;
    final denied = status?.isPermanentlyDenied ?? false;

    Color indicatorColor;
    IconData indicatorIcon;
    if (granted) {
      indicatorColor = const Color(0xFF4CAF50);
      indicatorIcon = FluentIcons.checkmark_circle_24_filled;
    } else if (denied) {
      indicatorColor = const Color(0xFFE57373);
      indicatorIcon = FluentIcons.dismiss_circle_24_filled;
    } else {
      indicatorColor = CupertinoColors.white.withValues(alpha: 0.24);
      indicatorIcon = FluentIcons.circle_24_regular;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: granted
              ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
              : CupertinoColors.white.withValues(alpha: 0.07),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE50914).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFE50914), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.outfit(
                    color: CupertinoColors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(indicatorIcon, color: indicatorColor, size: 22),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, CupertinoColors.transparent]),
      ),
    );
  }
}



