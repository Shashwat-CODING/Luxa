import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart' as material;

import 'package:fvp/fvp.dart';

import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../services/streaming_service.dart';
import '../models/api_models.dart';
import '../models/download_item.dart';
import '../services/watch_history.dart';
import '../services/settings_service.dart';
import '../widgets/native_ad_widget.dart';
import '../widgets/banner_ad_widget.dart';
import 'package:share_plus/share_plus.dart';




class PlayerScreen extends StatefulWidget {
  final MediaDetail? item;
  final int? season;
  final int? episode;
  final int initialIndex;
  final List<MediaDetail>? playlist;
  final String? offlinePath;

  const PlayerScreen({
    super.key,
    this.item,
    this.playlist,
    this.initialIndex = 0,
    this.season,
    this.episode,
    this.offlinePath,
    this.extras,
  });

  final Map<String, dynamic>? extras;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _api = ApiService.instance;
  final _streamService = StreamingService.instance;

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  dynamic _mediaInfo;

  bool _loading = true;
  bool _fetchingDubs = false;
  bool _error = false;
  String _errorMsg = '';

  List<StreamSource> _sources = [];
  StreamSource? _selectedSource;
  String? _selectedLanguage;

  // Tracks which CDN base URLs have fully failed.
  final Set<String> _failedCDNs = {};
  bool _isStreamDone = false;

  // FIX 2: _handlingError must always be reset, including in the "all failed" path.
  bool _handlingError = false;

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

  bool _isFullscreen = false;
  bool _hasSeeked = false;
  TvEpisode? _episodeDetail;

