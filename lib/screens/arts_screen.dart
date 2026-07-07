import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wallpaper_manager_plus/wallpaper_manager_plus.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:media_store_plus/media_store_plus.dart';
import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';

class ArtsScreen extends StatefulWidget {
  const ArtsScreen({super.key});

  @override
  State<ArtsScreen> createState() => _ArtsScreenState();
}

class _ArtsScreenState extends State<ArtsScreen> {
  final String _apiKey = 'wCwCTx5e6SExjsLckZoDEyCIK4sNE1rbH6JenhPciPQlbvUDg7FDhChl';
  final Dio _dio = Dio();
  List<dynamic> _photos = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_loadingMore && _hasMore) {
        _fetchMorePhotos();
      }
    }
  }

  Future<void> _fetchPhotos({String? query}) async {
    setState(() {
      _loading = true;
      _page = 1;
      _photos = [];
      _hasMore = true;
    });
    try {
      final url = query != null && query.isNotEmpty
          ? 'https://api.pexels.com/v1/search?query=$query&per_page=30&page=$_page'
          : 'https://api.pexels.com/v1/curated?per_page=30&page=$_page';
      
      final response = await _dio.get(
        url,
        options: Options(headers: {'Authorization': _apiKey}),
      );

      if (mounted) {
        setState(() {
          _photos = response.data['photos'];
          _loading = false;
          _hasMore = response.data['next_page'] != null;
        });
      }
    } catch (e) {
      debugPrint('Error fetching photos: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchMorePhotos() async {
    setState(() => _loadingMore = true);
    _page++;
    try {
      final url = _query.isNotEmpty
          ? 'https://api.pexels.com/v1/search?query=$_query&per_page=30&page=$_page'
          : 'https://api.pexels.com/v1/curated?per_page=30&page=$_page';
      
      final response = await _dio.get(
        url,
        options: Options(headers: {'Authorization': _apiKey}),
      );

      if (mounted) {
        setState(() {
          _photos.addAll(response.data['photos']);
          _loadingMore = false;
          _hasMore = response.data['next_page'] != null;
        });
      }
    } catch (e) {
      debugPrint('Error fetching more photos: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final width = MediaQuery.of(context).size.width;
    
    int crossAxisCount = 2;
    if (width > 600) crossAxisCount = 3;
    if (width > 1000) crossAxisCount = 4;
    if (width > 1400) crossAxisCount = 5;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: Text('ARTS', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w900, letterSpacing: -1.0)),
            backgroundColor: CupertinoColors.transparent,
            border: null,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _fetchPhotos(query: _query),
              child: const Icon(FluentIcons.arrow_clockwise_24_regular, size: 22),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Search for arts...',
                onSubmitted: (val) {
                  setState(() => _query = val);
                  _fetchPhotos(query: val);
                },
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: IOSLoading(message: 'Exploring gallery...', size: 50)),
            )
          else if (_photos.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text('No results found')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  return _ArtCard(
                    photo: photo,
                    onTap: () => _showPhotoDetail(photo),
                  );
                },
                childCount: _photos.length,
              ),
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CupertinoActivityIndicator()),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  void _showPhotoDetail(dynamic photo) {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => ArtDetailScreen(photo: photo),
        fullscreenDialog: true,
      ),
    );
  }
}

class _ArtCard extends StatelessWidget {
  final dynamic photo;
  final VoidCallback onTap;

