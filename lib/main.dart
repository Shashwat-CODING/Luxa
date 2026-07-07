import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:permission_handler/permission_handler.dart';

import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/library_screen.dart';
import 'screens/arts_screen.dart';
import 'screens/permission_gate_screen.dart';
import 'screens/anime_screen.dart';
import 'screens/detail_screen.dart';
import 'models/media_item.dart';

import 'services/watch_history.dart';
import 'services/bookmark_service.dart';
import 'services/api_service.dart';
import 'services/streaming_service.dart';
import 'services/ad_service.dart';
import 'services/deeplink_service.dart';
import 'services/window_service.dart';
import 'services/settings_service.dart';
import 'services/collection_service.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'screens/settings_screen.dart';
import 'screens/auth_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    MobileAds.instance.initialize();
    AdService.loadRewardedAd();
  }
  fvp.registerWith(options: {
    'video.decoders': ['AMediaCodec', 'VT', 'D3D11', 'NVDEC', 'FFmpeg'],
    'avformat.probesize': '1048576',
    'avformat.max_analyze_duration': '1000000',
    'demuxer.buffer.min': '1024',
    'demuxer.buffer.max': '8192',
  });
  await WatchHistory.load();
  await BookmarkService.init();
  await ApiService.instance.init();
  await WindowService.init();
  await StreamingService.instance.initDownloads();
  
  // Initialize Settings
  await SettingsService.instance.init();

  // Initialize Collection Service
  await CollectionService.instance.init();

  // Initialize Auth
  await AuthService.instance.init();
  
  runApp(const LuxaApp());
}

class LuxaApp extends StatefulWidget {
  const LuxaApp({super.key});

  @override
  State<LuxaApp> createState() => _LuxaAppState();
}

class _LuxaAppState extends State<LuxaApp> with WidgetsBindingObserver {
  bool _needsPermissionGate = false;
  bool _permissionChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeepLinkService.instance.init();
    _checkPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed. Restoring cloud data...');
      SyncService.instance.restoreAll();
    }
  }

  Future<void> _checkPermissions() async {
    // Basic check for now, can be expanded to check specific permissions via PermissionService
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final status = await Permission.notification.status;
        if (!status.isGranted && !status.isPermanentlyDenied) {
          await Permission.notification.request();
        }
      } catch (e) {
        debugPrint('Error requesting notification permission: $e');
      }
    }
    if (mounted) {
      setState(() {
        _needsPermissionGate = false; 
        _permissionChecked = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeepLinkService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final settings = SettingsService.instance;
        return CupertinoApp(
          navigatorKey: navigatorKey,
          title: 'Luxa',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.iosTheme(
            settings.themeMode == 1
                ? Brightness.dark
                : settings.themeMode == 2
                    ? Brightness.light
                    : MediaQuery.platformBrightnessOf(context),
            customFont: settings.customFont,
            isAmoled: settings.amoledTheme,
          ),
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    if (!_permissionChecked) {
      return const CupertinoPageScaffold(
        backgroundColor: Color(0xFF0A0A0A),
        child: Center(
          child: CupertinoActivityIndicator(radius: 15, color: Color(0xFFE50914)),
        ),
      );
    }

    if (_needsPermissionGate) {
      return PermissionGateScreen(
        onComplete: () {
          if (mounted) setState(() => _needsPermissionGate = false);
        },
      );
    }

    return const MainNavigation();
  }
}

// ── Navigation Items ───────────────────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int screenIndex;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.screenIndex,
  });
}

const List<_NavItem> _mainNavItems = [
  _NavItem(icon: FluentIcons.home_24_regular, selectedIcon: FluentIcons.home_24_filled, label: 'Home', screenIndex: 0),
  _NavItem(icon: FluentIcons.sparkle_24_regular, selectedIcon: FluentIcons.sparkle_24_filled, label: 'Anime', screenIndex: 2),
  _NavItem(icon: FluentIcons.library_24_regular, selectedIcon: FluentIcons.library_24_filled, label: 'Library', screenIndex: 3),
  _NavItem(icon: FluentIcons.image_24_regular, selectedIcon: FluentIcons.image_24_filled, label: 'Arts', screenIndex: 4),
  _NavItem(icon: FluentIcons.settings_24_regular, selectedIcon: FluentIcons.settings_24_filled, label: 'Settings', screenIndex: 5),
];

