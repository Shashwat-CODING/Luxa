import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart' as material;
import 'package:fvp/fvp.dart';
import 'package:dio/dio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/media_item.dart';
import '../services/api_service.dart';
import '../models/api_models.dart';
import '../widgets/ios_widgets.dart';
import '../services/watch_history.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

class AnimePlayerScreen extends StatefulWidget {
  final MediaDetail item;
  final String slug;
  final String type; // 'movie' or 'episode'

  const AnimePlayerScreen({
    super.key,
    required this.item,
    required this.slug,
    required this.type,
  });

  @override
  State<AnimePlayerScreen> createState() => _AnimePlayerScreenState();
}

class _AnimePlayerScreenState extends State<AnimePlayerScreen> {
  final _api = ApiService.instance;

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  dynamic _mediaInfo;

  bool _loading = true;
  bool _error = false;
  String _errorMsg = '';
  bool _isFullscreen = false;
  bool _hasSeeked = false;

  List<StreamSource> _sources = [];
  StreamSource? _selectedSource;

  String? _currentSlug;
  String? _nextSlug;
  String? _prevSlug;
  String? _currentTitle;
  String? _currentEpInfo;

  // Patience notice timer
  bool _showPatienceNotice = false;
  Timer? _patienceTimer;

  Timer? _loadingTimer;
  int _messageIndex = 0;
  final List<String> _loadingMessages = [
    'Summoning anime spirits...',
    'Buffering awesome moments...',
    'Finding best quality...',
    'Sharpening the pixels...',
    'Almost ready...',
    'Enjoy the show!',
  ];