  const _ArtCard({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final double width = (photo['width'] as num).toDouble();
    final double height = (photo['height'] as num).toDouble();
    final double aspectRatio = width / height;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: AspectRatio(
          aspectRatio: aspectRatio.clamp(0.6, 1.8),
          child: Stack(
            children: [
              CachedNetworkImage(
                imageUrl: photo['src']['medium'],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => Container(color: CupertinoColors.systemGrey6),
                errorWidget: (_, __, ___) => const Icon(FluentIcons.image_24_regular),
              ),
              Positioned.fill(
                child: Container(
                  color: CupertinoColors.black.withValues(alpha: 0.05),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}

class ArtDetailScreen extends StatelessWidget {
  final dynamic photo;
  const ArtDetailScreen({super.key, required this.photo});

  Future<void> _downloadImage(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          // Continue anyway, as MediaStore API on Android 10+ handles this without storage permission.
        }
      }

      final url = photo['src']['original'];
      final tempDir = await getTemporaryDirectory();
      final fileName = 'StreamFlix_${photo['id']}.jpg';
      final path = '${tempDir.path}/$fileName';
      
      _showToast(context, 'Downloading image...');
      await Dio().download(url, path);
      
      if (Platform.isAndroid) {
        MediaStore.appFolder = "StreamFlix";
        final response = await MediaStore().saveFile(
          tempFilePath: path,
          dirType: DirType.download,
          dirName: DirType.download.defaults,
        );
        if (response != null) {
          _showToast(context, 'Saved to Downloads folder');
        } else {
          _showToast(context, 'Failed to save to Downloads');
        }
      } else {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          final targetPath = '${downloadsDir.path}/$fileName';
          await File(path).copy(targetPath);
          _showToast(context, 'Saved to Downloads folder');
        } else {
          final docDir = await getApplicationDocumentsDirectory();
          final targetPath = '${docDir.path}/$fileName';
          await File(path).copy(targetPath);
          _showToast(context, 'Saved to Documents folder');
        }
      }
    } catch (e) {
      _showToast(context, 'Download failed: $e');
    }
  }

  Future<void> _setWallpaper(BuildContext context) async {
    try {
      final url = photo['src']['large2x'] ?? photo['src']['original'];
      
      _showToast(context, 'Downloading wallpaper...');
      
      final file = await DefaultCacheManager().getSingleFile(url);
      
      if (context.mounted) {
        _showToast(context, 'Applying to Home Screen...');
      }

      final result = await WallpaperManagerPlus().setWallpaper(
        file,
        WallpaperManagerPlus.homeScreen,
      );

      if (context.mounted) {
        _showToast(context, result == "Wallpaper set successfully" || result.toString().contains("Success") 
          ? 'Wallpaper updated!' 
          : 'Failed: $result');
      }
    } catch (e) {
      if (context.mounted) _showToast(context, 'Error: $e');
    }
  }

  void _showToast(BuildContext context, String message) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
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

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: photo['src']['original'],
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(child: CupertinoActivityIndicator(color: CupertinoColors.white)),
              ),
            ),
          ),
          Positioned(
            top: 44,
            left: 16,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: CupertinoColors.black.withValues(alpha: 0.5),
                  child: CupertinoButton(
                    padding: const EdgeInsets.all(8),
                    minSize: 0,
                    onPressed: () => Navigator.pop(context),
                    child: const Icon(FluentIcons.chevron_left_24_regular, color: CupertinoColors.white, size: 24),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: (isDark 
                        ? (SettingsService.instance.isAmoled ? CupertinoColors.black : const Color(0xCC1C1C1E))
                        : const Color(0xCCFFFFFF)).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: CupertinoColors.white.withValues(alpha: isDark ? 0.08 : 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BY ${photo['photographer']}'.toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: isDark ? CupertinoColors.white : CupertinoColors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PROVIDED BY PEXELS',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => _downloadImage(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? CupertinoColors.white.withValues(alpha: 0.1)
                                      : CupertinoColors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      FluentIcons.arrow_download_24_regular,
                                      size: 20,
                                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'SAVE',
                                      style: GoogleFonts.spaceGrotesk(
                                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => _setWallpaper(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: theme.primaryColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(FluentIcons.phone_24_regular, size: 20, color: CupertinoColors.black),
                                    const SizedBox(width: 8),
                                    Text(
                                      'WALLPAPER',
                                      style: GoogleFonts.spaceGrotesk(
                                        color: CupertinoColors.black,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
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
          ),
        ],
      ),
    );
  }
}