const List<_NavItem> _sidebarNavItems = [
  _NavItem(icon: FluentIcons.home_24_regular, selectedIcon: FluentIcons.home_24_filled, label: 'Home', screenIndex: 0),
  _NavItem(icon: FluentIcons.search_24_regular, selectedIcon: FluentIcons.search_24_filled, label: 'Search', screenIndex: 1),
  _NavItem(icon: FluentIcons.sparkle_24_regular, selectedIcon: FluentIcons.sparkle_24_filled, label: 'Anime', screenIndex: 2),
  _NavItem(icon: FluentIcons.library_24_regular, selectedIcon: FluentIcons.library_24_filled, label: 'Library', screenIndex: 3),
  _NavItem(icon: FluentIcons.image_24_regular, selectedIcon: FluentIcons.image_24_filled, label: 'Arts', screenIndex: 4),
  _NavItem(icon: FluentIcons.settings_24_regular, selectedIcon: FluentIcons.settings_24_filled, label: 'Settings', screenIndex: 5),
];

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _idx = 0;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final List<Widget> _screens;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowAuth());
    
    DeepLinkService.instance.init(onTabChange: (idx, [String? query]) {
      if (mounted) {
        setState(() {
          _idx = idx;
        });
        _navigatorKey.currentState?.popUntil((r) => r.isFirst);
        if (idx == 1) {
          if (query != null) {
            _searchController.text = query;
          }
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) {
              _searchFocusNode.requestFocus();
            }
          });
        } else {
          _searchController.clear();
          _searchFocusNode.unfocus();
        }
      }
    });

    _screens = [
      HomeScreen(
        onSearch: _goToSearchTab,
      ),
      SearchScreen(
        controller: _searchController,
        isTab: true,
      ),
      AnimeScreen(
        onSearch: _goToSearchTab,
      ),
      LibraryScreen(
        onSearch: _goToSearchTab,
      ),
      const ArtsScreen(),
      const SettingsScreen(),
    ];
  }

  void _goToSearchTab() {
    _goToTab(1);
  }

  void _goToTab(int index) {
    setState(() {
      _idx = index;
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    });
    if (index != 1) {
      _searchController.clear();
      _searchFocusNode.unfocus();
    } else {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Widget _buildSidebar(CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final inactiveColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF999999);

    return Container(
      width: 250,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      decoration: BoxDecoration(
        color: isDark
            ? (SettingsService.instance.amoledTheme ? const Color(0xFF121212) : const Color(0xFF1C1C1E))
            : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo/Brand
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 24, top: 8),
            child: Text(
              'LUXA',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Nav Items
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sidebarNavItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = _sidebarNavItems[i];
                final active = _idx == item.screenIndex;

                return GestureDetector(
                  onTap: () => _goToTab(item.screenIndex),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: active
                        ? BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8.0),
                          )
                        : const BoxDecoration(
                            color: CupertinoColors.transparent,
                          ),
                    child: Row(
                      children: [
                        Icon(
                          active ? item.selectedIcon : item.icon,
                          color: active ? theme.primaryColor : inactiveColor,
                          size: 20,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            item.label,
                            style: GoogleFonts.inter(
                              color: active ? theme.primaryColor : (isDark ? CupertinoColors.white : CupertinoColors.black),
                              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width > 950;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: CupertinoColors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: CupertinoColors.transparent,
      ),
    );

    if (isWide) {
      return CupertinoPageScaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        child: Row(
          children: [
            _buildSidebar(theme),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                decoration: AppTheme.brutalistDecoration(
                  context: context,
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: 12.0,
                  hasShadow: false,
                  hasBorder: false,
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildNavigator(),
              ),
            ),
          ],
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: Stack(
        children: [
          _buildNavigator(),
          _buildBottomBar(theme),
        ],
      ),
    );
  }

  Widget _buildNavigator() {
    return Navigator(
      key: _navigatorKey,
      onGenerateRoute: (settings) {
        return CupertinoPageRoute(
          settings: settings,
          builder: (context) {
            if (settings.name == '/details') {
              return DetailScreen(item: settings.arguments as MediaItem);
            }
            if (settings.name == '/search') {
              return const SearchScreen();
            }
            return IndexedStack(index: _idx, children: _screens);
          },
        );
      },
    );
  }

  Widget _buildBottomBar(CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final floatBottom = 12.0 + bottomPadding;
    final isSearchActive = _idx == 1;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final showNavBar = (!keyboardVisible || isSearchActive);

    return Positioned(
      left: 16,
      right: 16,
      bottom: floatBottom,
      height: 56,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: showNavBar ? 1.0 : 0.0,
        child: IgnorePointer(
          ignoring: !showNavBar,
          child: Row(
            children: [
              // Main pill: Home, Anime, Library, Arts, Settings OR Search input
              Expanded(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                        blurRadius: 20,
                        spreadRadius: -4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: Container(
                        decoration: BoxDecoration(
                          color: (isDark ? CupertinoColors.black : CupertinoColors.white).withValues(alpha: isDark ? 0.20 : 0.35),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: CupertinoColors.white.withValues(alpha: isDark ? 0.12 : 0.20),
                            width: 0.75,
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: isSearchActive
                              ? _buildSearchTextField(context)
                              : _buildNavButtons(theme),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Search circle / Home Button
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                      blurRadius: 20,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (isSearchActive) {
                          _goToTab(0); // Go to Home
                        } else {
                          _goToSearchTab();
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: (isDark ? CupertinoColors.black : CupertinoColors.white).withValues(alpha: isDark ? 0.20 : 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: CupertinoColors.white.withValues(alpha: isDark ? 0.12 : 0.20),
                            width: 0.75,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (child, animation) {
                                  return ScaleTransition(
                                    scale: animation,
                                    child: FadeTransition(opacity: animation, child: child),
                                  );
                                },
                                child: isSearchActive
                                    ? Icon(
                                        FluentIcons.home_24_regular,
                                        key: const ValueKey('home_button_icon'),
                                        color: (isDark ? CupertinoColors.white : CupertinoColors.black).withValues(alpha: 0.6),
                                        size: 18,
                                      )
                                    : Icon(
                                        FluentIcons.search_24_regular,
                                        key: const ValueKey('search_button_icon'),
                                        color: (isDark ? CupertinoColors.white : CupertinoColors.black).withValues(alpha: 0.6),
                                        size: 18,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButtons(CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      key: const ValueKey('nav_buttons_row'),
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(_mainNavItems.length, (i) {
        final item = _mainNavItems[i];
        final active = _idx == item.screenIndex;
        final activeColor = theme.primaryColor;
        final inactiveColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF999999);

        return Expanded(
          child: GestureDetector(
            onTap: () => _goToTab(item.screenIndex),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: active
                    ? RadialGradient(
                        colors: [
                          activeColor.withValues(alpha: isDark ? 0.15 : 0.10),
                          activeColor.withValues(alpha: 0.0),
                        ],
                        radius: 0.85,
                      )
                    : null,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    active ? item.selectedIcon : item.icon,
                    color: active ? activeColor : inactiveColor,
                    size: 18,
                  ),
                  const SizedBox(height: 0.5),
                  Text(
                    item.label,
                    style: GoogleFonts.inter(
                      color: active ? activeColor : inactiveColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 8.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSearchTextField(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      key: const ValueKey('search_text_field'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CupertinoTextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: TextStyle(
          color: isDark ? CupertinoColors.white : CupertinoColors.black,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: theme.primaryColor,
        placeholder: 'Search movies, TV shows & anime...',
        placeholderStyle: TextStyle(
          color: (isDark ? CupertinoColors.white : CupertinoColors.black).withValues(alpha: 0.4),
          fontWeight: FontWeight.w500,
        ),
        decoration: null,
        prefix: Padding(
          padding: const EdgeInsets.only(left: 0, right: 8),
          child: Icon(
            FluentIcons.search_24_regular,
            color: (isDark ? CupertinoColors.white : CupertinoColors.black).withValues(alpha: 0.6),
            size: 20,
          ),
        ),
        suffix: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchController,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () {
                _searchController.clear();
                _searchFocusNode.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  FluentIcons.dismiss_circle_24_filled,
                  color: (isDark ? CupertinoColors.white : CupertinoColors.black).withValues(alpha: 0.4),
                  size: 18,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _checkUpdate() async {
    final update = await ApiService.instance.checkForUpdate();
    if (update != null && mounted) {
      _showUpdateDialog(update);
    }
  }

  Future<void> _maybeShowAuth() async {
    if (AuthService.instance.isAuthenticated) return;
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool('has_seen_auth') ?? false;
    if (hasSeen) return;
    await prefs.setBool('has_seen_auth', true);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(builder: (_) => const AuthScreen(showSkip: true)),
    );
  }

  void _showUpdateDialog(Map<String, dynamic> update) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Update Available'),
        content: Text('A new version (${update['version']}) is available.'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              launchUrl(Uri.parse(update['url']), mode: LaunchMode.externalApplication);
              Navigator.pop(context);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}