  @override
  void initState() {
    super.initState();
    _currentSlug = widget.slug;
    _currentTitle = widget.item.title;
    WakelockPlus.enable().catchError((_) {});
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: CupertinoColors.transparent),
    );
    _loadPlayback();
  }

  void _startLoadingAnimation() {
    _stopLoadingAnimation();
    _messageIndex = 0;
    _loadingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _loadingMessages.length;
        });
      }
    });
    // Show patience notice after 6 seconds
    _patienceTimer?.cancel();
    _patienceTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _showPatienceNotice = true);
    });
  }

  void _stopLoadingAnimation() {
    _loadingTimer?.cancel();
    _loadingTimer = null;
    _patienceTimer?.cancel();
    _patienceTimer = null;
    if (mounted) setState(() => _showPatienceNotice = false);
  }

  @override
  void dispose() {
    _saveProgress();
    _resetSystemUI();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _stopLoadingAnimation();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void _resetSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      _resetSystemUI();
    }
  }

  void _saveProgress() {
    if (_videoPlayerController == null ||
        !_videoPlayerController!.value.isInitialized) {
      return;
    }
    if (_videoPlayerController!.value.duration.inMilliseconds <= 0) {
      return;
    }

    final pos = _videoPlayerController!.value.position.inMilliseconds;
    final dur = _videoPlayerController!.value.duration.inMilliseconds;

    // If watched > 95%, we consider it finished and don't save progress
    final progress = pos / dur;
    final finalPos = progress > 0.95 ? 0 : pos;

    WatchHistory.addItem(
      MediaItem(
        id: widget.item.id,
        title: widget.item.title,
        overview: widget.item.overview,
        posterPath: widget.item.posterPath,
        backdropPath: widget.item.backdropPath,
        voteAverage: widget.item.voteAverage,
        releaseDate: widget.item.releaseDate,
        mediaType: widget.item.mediaType,
        extraInfo: _currentEpInfo ?? _currentTitle,
        position: finalPos,
        duration: dur,
      ),
    );
  }

  // ── Playback Loading ────────────────────────────────────────────────────────

  Future<void> _loadPlayback() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
      _errorMsg = '';
      _sources = [];
      _selectedSource = null;
    });
    _startLoadingAnimation();

    debugPrint('🚀 [ANIME] Loading slug: $_currentSlug, type: ${widget.type}');
    try {
      final details = await _api.getAnimePlaybackDetails(_currentSlug!, widget.type);

      if (details == null ||
          details['sources'] == null ||
          (details['sources'] as List).isEmpty) {
        debugPrint('❌ [ANIME] No sources found for $_currentSlug');
        if (mounted) {
          setState(() {
            _error = true;
            _errorMsg = 'No streaming sources found for this episode.';
            _loading = false;
          });
          _stopLoadingAnimation();
        }
        return;
      }

      if (mounted) {
        setState(() {
          _sources = List<StreamSource>.from(details['sources']);
          _nextSlug = details['next_slug'];
          _prevSlug = details['prev_slug'];
          if (details['title'] != null) _currentTitle = details['title'];
          _currentEpInfo = details['episode_info'];
          _selectedSource = _sources.first;
        });
        debugPrint('✅ [ANIME] ${_sources.length} sources. Using: ${_selectedSource?.url}');
        _initPlayer(_selectedSource!.url);
      }
    } catch (e) {
      debugPrint('💥 [ANIME API ERR] $e');
      if (mounted) {
        setState(() {
          _error = true;
          _errorMsg = 'API Error: $e';
          _loading = false;
        });
        _stopLoadingAnimation();
      }
    }
  }

  // ── Player Init (same pattern as movie player) ──────────────────────────────

  Future<void> _initPlayer(String url) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    _startLoadingAnimation();

    final headers = <String, String>{
      'Referer': _selectedSource?.resolvedReferer ?? 'https://animesalt.ac/',
      'Origin': _selectedSource?.resolvedOrigin ?? 'https://animesalt.ac',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
    if (_selectedSource?.headers != null) {
      headers.addAll(_selectedSource!.headers!);
    }

    // Dispose old controller
    _chewieController?.dispose();
    _chewieController = null;
    _videoPlayerController?.pause();
    _videoPlayerController?.dispose();
    _videoPlayerController = null;

    // Pre-validate URL (same logic as movie player, but lighter — HLS .m3u8
    // endpoints often return 200 immediately so we keep a short timeout)
    final isServer6 = _selectedSource?.serverId == 6;
    if (isServer6) {
      debugPrint('ℹ️ [ANIME PLAYER] Server 6 detected. Skipping pre-validation as requested.');
    }
    final statusCode = isServer6 ? 200 : await _preValidateUrl(url, headers);
    if (!mounted) return;

    if (statusCode >= 400) {
      debugPrint('❌ [ANIME] Pre-validation failed ($statusCode) for $url');
      _handleStreamError('URL pre-validation failed ($statusCode)');
      return;
    }

    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: headers,
      );

      await _videoPlayerController!.initialize();

      final primaryColor = CupertinoTheme.of(context).primaryColor;
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio > 0 ? _videoPlayerController!.value.aspectRatio : 16 / 9,
        showControls: true,
        allowFullScreen: true,
        allowPlaybackSpeedChanging: true,
        customControls: const MaterialControls(),
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: primaryColor,
          handleColor: primaryColor,
          bufferedColor: CupertinoColors.systemGrey.withValues(alpha: 0.5),
          backgroundColor: CupertinoColors.systemGrey.withValues(alpha: 0.2),
        ),
        materialProgressColors: ChewieProgressColors(
          playedColor: primaryColor,
          handleColor: primaryColor,
          bufferedColor: CupertinoColors.systemGrey.withValues(alpha: 0.5),
          backgroundColor: CupertinoColors.systemGrey.withValues(alpha: 0.2),
        ),
      );

      try {
        _mediaInfo = _videoPlayerController!.getMediaInfo();
      } catch (_) {}

      if (mounted) {
        setState(() => _loading = false);
        _stopLoadingAnimation();

        // Seek once if we have a saved position
        if (!_hasSeeked && widget.item.position != null) {
          _hasSeeked = true;
          _videoPlayerController!.seekTo(
            Duration(milliseconds: widget.item.position!),
          );
        }

        _videoPlayerController!.play();

        // Add to watch history instantly (will sync to API immediately)
        WatchHistory.addItem(
          MediaItem(
            id: widget.item.id,
            title: widget.item.title,
            overview: widget.item.overview,
            posterPath: widget.item.posterPath,
            backdropPath: widget.item.backdropPath,
            voteAverage: widget.item.voteAverage,
            releaseDate: widget.item.releaseDate,
            mediaType: widget.item.mediaType,
            extraInfo: _currentEpInfo ?? _currentTitle,
            position: 0,
            duration: _videoPlayerController!.value.duration.inMilliseconds,
          ),
        );
      }
    } catch (e) {
      debugPrint('💥 [ANIME INIT ERR] $e');
      _handleStreamError(e);
    }
  }

  void _handleStreamError(dynamic error) {
    final failedSource = _selectedSource;
    if (failedSource == null) return;

    final idx = _sources.indexOf(failedSource);
    final nextIdx = idx + 1;

    if (nextIdx < _sources.length) {
      debugPrint('🔄 [ANIME] Server failed, trying next...');
      if (mounted) {
        setState(() {
          _selectedSource = _sources[nextIdx];
          _loading = true;
          _error = false;
        });
        _initPlayer(_selectedSource!.url);
      }
    } else {
      debugPrint('❌ [ANIME] All servers failed.');
      if (mounted) {
        final msg = 'All available servers failed.\n${error.toString()}';
        setState(() {
          _loading = false;
          _error = true;
          _errorMsg = msg;
        });
        _stopLoadingAnimation();
        _showErrorDialog(msg);
      }
    }
  }

  Future<int> _preValidateUrl(String url, Map<String, String> headers) async {
    if (url.startsWith('file://')) return 200;
    // HLS .m3u8 URLs are almost always valid from anime APIs; use short timeout
    try {
      final client = Dio();
      client.options.connectTimeout = const Duration(seconds: 8);
      client.options.receiveTimeout = const Duration(seconds: 8);
      client.options.sendTimeout = const Duration(seconds: 8);

      final reqHeaders = Map<String, String>.from(headers)
        ..remove('Range')
        ..remove('range');

      final response = await client.head(
        url,
        options: Options(
          headers: reqHeaders,
          validateStatus: (_) => true,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );
      final code = response.statusCode ?? 500;
      final ct = (response.headers.value('content-type') ?? '').toLowerCase();
      debugPrint('  [ANIME] Pre-validate: $code | $ct | $url');
      if (ct.contains('text/html')) return 406;
      if (code == 405 || code == 501) return 200; // HEAD not allowed, try anyway
      if (code < 400) return 200;
      return code;
    } catch (_) {
      return 200; // Let player try on timeout/error
    }
  }

  // ── Episode Navigation ──────────────────────────────────────────────────────

  void _onNext() {
    if (_nextSlug != null) {
      _saveProgress();
      setState(() => _currentSlug = _nextSlug);
      _videoPlayerController?.pause();
      _loadPlayback();
    }
  }

  void _onPrev() {
    if (_prevSlug != null) {
      _saveProgress();
      setState(() => _currentSlug = _prevSlug);
      _videoPlayerController?.pause();
      _loadPlayback();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isFullscreen) {
      return CupertinoPageScaffold(
        backgroundColor: CupertinoColors.transparent,
        child: Stack(children: [Center(child: _buildVideoContainer())]),
      );
    }

    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 950;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: _buildVideoContainer(),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 24)
                              .copyWith(bottom: 40),
                          child: _buildAnimeInfo(),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                    width: 1,
                    color: CupertinoColors.separator.withValues(alpha: 0.2)),
                Expanded(flex: 3, child: _buildSidebar(theme)),
              ],
            );
          }

          return Column(
            children: [
              Stack(
                children: [
                  SafeArea(
                    bottom: false,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _buildVideoContainer(),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAnimeInfo(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Video Container ─────────────────────────────────────────────────────────

  Widget _buildVideoContainer() {
    if (_loading) return _buildLoadingView();
    if (_error) {
      return Container(
        color: CupertinoColors.black,
        child: _buildErrorState(),
      );
    }

    return Stack(
      children: [
        if (_videoPlayerController != null &&
            _videoPlayerController!.value.isInitialized &&
            _chewieController != null)
          material.Theme(
            data: material.ThemeData.dark().copyWith(
              platform: TargetPlatform.android,
            ),
            child: material.Material(
              type: material.MaterialType.transparency,
              child: Chewie(controller: _chewieController!),
            ),
          )
        else
          Container(color: CupertinoColors.black),
      ],
    );
  }

  Widget _glassIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    EdgeInsets? padding,
  }) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: isDark ? const Color(0x662C2C2E) : const Color(0x66FFFFFF),
          child: CupertinoButton(
            padding: padding ?? const EdgeInsets.all(10),
            minSize: 0,
            onPressed: onPressed,
            child: Icon(
              icon,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _glassIconButton(
            padding: EdgeInsets.zero,
            icon: FluentIcons.chevron_left_24_regular,
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    final cs = CupertinoTheme.of(context).colorScheme;
    return Container(
      color: CupertinoColors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const IOSLoading(size: 64),
            const SizedBox(height: 32),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Column(
                key: ValueKey<int>(_messageIndex),
                children: [
                  Text(
                    _loadingMessages[_messageIndex],
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSerifDisplay(
                      color: cs.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sources.isNotEmpty
                        ? 'Attempting Server ${_sources.indexOf(_selectedSource ?? _sources.first) + 1} of ${_sources.length}...'
                        : 'Fetching sources...',
                    style: GoogleFonts.outfit(
                      color: CupertinoColors.systemGrey,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            // Patience notice after 6 seconds
            if (_showPatienceNotice) ...[
              const SizedBox(height: 24),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: CupertinoColors.systemOrange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      FluentIcons.clock_24_regular,
                      color: CupertinoColors.systemOrange,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Stream loading may take a little time — please be patient ✨',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: CupertinoColors.systemOrange,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: 0.2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(32),
            width: 400,
            decoration: BoxDecoration(
              color: CupertinoColors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(24),
              border:
                  Border.all(color: CupertinoColors.systemRed.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    FluentIcons.warning_24_filled,
                    color: CupertinoColors.systemRed,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Playback Error',
                  style: GoogleFonts.outfit(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMsg,
                  style: GoogleFonts.outfit(
                    color: CupertinoColors.systemGrey,
                    fontSize: 13,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: AppTheme.brutalistDecoration(
                            context: context,
                            color: CupertinoColors.white,
                            borderRadius: 4.0,
                            shadowOffset: 2.0,
                          ),
                          child: Center(
                            child: Text(
                              'GO BACK',
                              style: GoogleFonts.spaceGrotesk(
                                color: CupertinoColors.black,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _loadPlayback,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: AppTheme.brutalistDecoration(
                            context: context,
                            color: AppTheme.neonYellow,
                            borderRadius: 4.0,
                            shadowOffset: 2.0,
                          ),
                          child: Center(
                            child: Text(
                              'RETRY',
                              style: GoogleFonts.spaceGrotesk(
                                color: CupertinoColors.black,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Anime Info ──────────────────────────────────────────────────────────────

  Widget _buildAnimeInfo() {
    final item = widget.item;
    final cs = CupertinoTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _currentTitle ?? item.title,
            style: GoogleFonts.dmSerifDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1.0,
              color: cs.onSurface,
            ),
          ).animate().fadeIn().slideX(begin: -0.05),
          if (_currentEpInfo != null) ...[
            const SizedBox(height: 4),
            Text(
              _currentEpInfo!,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (item.year.isNotEmpty) _infoBadge(item.year, FluentIcons.calendar_24_regular),
              _infoBadge(
                item.ratingStr,
                FluentIcons.star_24_filled,
                iconColor: CupertinoColors.systemYellow,
              ),
            ],
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 24),
          _buildActionRow().animate().fadeIn(delay: 150.ms).slideY(begin: 0.1),
          const SizedBox(height: 32),
          Text(
            'SYNOPSIS',
            style: GoogleFonts.dmSans(
              color: cs.primary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 12),
          Text(
            item.overview ?? 'No description available.',
            style: GoogleFonts.dmSans(
              color: cs.onSurface.withValues(alpha: 0.75),
              fontSize: 15,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ).animate().fadeIn(delay: 300.ms),
        ],
      ),
    );
  }

  Widget _infoBadge(String text, IconData icon, {Color? iconColor}) {
    final cs = CupertinoTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? cs.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        if (_prevSlug != null)
          Expanded(
            child: _actionButton(
              icon: FluentIcons.rewind_24_filled,
              label: 'Previous',
              onTap: _onPrev,
            ),
          ),
        if (_prevSlug != null && _nextSlug != null) const SizedBox(width: 12),
        if (_nextSlug != null)
          Expanded(
            child: _actionButton(
              icon: FluentIcons.fast_forward_24_filled,
              label: 'Next',
              onTap: _onNext,
            ),
          ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: AppTheme.neonYellow,
          borderRadius: 4.0,
          shadowOffset: 3.0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: CupertinoColors.black, size: 18),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                color: CupertinoColors.black,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sidebar (wide screens) ──────────────────────────────────────────────────

  Widget _buildSidebar(CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(
            children: [
              _glassIconButton(
                padding: EdgeInsets.zero,
                icon: FluentIcons.chevron_left_24_regular,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 14),
              Text(
                'PLAYBACK SETTINGS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ],
          ),
        ),
        Container(height: 0.5, color: CupertinoColors.separator),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              _sidebarTile(
                icon: FluentIcons.movies_and_tv_24_regular,
                title: 'Video Quality (HLS)',
                subtitle: 'Internal quality tracks',
                onTap: _showVideoTrackSelection,
                theme: theme,
              ),
              _sidebarTile(
                icon: FluentIcons.music_note_2_24_regular,
                title: 'Audio Tracks',
                subtitle: 'Internal audio tracks',
                onTap: _showAudioSelection,
                theme: theme,
              ),
              _sidebarTile(
                icon: FluentIcons.library_24_regular,
                title: 'Change Server',
                subtitle: _selectedSource?.source ?? 'Select Source',
                onTap: _showSourcePicker,
                theme: theme,
              ),
              _sidebarTile(
                icon: FluentIcons.top_speed_24_regular,
                title: 'Playback Speed',
                subtitle: '${_videoPlayerController?.value.playbackSpeed ?? 1.0}x',
                onTap: _showSpeedPicker,
                theme: theme,
              ),
              if (_nextSlug != null)
                _sidebarTile(
                  icon: FluentIcons.next_24_filled,
                  title: 'Next Episode',
                  subtitle: 'Play the next one',
                  onTap: _onNext,
                  theme: theme,
                ),
              if (_prevSlug != null)
                _sidebarTile(
                  icon: FluentIcons.previous_24_filled,
                  title: 'Previous Episode',
                  subtitle: 'Go back to previous',
                  onTap: _onPrev,
                  theme: theme,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sidebarTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required CupertinoThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: isDark
              ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
              : const Color(0x77FFFFFF),
          borderRadius: 12.0,
          hasShadow: false,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: theme.primaryColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: CupertinoColors.systemGrey,
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Settings Sheet ──────────────────────────────────────────────────────────

  void _showSettingsSheet() {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Playback Settings'),
        message: const Text('Configure player properties'),
        actions: [
          CompactActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showSpeedPicker();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(FluentIcons.top_speed_24_regular, size: 16),
                const SizedBox(width: 8),
                Text('Playback Speed (${_videoPlayerController?.value.playbackSpeed ?? 1.0}x)'),
              ],
            ),
          ),
          CompactActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showVideoTrackSelection();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(FluentIcons.movies_and_tv_24_regular, size: 16),
                const SizedBox(width: 8),
                const Text('Video Quality (HLS)'),
              ],
            ),
          ),
          CompactActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showAudioSelection();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(FluentIcons.music_note_2_24_regular, size: 16),
                const SizedBox(width: 8),
                const Text('Audio Tracks (Internal)'),
              ],
            ),
          ),
          CompactActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showSourcePicker();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(FluentIcons.library_24_regular, size: 16),
                const SizedBox(width: 8),
                Text('Change Server (${_selectedSource?.source ?? 'Select Source'})'),
              ],
            ),
          ),
        ],
        cancelButton: CompactActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // ── Speed Picker ────────────────────────────────────────────────────────────

  void _showSpeedPicker() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final currentSpeed = _videoPlayerController?.value.playbackSpeed ?? 1.0;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Playback Speed'),
        message: const Text('Select speed multiplier'),
        actions: speeds.map((s) {
          final isCurrent = currentSpeed == s;
          return CompactActionSheetAction(
            onPressed: () {
              _videoPlayerController?.setPlaybackSpeed(s);
              Navigator.pop(ctx);
            },
            child: Text(
              '${s}x ${isCurrent ? "✓" : ""}',
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
        cancelButton: CompactActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // ── Source / Server Picker ──────────────────────────────────────────────────

  void _showSourcePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Change Server'),
        message: const Text('Select streaming provider'),
        actions: _sources.map((s) {
          final active = s == _selectedSource;
          final label = '${s.quality.isNotEmpty ? "${s.quality} · " : ""}${s.source}';
          
          return CompactActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              if (!active) {
                setState(() {
                  _selectedSource = s;
                  _loading = true;
                  _error = false;
                });
                _initPlayer(s.url);
              }
            },
            child: Text(
              '$label ${active ? "✓" : ""}',
              style: TextStyle(
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
        cancelButton: CompactActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // ── Video Quality (HLS internal tracks) ─────────────────────────────────────

  void _showVideoTrackSelection() {
    if (_mediaInfo == null || _mediaInfo.video == null) {
      _showToast('No internal video tracks available.\n'
          'For HLS, the player adapts quality automatically.\n'
          'Use "Change Server" to switch sources.');
      return;
    }

    final videoTracks = _mediaInfo.video as List;
    final activeTracks = _videoPlayerController?.getActiveVideoTracks() ?? [];

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Internal Video Tracks'),
        message: const Text('Select video stream track'),
        actions: List.generate(videoTracks.length, (index) {
          final track = videoTracks[index];
          final trackId = track.index ?? index;
          final isActive = activeTracks.contains(trackId);
          final codec = track.codec ?? 'Unknown';
          final label = 'Track ${index + 1} ($codec)';

          return CompactActionSheetAction(
            onPressed: () {
              _videoPlayerController?.setVideoTracks([trackId]);
              Navigator.pop(ctx);
            },
            child: Text(
              '$label ${isActive ? "✓" : ""}',
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }),
        cancelButton: CompactActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // ── Audio Track Selection ───────────────────────────────────────────────────

  void _showAudioSelection() {
    if (_mediaInfo == null || _mediaInfo.audio == null) {
      _showToast('No internal audio tracks available for this stream.');
      return;
    }

    final audioTracks = _mediaInfo.audio as List;
    final activeTracks = _videoPlayerController?.getActiveAudioTracks() ?? [];

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Audio Tracks'),
        message: const Text('Select embedded audio channel'),
        actions: List.generate(audioTracks.length, (index) {
          final track = audioTracks[index];
          final trackId = track.index ?? index;
          final lang = track.metadata?['language'] ?? 'Track ${index + 1}';
          final isActive = activeTracks.contains(trackId);

          return CompactActionSheetAction(
            onPressed: () {
              _videoPlayerController?.setAudioTracks([trackId]);
              Navigator.pop(ctx);
            },
            child: Text(
              '$lang (${track.codec ?? "Unknown"}) ${isActive ? "✓" : ""}',
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }),
        cancelButton: CompactActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  void _showToast(String message) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Playback Interrupted'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Go Back'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _loadPlayback();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── UI Helpers ──────────────────────────────────────────────────────────────

  Widget _dragHandle() {
    return Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context)
            .colorScheme
            .onSurfaceVariant
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _sheetOption({
    required IconData icon,
    required String label,
    required CupertinoColorScheme cs,
    required VoidCallback onTap,
  }) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: isDark ? const Color(0x771C1C1E) : const Color(0x77FFFFFF),
          borderRadius: 4.0,
          shadowOffset: 2.0,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: CupertinoColors.black, width: 1.5),
              ),
              child: Icon(icon, color: isDark ? CupertinoColors.black : CupertinoColors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ),
            Icon(
              FluentIcons.chevron_right_24_regular,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetTrackTile({
    required String label,
    required bool isActive,
    required IconData icon,
    required CupertinoColorScheme cs,
    required VoidCallback onTap,
  }) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: isActive
              ? AppTheme.neonYellow
              : (isDark ? const Color(0x771C1C1E) : const Color(0x77FFFFFF)),
          borderRadius: 4.0,
          shadowOffset: isActive ? 2.5 : 1.5,
        ),
        child: Row(
          children: [
            Icon(
              isActive ? FluentIcons.checkmark_circle_24_filled : icon,
              color: CupertinoColors.black,
              size: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: CupertinoColors.black,
                ),
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: CupertinoColors.black,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'ACTIVE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.neonYellow,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