  Timer? _loadingTimer;
  int _messageIndex = 0;
  final List<String> _loadingMessages = [
    'Setting the stage...',
    'Finding best streams...',
    'Preparing stream...',
    'Polishing pixels...',
    'Almost ready...',
    'Rolling soon...',
  ];

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
  }

  void _stopLoadingAnimation() {
    _loadingTimer?.cancel();
    _loadingTimer = null;
  }

  @override
  void initState() {
    super.initState();
    // FIX 3: _currentIdx was set but never used — removed.

    WakelockPlus.enable().catchError((_) {});
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: CupertinoColors.transparent),
    );

    if (widget.item != null) {
      final extra =
          (widget.item!.mediaType == 'tv' &&
              widget.season != null &&
              widget.episode != null)
          ? 'S${widget.season} E${widget.episode}'
          : null;
      WatchHistory.addItem(
        MediaItem(
          id: widget.item!.id,
          title: widget.item!.title,
          overview: widget.item!.overview,
          posterPath: widget.item!.posterPath,
          backdropPath: widget.item!.backdropPath,
          voteAverage: widget.item!.voteAverage,
          releaseDate: widget.item!.releaseDate,
          mediaType: widget.item!.mediaType,
          extraInfo: extra,
          position: widget.item!.position,
          duration: widget.item!.duration,
          extras: widget.item!.extras,
        ),
        season: widget.season,
        episode: widget.episode,
      );
    }

    if (widget.offlinePath != null) {
      _initOfflinePlayer();
    } else if (widget.item != null) {
      _loadMovieStreams();
      if (widget.item!.mediaType == 'tv' &&
          widget.season != null &&
          widget.episode != null) {
        _loadEpisodeDetail();
      }
    }
  }

  void _initOfflinePlayer() {
    setState(() {
      _loading = false;
      _error = false;
    });
    _initPlayer(widget.offlinePath!);
  }

  Future<void> _loadEpisodeDetail() async {
    final ep = await _api.getTvEpisodeDetail(
      widget.item!.id,
      widget.season!,
      widget.episode!,
    );
    if (mounted) {
      setState(() => _episodeDetail = ep);
    }
  }

  Future<void> _loadMovieStreams() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = false;
      _sources = [];
      _selectedSource = null;
      _failedCDNs.clear();
      _isStreamDone = false;
      _handlingError = false;
      _selectedLanguage = null; // Reset on new movie/episode load
    });
    _startLoadingAnimation();

    final isTv = widget.item!.mediaType == 'tv';
    debugPrint(
      '\n🎬 Loading ${isTv ? "TV" : "Movie"} | tmdbId=${widget.item!.id}',
    );

    final stream = _streamService.getSources(
      widget.item!.mediaType,
      widget.item!.id,
      season: widget.season,
      episode: widget.episode,
      extras: widget.item!.extras ?? widget.extras,
    );

    stream.listen(
      (newSources) {
        if (!mounted) return;
        setState(() {
          _sources.addAll(newSources);
          // Sort by priority DESC (higher first), then by fileSize ASC (smaller first)
          _sources.sort((a, b) {
            final p = b.priority.compareTo(a.priority);
            if (p != 0) return p;

            // If priorities same, prefer smaller fileSize (0 means unknown, push to end)
            if (a.fileSize > 0 && b.fileSize > 0) {
              return a.fileSize.compareTo(b.fileSize);
            } else if (a.fileSize > 0) {
              return -1; // a is known, b is unknown, a first
            } else if (b.fileSize > 0) {
              return 1; // b is known, a is unknown, b first
            }

            return a.serverId.compareTo(b.serverId);
          });

          if (_selectedSource == null && _sources.isNotEmpty) {
            // Find first source whose CDN hasn't failed yet, preferring current language if set
            final bestSource = _sources.cast<StreamSource?>().firstWhere(
              (s) =>
                  s != null &&
                  !_failedCDNs.contains(_getCDN(s.url)) &&
                  (s.language == _selectedLanguage),
              orElse: () => _sources.cast<StreamSource?>().firstWhere(
                (s) => s != null && !_failedCDNs.contains(_getCDN(s.url)),
                orElse: () => null,
              ),
            );

            if (bestSource != null) {
              _selectedSource = bestSource;
              debugPrint('▶️  Starting with best available: $_selectedSource');
              _initPlayer(_selectedSource!.url);
            }
          }
        });
      },
      onDone: () {
        if (!mounted) return;
        _isStreamDone = true;

        final bool allSourcesFailed =
            _sources.isNotEmpty &&
            _sources.every((s) => _failedCDNs.contains(_getCDN(s.url)));

        if (_sources.isEmpty || allSourcesFailed) {
          final msg = allSourcesFailed
              ? 'All available servers failed to load. Please try again.'
              : 'No playback sources found for this ${isTv ? "show" : "movie"}.';
          setState(() {
            _loading = false;
            _error = true;
            _errorMsg = msg;
          });
          _stopLoadingAnimation();
          _showErrorCupertinoAlertDialog(msg);
          debugPrint('❌ No valid sources found after all servers checked');
        } else {
          debugPrint(
            '📦 Finished fetching all sources. Total: ${_sources.length}',
          );
        }
      },
      onError: (e) {
        debugPrint('❌ Stream error: $e');
        if (!mounted) return;
        if (_sources.isEmpty) {
          final msg = 'Error fetching sources: $e';
          setState(() {
            _loading = false;
            _error = true;
            _errorMsg = msg;
          });
          _stopLoadingAnimation();
          _showErrorCupertinoAlertDialog(msg);
        }
      },
    );
  }

  String _getCDN(String url) {
    try {
      final uri = Uri.parse(url);
      // If the URL is a proxying service, try to block the target host instead of the proxy itself.
      final target = uri.queryParameters['url'] ?? uri.queryParameters['link'];
      if (target != null && target.startsWith('http')) {
        final targetUri = Uri.parse(target);
        return '${targetUri.scheme}://${targetUri.host}';
      }
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return url;
    }
  }

  void _startDownload() async {
    if (widget.item == null) return;

    // Show loading dialog while fetching and validating dedicated download sources
    _showLoadingDownloadSourcesCupertinoAlertDialog();

    try {
      final downloadSources = await _streamService.fetchDownloadSources(
        widget.item!.mediaType,
        widget.item!.id,
        season: widget.season,
        episode: widget.episode,
      );

      if (!mounted) return;

      if (downloadSources.isEmpty) {
        Navigator.pop(context); // Pop loading dialog
        _showToast('No high-speed download sources found for this title.');
        return;
      }

      // Pre-validation pass — validate up to 5 sources in parallel (with timeout)
      final List<StreamSource> validSources = [];
      final results = await Future.wait(
        downloadSources.map((source) async {
          final Map<String, String> headers = {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
          };
          if (source.referer != null && source.referer!.isNotEmpty) {
            headers['Referer'] = source.referer!;
          }
          if (source.origin != null && source.origin!.isNotEmpty) {
            headers['Origin'] = source.origin!;
          }
          if (source.headers != null) headers.addAll(source.headers!);

          final code = await _preValidateUrl(source.url, headers);
          return (source, code);
        }),
        eagerError: false, // Keep going even if some fail
      );

      // Filter: accept anything that isn't a definitive failure (401, 403, 404, 410)
      // Status 200 = valid. We use _preValidateUrl which already normalises codes.
      for (final res in results) {
        final code = res.$2;
        if (code < 400 || code == 206) {
          validSources.add(res.$1);
        } else {
          debugPrint('🚫 Skipping download source (HTTP $code): ${res.$1.url}');
        }
      }

      // If validation filtered everything, pass all sources anyway to let Dio try
      final sourcesToOffer = validSources.isNotEmpty
          ? validSources
          : downloadSources;

      if (!mounted) return;
      Navigator.pop(context); // Pop loading dialog

      if (sourcesToOffer.isEmpty) {
        _showToast('No download sources available for this title. Please try again later.');
        return;
      }

      _showDownloadQualityCupertinoAlertDialog(sourcesToOffer);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showToast('Error preparing download links: $e');
      }
    }
  }

  void _showLoadingDownloadSourcesCupertinoAlertDialog() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: IOSLoading(message: 'Preparing download links...'),
      ),
    );
  }

  void _showDownloadQualityCupertinoAlertDialog(List<StreamSource> sources) {
    // Sort sources: Quality DESC, then Size DESC
    final sortedSources = List<StreamSource>.from(sources)
      ..sort((a, b) {
        final aInt =
            int.tryParse(a.quality.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final bInt =
            int.tryParse(b.quality.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return bInt.compareTo(aInt);
      });

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CompactActionSheet(
        title: const Text('Download Quality'),
        message: const Text('Select your preferred quality. Sources are optimized for speed.'),
        actions: sortedSources.map((source) {
          final sizeText = source.sizeText ?? 'Unknown size';
          return CompactActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _initiateDownload([source], 'DL');
            },
            child: Text('${source.quality} · $sizeText'),
          );
        }).toList(),
        cancelButton: CompactActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _initiateDownload(List<StreamSource> sList, String label) async {
    _showDownloadStatusCupertinoAlertDialog(widget.item!, label);

    try {
      await _streamService.startDownload(
        sList,
        widget.item!,
        sourceLabel: label,
      );
    } catch (e) {
      if (mounted) {
        _showToast(e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  void _showDownloadStatusCupertinoAlertDialog(MediaDetail item, String label) {
    bool timeoutReached = false;
    Timer? timeoutTimer;

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        timeoutTimer ??= Timer(const Duration(seconds: 15), () {
          if (mounted && Navigator.canPop(context)) {
            final download = _streamService.downloads
                .cast<DownloadItem?>()
                .firstWhere(
                  (d) =>
                      d?.mediaItem.id == item.id &&
                      d?.status == DownloadStatus.downloading,
                  orElse: () => null,
                );
            if (download == null) {
              setState(() => timeoutReached = true);
            }
          }
        });

        return ValueListenableBuilder<int>(
          valueListenable: StreamingService.listChanged,
          builder: (context, _, __) {
            final download = _streamService.downloads
                .cast<DownloadItem?>()
                .firstWhere(
                  (d) =>
                      d?.mediaItem.id == item.id &&
                      d?.status != DownloadStatus.completed &&
                      d?.status != DownloadStatus.failed,
                  orElse: () => null,
                );

            final theme = CupertinoTheme.of(context);
            final isStarted = download != null;

            if (download != null && download.progress >= 0.999) {
              timeoutTimer?.cancel();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                  showCupertinoDialog(
                    context: context,
                    builder: (context) => CupertinoAlertDialog(
                      title: const Text('Download Completed'),
                      content: const Text('Download completed successfully!'),
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              });
            }

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: CupertinoAlertDialog(
                title: Text(isStarted ? 'Download Started' : 'Searching...'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    if (timeoutReached && !isStarted)
                      _buildTimeoutContent()
                    else if (!isStarted)
                      const CupertinoActivityIndicator(radius: 15)
                    else
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: CupertinoActivityIndicator(
                              radius: 20,
                              color: theme.primaryColor,
                            ),
                          ),
                          Text(
                            '${(download.progress * 100).toInt()}%',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Text(
                      isStarted
                          ? 'Your download is in progress.'
                          : 'Searching for high-speed link...',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(fontSize: 14),
                    ),
                    if (isStarted) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton.filled(
                          onPressed: () {
                            timeoutTimer?.cancel();
                            Navigator.pop(context);
                          },
                          child: const Text('Close & Continue'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) => timeoutTimer?.cancel());
  }

  Widget _buildTimeoutContent() {
    final theme = CupertinoTheme.of(context);
    return Column(
      children: [
        const Icon(FluentIcons.warning_24_filled, color: CupertinoColors.systemOrange, size: 48),
        const SizedBox(height: 16),
        Text(
          'Server Not Responding',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Text(
          'This link is taking too long. Please switch to other sources or try another quality.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(fontSize: 13, color: CupertinoColors.systemGrey),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            color: CupertinoColors.systemRed,
            onPressed: () => Navigator.pop(context),
            child: const Text('Try Other Source'),
          ),
        ),
      ],
    );
  }

  // ── Stream error handler ────────────────────────────────────────────────────

  void _handleStreamError(dynamic error, {StreamSource? failedSource}) {
    if (_handlingError) {
      debugPrint(
        '🔒 [handleStreamError] Already handling — skipping duplicate',
      );
      return;
    }
    _handlingError = true;

    final source = failedSource ?? _selectedSource;
    if (source == null) {
      _handlingError = false;
      return;
    }

    debugPrint('\n⚠️  Stream failed: $source');
    debugPrint('   Reason: $error');

    final cdn = _getCDN(source.url);
    final wasAlreadyFailed = _failedCDNs.contains(cdn);
    _failedCDNs.add(cdn);

    if (wasAlreadyFailed) {
      debugPrint('🔒 CDN $cdn was already blocked — skipping');
      _handlingError = false;
      return;
    }

    debugPrint('🚫 Blocking all sources from CDN: $cdn');

    if (_sources.isNotEmpty) {
      // FIX 4: Use nullable firstWhere so orElse returns null instead of
      // _sources.first (which could itself be a failed server), avoiding
      // a false "all servers failed" when valid sources still exist.
      final nextSource = _sources.cast<StreamSource?>().firstWhere(
        (s) => s != null && !_failedCDNs.contains(_getCDN(s.url)),
        orElse: () => null,
      );

      if (nextSource != null) {
        debugPrint('⏭️  Falling back to: $nextSource');
        if (mounted) {
          setState(() {
            _selectedSource = nextSource;
            _loading = true;
            _error = false;
          });
          _startLoadingAnimation();
        }
        // FIX 5: Reset guard BEFORE calling _initPlayer so errors
        // from the new source can be caught and handled correctly.
        _handlingError = false;
        _initPlayer(nextSource.url);
        return;
      }
    }

    if (!_isStreamDone) {
      debugPrint(
        '⏳ All known sources failed, but stream is still fetching. Waiting...',
      );
      _handlingError = false;
      _selectedSource =
          null; // Ensures stream listener will pick up a new source if it appears
      return;
    }

    // FIX 6: Reset guard in the "all servers failed" path too —
    // was previously left true, permanently blocking future error handling.
    debugPrint('❌ All servers failed. Showing error screen.');
    _handlingError = false;
    if (mounted) {
      final msg = 'All available servers failed to load.\n${error.toString()}';
      setState(() {
        _loading = false;
        _error = true;
        _errorMsg = msg;
      });
      _showErrorCupertinoAlertDialog(msg);
      _stopLoadingAnimation();
    }
  }

  Future<void> _initPlayer(
    String url, {
    String? referrer,
    String? userAgent,
  }) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    _startLoadingAnimation();

    final bool skipHeaders = _selectedSource?.noHeaders == true;
    final Map<String, String> headers = skipHeaders
        ? {}
        : {
            'Referer':
                _selectedSource?.resolvedReferer ??
                referrer ??
                'https://rivestream.app/',
            'Origin':
                _selectedSource?.resolvedOrigin ??
                referrer ??
                'https://rivestream.app',
            'User-Agent':
                userAgent ??
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
          };

    if (!skipHeaders && _selectedSource?.headers != null) {
      // Overwrite default headers with any dynamically provided headers from the source.
      headers.addAll(_selectedSource!.headers!);
    }

    // Stop and dispose old controller immediately to avoid background audio/video playing
    _chewieController?.dispose();
    _chewieController = null;
    _videoPlayerController?.pause();
    _videoPlayerController?.dispose();
    _videoPlayerController = null;

    // Ensure we show loading state while pre-validating
    if (mounted && !_loading) {
      setState(() => _loading = true);
    }

    // FIX 7: Pre-validate URL with a HEAD request before handing to video_player.
    // This catches immediate 404s in ~8s instead of waiting for libmpv's
    // full internal timeout (which can be several minutes).
    final isLocal = url.startsWith('file://');
    final isServer6 = _selectedSource?.serverId == 6;
    if (isServer6) {
      debugPrint('ℹ️ [PLAYER] Server 6 detected. Skipping pre-validation as requested.');
    }
    final statusCode = isServer6
        ? 200
        : (isLocal
            ? (await File(url.replaceFirst('file://', '')).exists() ? 200 : 404)
            : await _preValidateUrl(url, headers));

    if (!mounted) return;

    if (statusCode >= 400) {
      if (statusCode == 403 || statusCode == 401 || statusCode == 410) {
        debugPrint(
          '🚫 Terminal error ($statusCode) for Server ${_selectedSource?.serverId}. Removing from priority list.',
        );
        setState(() {
          _sources.removeWhere((s) => s.url == url);
        });
      }

      debugPrint(
        '❌ ${isLocal ? "Local file not found" : "Pre-validation failed ($statusCode) for Server ${_selectedSource?.serverId}"}',
      );
      _handleStreamError(
        isLocal
            ? 'Local video file missing or moved.'
            : 'URL pre-validation failed ($statusCode)',
        failedSource: _selectedSource,
      );
      return;
    }

    try {
      if (!mounted) return;

      if (isLocal) {
        _videoPlayerController = VideoPlayerController.file(
          File(url.replaceFirst('file:///', '')),
        );
      } else {
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: headers,
        );
      }

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
        if (!_hasSeeked && widget.item?.position != null) {
          _hasSeeked = true;
          await _videoPlayerController!.seekTo(
            Duration(milliseconds: widget.item!.position!),
          );
        }
        _videoPlayerController!.play();
      }
    } catch (e) {
      debugPrint(
        '❌ Player init exception for Server ${_selectedSource?.serverId}: $e',
      );
      _handleStreamError(e, failedSource: _selectedSource);
    }
  }

  /// Validates a URL by sending a HEAD request first, then falling back to a
  /// partial GET. Returns an HTTP status code. Returns 200 for local files.
  /// Returns 200 even for 4xx Range-related codes (206, 416) since many CDNs
  /// block partial-content requests but serve the full file correctly.
  Future<int> _preValidateUrl(String url, Map<String, String> headers) async {
    if (url.startsWith('file://')) return 200;
    try {
      final client = Dio();
      client.options.connectTimeout = const Duration(seconds: 8);
      client.options.receiveTimeout = const Duration(seconds: 8);
      client.options.sendTimeout = const Duration(seconds: 8);

      final requestHeaders = Map<String, String>.from(headers);
      // Remove Range — many CDNs reject it and it's not needed for validation
      requestHeaders.remove('Range');
      requestHeaders.remove('range');

      final response = await client.head(
        url,
        options: Options(
          headers: requestHeaders,
          validateStatus: (s) => true, // Accept all codes — we check manually
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

      final statusCode = response.statusCode ?? 500;
      final contentType = (response.headers.value('content-type') ?? '')
          .toLowerCase();

      debugPrint(
        '   Pre-validate HEAD: $statusCode | Type: $contentType | $url',
      );

      // HTML response = error/login page, not a real stream
      if (contentType.contains('text/html')) {
        debugPrint('   ❌ Received HTML — not a valid stream source.');
        return 406;
      }

      // 405 = HEAD not allowed, but the file may be valid — try GET with no range
      if (statusCode == 405 || statusCode == 501) {
        debugPrint(
          '   ⚠️  HEAD not supported ($statusCode), trying GET fallback...',
        );
        return await _preValidateWithGet(url, requestHeaders, client);
      }

      // 2xx, 3xx = valid
      if (statusCode < 400) return 200;

      // 401/403/410 = definitively bad
      return statusCode;
    } catch (e) {
      debugPrint('   Pre-validate exception: $e');
      // On timeout/connection failure, assume source may still be valid (let player try it)
      return 200;
    }
  }

  /// Fallback GET-based validator when HEAD is rejected.
  Future<int> _preValidateWithGet(
    String url,
    Map<String, String> headers,
    Dio client,
  ) async {
    try {
      final response = await client.get(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          validateStatus: (s) => true,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );
      final statusCode = response.statusCode ?? 500;
      final contentType = (response.headers.value('content-type') ?? '')
          .toLowerCase();

      // Close stream immediately — we only needed the headers
      try {
        final stream = response.data as ResponseBody?;
        await stream?.stream.drain();
      } catch (_) {}

      debugPrint(
        '   Pre-validate GET fallback: $statusCode | Type: $contentType | $url',
      );

      if (contentType.contains('text/html')) return 406;
      if (statusCode < 400) return 200;
      return statusCode;
    } catch (e) {
      debugPrint('   GET fallback exception: $e');
      return 200; // On error, let the player try
    }
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

  void _saveProgress() {
    if (widget.item == null ||
        _videoPlayerController == null ||
        !_videoPlayerController!.value.isInitialized)
      return;
    if (_videoPlayerController!.value.duration.inMilliseconds <= 0) return;

    final pos = _videoPlayerController!.value.position.inMilliseconds;
    final dur = _videoPlayerController!.value.duration.inMilliseconds;

    // If watched > 95%, we consider it finished and don't save progress
    // (or we save 0 so it's not in "Continue Watching" with 1 min left)
    final progress = pos / dur;
    final finalPos = progress > 0.95 ? 0 : pos;

    WatchHistory.addItem(
      MediaItem(
        id: widget.item!.id,
        title: widget.item!.title,
        overview: widget.item!.overview,
        posterPath: widget.item!.posterPath,
        backdropPath: widget.item!.backdropPath,
        voteAverage: widget.item!.voteAverage,
        releaseDate: widget.item!.releaseDate,
        mediaType: widget.item!.mediaType,
        extraInfo:
            (widget.item!.mediaType == 'tv' &&
                widget.season != null &&
                widget.episode != null)
            ? 'S${widget.season} E${widget.episode}'
            : null,
        position: finalPos,
        duration: dur,
      ),
    );
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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isFullscreen) {
      return Shortcuts(
        shortcuts: _shortcuts,
        child: Actions(
          actions: _actions,
          child: Focus(
            autofocus: true,
          child: CupertinoPageScaffold(
            backgroundColor: CupertinoColors.black,
            child: Stack(
                children: [
                  Center(child: _buildVideoContainer()),
                  // Remove _buildFloatingTopBar from over player in fullscreen
                  //                  Positioned(
                  //                    top: 0,
                  //                    left: 0,
                  //                    right: 0,
                  //                    child: SafeArea(child: _buildFloatingTopBar()),
                  //                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final theme = CupertinoTheme.of(context);
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: _actions,
        child: Focus(
          autofocus: true,
          child: CupertinoPageScaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 950;
                final cs = theme.colorScheme;

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                24,
                                24,
                                16,
                              ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ).copyWith(bottom: 40),
                                child: _buildMovieInfo(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        color: CupertinoColors.separator.withValues(alpha: 0.2),
                      ),
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
                        // Remove _buildFloatingTopBar from over player
                        //                        Positioned(
                        //                          top: 0,
                        //                          left: 0,
                        //                          right: 0,
                        //                          child: SafeArea(child: _buildFloatingTopBar()),
                        //                        ),
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const NativeAdWidget(
                              size: NativeAdSize.small,
                            ), // First Ad (Small)
                            if (widget.item != null) _buildMovieInfo(),
                            const NativeAdWidget(
                              size: NativeAdSize.medium,
                            ), // Second Ad (Medium)
                            BannerAdWidget(), // Third Ad (Banner)
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

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
              const SizedBox(width: 16),
              Text(
                'PLAYBACK SETTINGS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
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
                icon: FluentIcons.video_clip_24_regular,
                title: 'Resolution',
                subtitle: 'Auto',
                onTap: _showVideoTrackSelection,
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
                icon: FluentIcons.globe_24_regular,
                title: 'Language (Sources)',
                subtitle: _selectedLanguage ?? 'Original',
                onTap: _showLanguageSelection,
                theme: theme,
              ),
              _sidebarTile(
                icon: FluentIcons.sound_wave_circle_24_regular,
                title: 'Regional Dubs (Server 2)',
                subtitle: 'Fetch dubbed versions',
                onTap: _fetchingDubs ? () {} : _fetchAndShowDubs,
                theme: theme,
              ),
              _sidebarTile(
                icon: FluentIcons.music_note_2_24_regular,
                title: 'Audio Tracks (Internal)',
                subtitle: 'Internal embedded tracks',
                onTap: _showAudioSelection,
                theme: theme,
              ),
              _sidebarTile(
                icon: FluentIcons.arrow_circle_down_24_regular,
                title: 'Download Video',
                subtitle: 'Save for offline viewing',
                onTap: _startDownload,
                theme: theme,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 10),
                child: Text(
                  'SHORTCUTS',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ),
              const _ShortcutInfo(keyLabel: 'Space', action: 'Play / Pause'),
              const _ShortcutInfo(keyLabel: 'F', action: 'Fullscreen'),
              const _ShortcutInfo(keyLabel: '← / →', action: 'Seek 10s'),
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

  Widget _buildDownloadProgressOverlay() {
    final curItem = widget.item;
    if (curItem == null) return const SizedBox.shrink();

    return ValueListenableBuilder<int>(
      valueListenable: StreamingService.listChanged,
      builder: (context, _, __) {
        final downloads = StreamingService.instance.downloads
            .where(
              (d) =>
                  d.mediaItem.id == curItem.id &&
                  (d.status == DownloadStatus.downloading ||
                      d.status == DownloadStatus.paused),
            )
            .toList();

        if (downloads.isEmpty) return const SizedBox.shrink();

        final download = downloads.first;
        return Container(
          margin: const EdgeInsets.only(left: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.neonPink,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (download.status == DownloadStatus.downloading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CupertinoActivityIndicator(
                    color: CupertinoColors.white,
                  ),
                )
              else
                const Icon(
                  FluentIcons.pause_24_filled,
                  size: 14,
                  color: CupertinoColors.white,
                ),
              const SizedBox(width: 8),
              Text(
                '${(download.progress * 100).toInt()}%',
                style: GoogleFonts.inter(
                  color: CupertinoColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
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
          _buildDownloadProgressOverlay(),
          const Spacer(),
          const SizedBox(width: 48), // Spacer to balance the back button
        ],
      ),
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

  Widget _buildVideoContainer() {
    if (_loading) return _buildLoadingView();
    if (_error) {
      return Container(
        color: CupertinoColors.black,
        child: Center(
          child: Icon(
            FluentIcons.video_clip_24_filled,
            color: CupertinoColors.white.withValues(alpha: 0.1),
            size: 64,
          ),
        ),
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
        if (_fetchingDubs) _buildFetchingOverlay(),
      ],
    );
  }

  Widget _buildFetchingOverlay() {
    return Container(
      color: const Color(0x8A000000),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(color: CupertinoColors.white),
            SizedBox(height: 16),
            Text(
              'Fetching dubbed versions...',
              style: TextStyle(
                color: CupertinoColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ── Bottom Sheets ───────────────────────────────────────────────────────────

  void _showSettingsSheet() {
    final cs = CupertinoTheme.of(context).colorScheme;
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
              _showSpeedSelector();
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
          if (widget.item?.mediaType == 'tv')
            CompactActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _showEpisodeSelector();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(FluentIcons.list_24_regular, size: 16),
                  const SizedBox(width: 8),
                  const Text('Episodes'),
                ],
              ),
            ),
          CompactActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _startDownload();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(FluentIcons.arrow_circle_down_24_regular, size: 16),
                const SizedBox(width: 8),
                const Text('Download Video'),
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
              _showLanguageSelection();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(FluentIcons.globe_24_regular, size: 16),
                const SizedBox(width: 8),
                Text('Change Language (Dubs) (${_selectedLanguage ?? 'Original'})'),
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

  void _showSpeedSelector() {
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

  Future<void> _fetchAndShowDubs() async {
    if (widget.item == null) return;

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: IOSLoading(message: 'Fetching regional dubs...'),
      ),
    );

    try {
      final dubs = await _streamService.getSpecificServerSources(
        widget.item!.mediaType,
        widget.item!.id,
        2, // Server 2 is for Dubs
        season: widget.season,
        episode: widget.episode,
      );

      if (!mounted) return;
      Navigator.pop(context); // Remove loading dialog

      final filteredSources = dubs;
      if (filteredSources.isEmpty) {
        _showToast('No dubs available on Server 2');
        return;
      }

      if (mounted) {
        _showDubsPicker(filteredSources);
      }
    } catch (error) {
      if (mounted) {
        Navigator.pop(context);
        _showToast('Failed to fetch dubs');
      }
    }
  }

  void _showDubsPicker(List<StreamSource> sources) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Available Dubs (Server 2)'),
        message: const Text('Select dub variant'),
        actions: sources.map((s) {
          final active = s == _selectedSource;
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
              '${s.source}${s.language != null && s.language != "null" && s.language!.isNotEmpty ? " (${s.language})" : ""} ${active ? "✓" : ""}',
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

  void _applyNewSource(StreamSource source) async {
    final pos = _videoPlayerController?.value.position ?? Duration.zero;
    setState(() {
      _selectedSource = source;
      _selectedLanguage = source.language;
      _loading = true;
      // Ensure the newly selected source (e.g. a dub) is in the sources list
      if (!_sources.any((s) => s.url == source.url)) {
        _sources.add(source);
      }
    });

    await _initPlayer(source.url);
    if (_videoPlayerController != null) {
      await _videoPlayerController!.seekTo(pos);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showLanguageSelection() {
    final languages = _sources
        .map((s) => s.language)
        .whereType<String>()
        .toSet()
        .toList();
    languages.insert(0, 'Original');

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Select Language'),
        message: const Text('Choose audio track language'),
        actions: languages.map((lang) {
          final actualLang = lang == 'Original' ? null : lang;
          final isActive = _selectedLanguage == actualLang;
          return CompactActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              if (!isActive) {
                _changeLanguage(actualLang);
              }
            },
            child: Text(
              '$lang ${isActive ? "✓" : ""}',
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
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

  void _changeLanguage(String? language) async {
    debugPrint('🌐 Changing language to: ${language ?? "Original"}');

    // Find best source matching new language
    final nextSource = _sources.cast<StreamSource?>().firstWhere(
      (s) =>
          s != null &&
          !_failedCDNs.contains(_getCDN(s.url)) &&
          s.language == language,
      orElse: () => _sources.cast<StreamSource?>().firstWhere(
        (s) => s != null && !_failedCDNs.contains(_getCDN(s.url)),
        orElse: () => null,
      ),
    );

    if (nextSource != null) {
      if (mounted) {
        setState(() {
          _selectedLanguage = language;
          _selectedSource = nextSource;
          _loading = true;
          _error = false;
        });
      }
      _initPlayer(nextSource.url);
    }
  }

  void _showAudioSelection() {
    if (_mediaInfo == null || _mediaInfo.audio == null) {
      _showToast('No audio tracks available');
      return;
    }

    final audioTracks = _mediaInfo.audio as List;
    final activeTracks = _videoPlayerController?.getActiveAudioTracks() ?? [];

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Internal Audio Tracks'),
        message: const Text('Select embedded track'),
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

  void _showVideoTrackSelection() {
    if (_mediaInfo == null || _mediaInfo.video == null) {
      _showToast('No video tracks available');
      return;
    }

    final videoTracks = _mediaInfo.video as List;
    final activeTracks = _videoPlayerController?.getActiveVideoTracks() ?? [];

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Internal Video Tracks'),
        message: const Text('Select stream rendering track'),
        actions: List.generate(videoTracks.length, (index) {
          final track = videoTracks[index];
          final trackId = track.index ?? index;
          final isActive = activeTracks.contains(trackId);
          final codec = track.codec ?? "Unknown";

          return CompactActionSheetAction(
            onPressed: () {
              _videoPlayerController?.setVideoTracks([trackId]);
              Navigator.pop(ctx);
            },
            child: Text(
              'Track $index ($codec) ${isActive ? "✓" : ""}',
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

  void _showSourcePicker() {
    final availableSources = _sources
        .where((s) => !_failedCDNs.contains(_getCDN(s.url)))
        .toList();

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: const Text('Change Server'),
        message: const Text('Select a streaming server'),
        actions: availableSources.map((source) {
          final isCurrent = _selectedSource?.url == source.url;
          return CompactActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              if (!isCurrent) {
                _applyNewSource(source);
              }
            },
            child: Text(
              '${source.source}${source.language != null && source.language != "null" && source.language!.isNotEmpty ? " (${source.language})" : ""} ${isCurrent ? "✓" : ""}',
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

  Widget _dragHandle() {
    return Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
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
              size: 18,
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
          shadowOffset: isActive ? 2.5 : 0.0,
          hasShadow: isActive,
        ),
        child: Row(
          children: [
            Icon(
              isActive ? FluentIcons.checkmark_circle_24_filled : icon,
              color: isActive
                  ? CupertinoColors.black
                  : (isDark ? CupertinoColors.white : CupertinoColors.black),
              size: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: isActive
                      ? CupertinoColors.black
                      : (isDark ? CupertinoColors.white : CupertinoColors.black),
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
                    fontSize: 10,
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

  // ── Loading & Error views ───────────────────────────────────────────────────

  Widget _buildLoadingView() {
    final cs = CupertinoTheme.of(context).colorScheme;
    return Container(
      color: CupertinoColors.black,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const IOSLoading(size: 64),
              const SizedBox(height: 32),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: animation.drive(
                        Tween(
                          begin: const Offset(0.0, 0.2),
                          end: Offset.zero,
                        ).chain(CurveTween(curve: Curves.easeOutCubic)),
                      ),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  _loadingMessages[_messageIndex],
                  key: ValueKey<int>(_messageIndex),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSerifDisplay(
                    color: cs.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorCupertinoAlertDialog(String message) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Playback Interrupted'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _loadMovieStreams();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  // ── Info sections ───────────────────────────────────────────────────────────

  Widget _buildMovieInfo() {
    final item = widget.item!;
    final cs = CupertinoTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (_episodeDetail != null)
                    ? 'S${widget.season} E${widget.episode}: ${_episodeDetail!.name}'
                    : item.title,
                style: GoogleFonts.dmSerifDisplay(
                  fontSize: 28, // Reduced slightly for long episode titles
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: -1.0,
                  color: cs.onSurface,
                ),
              ).animate().fadeIn().slideX(begin: -0.05),
              if (_episodeDetail != null) ...[
                const SizedBox(height: 4),
                Text(
                  item.title,
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
                  _infoBadge(item.year, FluentIcons.calendar_24_regular),
                  _infoBadge(
                    item.ratingStr,
                    FluentIcons.star_24_filled,
                    iconColor: CupertinoColors.systemYellow,
                  ),
                  if (item.runtime != null)
                    _infoBadge('${item.runtime}m', FluentIcons.clock_24_regular),
                ],
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 24),
              _buildActionRow()
                  .animate()
                  .fadeIn(delay: 150.ms)
                  .slideY(begin: 0.1),
            ],
          ),
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
            _episodeDetail?.overview ??
                item.overview ??
                'No description available.',
            style: GoogleFonts.dmSans(
              color: cs.onSurface.withValues(alpha: 0.75),
              fontSize: 15,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 40),
          Text(
            'TOP CAST',
            style: GoogleFonts.dmSans(
              color: cs.primary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: item.cast.length.clamp(0, 10),
              separatorBuilder: (_, _) => const SizedBox(width: 20),
              itemBuilder: (_, i) {
                final p = item.cast[i];
                return Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.surfaceContainerHighest,
                        image: p.fullProfileUrl.isNotEmpty
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(p.fullProfileUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: p.fullProfileUrl.isEmpty
                          ? Icon(
                              FluentIcons.person_24_filled,
                              color: cs.onSurfaceVariant,
                              size: 32,
                            )
                          : null,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 72,
                      child: Text(
                        p.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ).animate().fadeIn(delay: 500.ms).slideX(begin: 0.1),
        ],
      ),
    );
  }

  Widget _infoBadge(String label, IconData icon, {Color? iconColor}) {
    final cs = CupertinoTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor ?? cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _actionChip(
            icon: FluentIcons.chevron_left_24_regular,
            label: 'Back',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          _actionChip(
            icon: FluentIcons.settings_24_regular,
            label: 'Settings',
            onTap: _showSettingsSheet,
          ),
          const SizedBox(width: 8),
          _actionChip(
            icon: FluentIcons.sound_wave_circle_24_regular,
            label: 'Dubs',
            onTap: _fetchAndShowDubs,
          ),
          if (widget.item?.mediaType == 'tv') ...[
            const SizedBox(width: 8),
            _actionChip(
              icon: FluentIcons.list_24_regular,
              label: 'Episodes',
              onTap: _showEpisodeSelector,
            ),
          ],
          const SizedBox(width: 8),
          _actionChip(
            icon: FluentIcons.arrow_download_24_regular,
            label: 'Download',
            onTap: _startDownload,
          ),
          const SizedBox(width: 8),
          _actionChip(
            icon: FluentIcons.share_24_regular,
            label: 'Share',
            onTap: () {
              if (widget.item == null) return;
              String url;
              if (widget.item?.mediaType == 'tv' && widget.season != null && widget.episode != null) {
                url = '${ApiService.websiteUrl}/watch?type=tv&id=${widget.item!.id}&s=${widget.season}&e=${widget.episode}';
              } else {
                final type = widget.item?.mediaType ?? 'movie';
                url = '${ApiService.websiteUrl}/watch?type=$type&id=${widget.item?.id}';
              }
              Share.share(
                'Check out "${widget.item?.title}" on Luxa!\n\nWatch here: $url',
                subject: 'Share ${widget.item?.title}',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: isDark ? const Color(0x771C1C1E) : const Color(0x77FFFFFF),
          borderRadius: 4.0,
          shadowOffset: 2.0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isDark ? CupertinoColors.white : CupertinoColors.black),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEpisodeSelector() {
    if (widget.item == null || widget.item!.mediaType != 'tv') return;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => ConstrainedBottomSheet(
        child: _PlayerEpisodeSelectorSheet(
          tvDetail: widget.item!,
          currentSeason: widget.season,
          currentEpisode: widget.episode,
          onEpisodeSelected: (s, e) {
            Navigator.pushReplacement(
              context,
              CupertinoPageRoute(
                builder: (_) =>
                  PlayerScreen(item: widget.item, season: s, episode: e),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Keyboard Shortcuts ──────────────────────────────────────────────────────

  late final Map<ShortcutActivator, Intent> _shortcuts = {
    const SingleActivator(LogicalKeyboardKey.space): const _PlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.keyF):
        const _ToggleFullscreenIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const _SeekForwardIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const _SeekBackwardIntent(),
  };

  late final Map<Type, Action<Intent>> _actions = {
    _PlayPauseIntent: CallbackAction<_PlayPauseIntent>(
      onInvoke: (_) => setState(() {
        if (_videoPlayerController?.value.isPlaying == true) {
          _videoPlayerController?.pause();
        } else {
          _videoPlayerController?.play();
        }
      }),
    ),
    _ToggleFullscreenIntent: CallbackAction<_ToggleFullscreenIntent>(
      onInvoke: (_) => _toggleFullscreen(),
    ),
    _SeekForwardIntent: CallbackAction<_SeekForwardIntent>(
      onInvoke: (_) {
        final currentPos =
            _videoPlayerController?.value.position ?? Duration.zero;
        _videoPlayerController?.fastSeekTo(
          currentPos + const Duration(seconds: 10),
        );
        return null;
      },
    ),
    _SeekBackwardIntent: CallbackAction<_SeekBackwardIntent>(
      onInvoke: (_) {
        final currentPos =
            _videoPlayerController?.value.position ?? Duration.zero;
        _videoPlayerController?.fastSeekTo(
          currentPos - const Duration(seconds: 10),
        );
        return null;
      },
    ),
  };
}

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _ToggleFullscreenIntent extends Intent {
  const _ToggleFullscreenIntent();
}

class _SeekForwardIntent extends Intent {
  const _SeekForwardIntent();
}

class _SeekBackwardIntent extends Intent {
  const _SeekBackwardIntent();
}

class _ShortcutInfo extends StatelessWidget {
  final String keyLabel;
  final String action;

  const _ShortcutInfo({required this.keyLabel, required this.action});

  @override
  Widget build(BuildContext context) {
    final cs = CupertinoTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              keyLabel,
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            action,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
// ── Private Widgets for Player Episode Selection ────────────────────────────

class _PlayerEpisodeSelectorSheet extends StatefulWidget {
  final MediaDetail tvDetail;
  final int? currentSeason;
  final int? currentEpisode;
  final void Function(int season, int episode)? onEpisodeSelected;

  const _PlayerEpisodeSelectorSheet({
    required this.tvDetail,
    this.currentSeason,
    this.currentEpisode,
    this.onEpisodeSelected,
  });

  @override
  State<_PlayerEpisodeSelectorSheet> createState() =>
      _PlayerEpisodeSelectorSheetState();
}

class _PlayerEpisodeSelectorSheetState
    extends State<_PlayerEpisodeSelectorSheet> {
  late TvSeason _selectedSeason;
  List<TvEpisode> _episodes = [];
  bool _loading = false;
  final _api = ApiService.instance;

  @override
  void initState() {
    super.initState();
    // Default to current season or first season
    _selectedSeason = widget.tvDetail.seasons.firstWhere(
      (s) => s.seasonNumber == (widget.currentSeason ?? 1),
      orElse: () => widget.tvDetail.seasons.firstWhere(
        (s) => s.seasonNumber > 0,
        orElse: () => widget.tvDetail.seasons.first,
      ),
    );
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    setState(() => _loading = true);
    final season = await _api.getTvSeasonDetail(
      widget.tvDetail.id,
      _selectedSeason.seasonNumber,
    );
    if (mounted) {
      setState(() {
        _episodes = season?.episodes ?? [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final cs = CupertinoTheme.of(context).colorScheme;

    return GlassBox(
      color: isDark ? AppTheme.darkSlate : AppTheme.creamBg,
      borderRadius: 14.0,
      child: Container(
        height: size.height * 0.8,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? CupertinoColors.white.withValues(alpha: 0.12)
                            : CupertinoColors.black.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 20),
              child: Row(
                children: [
                  Text(
                    'Episodes',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        showCupertinoModalPopup(
                          context: context,
                          builder: (ctx) => CompactActionSheet(
                            title: const Text('Select Season'),
                            actions: widget.tvDetail.seasons.map((s) {
                              return CompactActionSheetAction(
                                child: Text(s.name),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  setState(() => _selectedSeason = s);
                                  _loadEpisodes();
                                },
                              );
                            }).toList(),
                            cancelButton: CompactActionSheetAction(
                              child: const Text('Cancel'),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedSeason?.name ?? 'Select Season',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            FluentIcons.chevron_down_24_regular, 
                            size: 14, 
                            color: isDark ? CupertinoColors.white : CupertinoColors.black
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 0.5, color: CupertinoColors.separator),
          Expanded(
            child: _loading
                ? const Center(child: IOSLoading(message: 'Loading episodes...'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _episodes.length,
                    itemBuilder: (_, i) => _PlayerEpisodeTile(
                      episode: _episodes[i],
                      isCurrent:
                          _episodes[i].episodeNumber == widget.currentEpisode &&
                          _episodes[i].seasonNumber == widget.currentSeason,
                      onTap: () {
                        if (widget.onEpisodeSelected != null) {
                          Navigator.pop(context);
                          widget.onEpisodeSelected!(
                            _episodes[i].seasonNumber,
                            _episodes[i].episodeNumber,
                          );
                        }
                      },
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
}

class _PlayerEpisodeTile extends StatelessWidget {
  final TvEpisode episode;
  final bool isCurrent;
  final VoidCallback onTap;

  const _PlayerEpisodeTile({
    required this.episode,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCurrent
            ? theme.primaryColor
            : (isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isCurrent 
              ? theme.primaryColor 
              : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: episode.fullStillUrl,
                  width: 100,
                  height: 60,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 100,
                    height: 60,
                    color: isDark ? AppTheme.pureBlack : CupertinoColors.systemGrey5,
                    child: Icon(
                      FluentIcons.movies_and_tv_24_regular,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Episode ${episode.episodeNumber}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? CupertinoColors.white : CupertinoColors.systemGrey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      episode.name,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? CupertinoColors.white : (isDark ? CupertinoColors.white : CupertinoColors.black),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                const Icon(
                  FluentIcons.play_circle_24_filled,
                  color: CupertinoColors.white,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
