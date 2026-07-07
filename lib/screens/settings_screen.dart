import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../screens/auth_screen.dart';
import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _ignoreBatteryOptimizations = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBatteryOptimization();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBatteryOptimization();
    }
  }

  Future<void> _checkBatteryOptimization() async {
    if (Platform.isAndroid) {
      final isIgnored = await Permission.ignoreBatteryOptimizations.isGranted;
      if (mounted) {
        setState(() {
          _ignoreBatteryOptimizations = isIgnored;
        });
      }
    }
  }

  Future<void> _toggleBatteryOptimization(bool val) async {
    if (Platform.isAndroid) {
      if (val) {
        final status = await Permission.ignoreBatteryOptimizations.request();
        setState(() {
          _ignoreBatteryOptimizations = status.isGranted;
        });
      } else {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Battery Optimizations'),
            content: const Text('To restrict background battery usage, please disable this option in device settings.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              CupertinoDialogAction(
                child: const Text('Open Settings'),
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.transparent,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: const Text('Settings'),
            border: null,
          ),
          SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: SettingsService.instance,
              builder: (context, _) {
                final settings = SettingsService.instance;
                return Column(
                  children: [
                    ListenableBuilder(
                      listenable: AuthService.instance,
                      builder: (context, _) {
                        final auth = AuthService.instance;
                        final user = auth.user;
                        return IOSSettingsGroup(
                          title: 'Account',
                          children: [
                            if (auth.isAuthenticated)
                              IOSSettingsTile(
                                icon: FluentIcons.person_circle_24_regular,
                                iconColor: CupertinoColors.systemGreen,
                                title: user?.name ?? user?.username ?? 'User',
                                subtitle: user?.email,
                                trailing: CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => auth.logout(),
                                  child: const Text('Logout', style: TextStyle(color: CupertinoColors.systemRed)),
                                ),
                                onTap: () {},
                              )
                            else
                              IOSSettingsTile(
                                icon: FluentIcons.person_add_24_regular,
                                iconColor: theme.primaryColor,
                                title: 'Sign In / Sign Up',
                                subtitle: 'Sync your history & bookmarks',
                                onTap: () => Navigator.of(context, rootNavigator: true).push(
                                  CupertinoPageRoute(builder: (_) => const AuthScreen()),
                                ),
                              ),
                            ListenableBuilder(
                              listenable: SyncService.instance,
                              builder: (context, _) {
                                final sync = SyncService.instance;
                                return IOSSettingsTile(
                                  icon: sync.isSyncing 
                                    ? FluentIcons.arrow_sync_24_filled 
                                    : FluentIcons.cloud_24_filled,
                                  iconColor: sync.isSyncing 
                                    ? CupertinoColors.systemOrange 
                                    : CupertinoColors.systemBlue,
                                  title: sync.isSyncing ? 'Syncing...' : 'Cloud Backup',
                                  subtitle: sync.isSyncing 
                                    ? 'Updating your data...' 
                                    : (sync.lastSync != null 
                                        ? 'Last synced: ${_formatTime(sync.lastSync!)}' 
                                        : 'Data is synced automatically'),
                                  trailing: sync.isSyncing 
                                    ? const CupertinoActivityIndicator(radius: 8)
                                    : null,
                                  onTap: () {},
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    IOSSettingsGroup(
                      title: 'Appearance',
                      children: [
                        IOSSettingsTile(
                          icon: FluentIcons.brightness_high_24_regular,
                          iconColor: theme.primaryColor,
                          title: 'Theme Mode',
                          subtitle: _getThemeModeLabel(settings.themeMode),
                          onTap: () => _showThemePicker(context),
                        ),
                        IOSSettingsSwitch(
                          icon: FluentIcons.weather_moon_24_regular,
                          iconColor: AppTheme.secondaryGold,
                          title: 'AMOLED Black',
                          value: settings.amoledTheme,
                          onChanged: (val) {
                            settings.setAmoledTheme(val);
                          },
                        ),
                        IOSSettingsTile(
                          icon: FluentIcons.text_font_24_regular,
                          iconColor: AppTheme.secondaryGold,
                          title: 'Custom Font',
                          subtitle: settings.customFont,
                          onTap: () => _showFontPicker(context),
                        ),
                      ],
                    ),

                    IOSSettingsGroup(
                      title: 'System',
                      children: [
                        if (Platform.isAndroid)
                          IOSSettingsSwitch(
                            icon: FluentIcons.battery_charge_24_regular,
                            iconColor: theme.primaryColor,
                            title: 'Ignore Battery Optimizations',
                            value: _ignoreBatteryOptimizations,
                            onChanged: _toggleBatteryOptimization,
                          ),
                        IOSSettingsTile(
                          icon: FluentIcons.delete_24_regular,
                          iconColor: CupertinoColors.systemRed,
                          title: 'Clear Cache',
                          subtitle: 'Free up storage space',
                          onTap: () => _handleClearCache(context),
                        ),
                      ],
                    ),
                    IOSSettingsGroup(
                      title: 'Community',
                      children: [
                        IOSSettingsTile(
                          icon: FluentIcons.send_24_filled,
                          iconColor: const Color(0xFF229ED9),
                          title: 'Join Telegram',
                          subtitle: 'Stay updated with Luxa',
                          onTap: () => launchUrl(
                            Uri.parse('https://t.me/luxasuperapp'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                    IOSSettingsGroup(
                      title: 'About',
                      children: [
                        IOSSettingsTile(
                          icon: FluentIcons.info_24_regular,
                          iconColor: AppTheme.secondaryGold,
                          title: 'App Version',
                          subtitle: settings.appVersion,
                          onTap: () {},
                        ),
                        IOSSettingsTile(
                          icon: FluentIcons.heart_24_filled,
                          iconColor: theme.primaryColor,
                          title: 'Luxa Premium',
                          subtitle: 'You are using version 2.6.0',
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 120),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getThemeModeLabel(int mode) {
    if (mode == 1) return 'Dark';
    if (mode == 2) return 'Light';
    if (mode == 3) return 'AMOLED Black';
    return 'System Default';
  }

  void _showThemePicker(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CompactActionSheet(
        title: const Text('Select Theme'),
        actions: [
          CompactActionSheetAction(
            onPressed: () {
              SettingsService.instance.setThemeMode(0);
              Navigator.pop(context);
            },
            child: const Text('System Default'),
          ),
          CompactActionSheetAction(
            onPressed: () {
              SettingsService.instance.setThemeMode(2);
              Navigator.pop(context);
            },
            child: const Text('Light'),
          ),
          CompactActionSheetAction(
            onPressed: () {
              SettingsService.instance.setThemeMode(1);
              Navigator.pop(context);
            },
            child: const Text('Dark'),
          ),
        ],
        cancelButton: CompactActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showFontPicker(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CompactActionSheet(
        title: const Text('Select Font'),
        actions:
            [
                  'Karst',
                  'Poppins',
                  'Roboto',
                  'Inter',
                  'Outfit',
                  'Lexend',
                  'Montserrat',
                ]
                .map(
                  (font) => CompactActionSheetAction(
                    onPressed: () {
                      SettingsService.instance.setCustomFont(font);
                      Navigator.pop(context);
                    },
                    child: Text(
                      font,
                      style: font == 'Karst'
                          ? const TextStyle(fontFamily: 'Karst')
                          : GoogleFonts.getFont(font),
                    ),
                  ),
                )
                .toList(),
        cancelButton: CompactActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _handleClearCache(BuildContext context) async {
    await SettingsService.instance.clearCache();
    if (context.mounted) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Cache Cleared'),
          content: const Text('Successfully cleared all cache.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }
}
