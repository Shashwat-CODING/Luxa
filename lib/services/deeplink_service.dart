import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import '../services/api_service.dart';
import '../screens/detail_screen.dart';
import '../screens/player_screen.dart';
import '../widgets/ios_widgets.dart';
import '../main.dart';


class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._();
  DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  Function(int, [String?])? _onTabChange;

  Uri? _pendingUri;
  Uri? _lastHandledUri;
  DateTime? _lastHandledTime;
  bool _isProcessing = false;

  void init({Function(int, [String?])? onTabChange}) {
    _onTabChange = onTabChange;
    _linkSubscription?.cancel();

    if (_pendingUri != null) {
      final uri = _pendingUri!;
      _pendingUri = null;
      _handleUri(uri);
    }

    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleUri(uri);
      }
    });

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    });
  }

  void dispose() {
    _linkSubscription?.cancel();
  }



  void _handleUri(Uri uri) async {
    final now = DateTime.now();
    if (_lastHandledUri == uri && 
        _lastHandledTime != null && 
        now.difference(_lastHandledTime!).inMilliseconds < 1500) {
      return;
    }
    if (_isProcessing) {
      return;
    }
    
    _isProcessing = true;
    _lastHandledUri = uri;
    _lastHandledTime = now;

    final scheme = uri.scheme;
    final host = uri.host;
    final path = uri.path;
    final params = uri.queryParameters;

    try {
      String fullPath = (host.isNotEmpty && scheme == 'luxa')
          ? '/$host$path'
          : path;

      if (fullPath.endsWith('/') && fullPath.length > 1) {
        fullPath = fullPath.substring(0, fullPath.length - 1);
      }
      if (!fullPath.startsWith('/')) {
        fullPath = '/$fullPath';
      }

      // Config links are now ignored as API is hardcoded
      if (fullPath.startsWith('/config')) {
        return;
      }

      await _waitForNavigator();
      if (navigatorKey.currentState == null) return;

      if (!ApiService.instance.isConfigured) {
        _pendingUri = uri;
        return;
      }

      // 1. Content Details: /details?type=movie&id=123
      if (fullPath.startsWith('/details')) {
        final type = params['type'] ?? (fullPath.split('/').length >= 3 ? fullPath.split('/')[1] : null);
        final idStr = params['id'] ?? (fullPath.split('/').length >= 4 ? fullPath.split('/')[2] : null);
        final id = int.tryParse(idStr ?? '');
        
        if (id != null && (type == 'movie' || type == 'tv')) {
          await _navigateToDetails(id, type!);
        }
      }
      // 2. Media Player: /watch?type=tv&id=456&s=1&e=5
      else if (fullPath.startsWith('/watch') && !fullPath.startsWith('/watch/iptv')) {
        final type = params['type'];
        final id = int.tryParse(params['id'] ?? '');
        final s = int.tryParse(params['s'] ?? '1');
        final e = int.tryParse(params['e'] ?? '1');
        
        if (id != null && (type == 'movie' || type == 'tv')) {
          await _navigateToPlayer(id, type!, season: s, episode: e);
        }
      }
      else if (fullPath == '/movies') {
        _switchTab(0);
      }
      else if (fullPath == '/config' || fullPath.contains('config')) {
        return;
      }
      else if (fullPath == '/' || fullPath.isEmpty) {
        _switchTab(0);
      }
      else if (fullPath.startsWith('/search')) {
        final query = params['query'] ?? params['q'];
        if (query != null && query.isNotEmpty) {
          _navigateToSearch(query);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _waitForNavigator() async {
    int retryCount = 0;
    while (navigatorKey.currentState == null && retryCount < 15) {
      await Future.delayed(const Duration(milliseconds: 200));
      retryCount++;
    }
  }




  void _navigateToSearch(String query) {
    _switchTab(1, query);
  }

  Future<void> _navigateToDetails(int id, String type) async {
    await _waitForNavigator();
    if (navigatorKey.currentState == null) return;

    _showLoadingOverlay();

    try {
      final api = ApiService.instance;
      final detail = type == 'movie'
          ? await api.getMovieDetail(id)
          : await api.getTvDetail(id);

      _hideLoadingOverlay();

      if (detail != null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          CupertinoPageRoute(builder: (_) => const MainNavigation()),
          (route) => false,
        );
        
        navigatorKey.currentState?.push(
          CupertinoPageRoute(builder: (_) => DetailScreen(item: detail)),
        );
      }
    } catch (e) {
      _hideLoadingOverlay();
    }
  }

  Future<void> _navigateToPlayer(int id, String type, {int? season, int? episode}) async {
    await _waitForNavigator();
    if (navigatorKey.currentState == null) return;

    _showLoadingOverlay();

    try {
      final api = ApiService.instance;
      final detail = type == 'movie'
          ? await api.getMovieDetail(id)
          : await api.getTvDetail(id);

      _hideLoadingOverlay();

      if (detail != null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          CupertinoPageRoute(builder: (_) => const MainNavigation()),
          (route) => false,
        );
        
        navigatorKey.currentState?.push(
          CupertinoPageRoute(
            builder: (_) => PlayerScreen(
              item: detail,
              season: season,
              episode: episode,
            ),
          ),
        );
      }
    } catch (e) {
      _hideLoadingOverlay();
    }
  }

  void _switchTab(int index, [String? query]) {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _onTabChange?.call(index, query);
  }

  bool _isLoadingShowing = false;

  void _hideLoadingOverlay() {
    if (!_isLoadingShowing) return;
    _isLoadingShowing = false;
    navigatorKey.currentState?.pop();
  }

  void _showLoadingOverlay({String message = 'Loading...'}) {
    if (_isLoadingShowing) return;
    _isLoadingShowing = true;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => IOSLoading(message: message),
    );
  }
}

