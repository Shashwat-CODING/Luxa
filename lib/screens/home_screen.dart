import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import 'detail_screen.dart';
import '../services/watch_history.dart';
import 'search_screen.dart';
import '../widgets/native_ad_widget.dart';
import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSearch;
  const HomeScreen({super.key, this.onSearch});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService.instance;
  List<MediaItem> _trending = [];
  List<MediaItem> _popularMovies = [];
  List<MediaItem> _nowPlayingMovies = [];
  List<MediaItem> _animeMovies = [];
  List<MediaItem> _trendingTv = [];
  List<MediaItem> _popularTv = [];
  List<MediaItem> _topRatedTv = [];
  List<MediaItem> _airingTodayTv = [];
  bool _loading = true;

  int _heroIndex = 0;
  Timer? _heroTimer;
  final PageController _heroController = PageController(viewportFraction: 1.0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.getTrendingMovies(),
      _api.getPopularMovies(),
      _api.getNowPlayingMovies(),
      _api.getAnimeMovies(),
      _api.getTrendingTv(),
      _api.getPopularTvShows(),
      _api.getTopRatedTvShows(),
      _api.getAiringTodayTv(),
    ]);
    if (mounted) {
      setState(() {
        final movieTrend = results[0];
        final tvTrend = results[4];
        
        // Merge trending movies and tv shows for hero carousel
        _trending = [];
        int i = 0, j = 0;
        while (i < movieTrend.length || j < tvTrend.length) {
          if (i < movieTrend.length) {
            _trending.add(movieTrend[i]);
            i++;
          }
          if (j < tvTrend.length) {
            _trending.add(tvTrend[j]);
            j++;
          }
        }

        _popularMovies = SwapListNullSafe(results[1]);
        _nowPlayingMovies = SwapListNullSafe(results[2]);
        _animeMovies = SwapListNullSafe(results[3]);
        _trendingTv = SwapListNullSafe(results[4]);
        _popularTv = SwapListNullSafe(results[5]);
        _topRatedTv = SwapListNullSafe(results[6]);
        _airingTodayTv = SwapListNullSafe(results[7]);
        _loading = false;
      });
      _startHeroTimer();
    }
  }

  List<MediaItem> SwapListNullSafe(List<MediaItem>? list) {
    return list ?? [];
  }

  void _startHeroTimer() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _trending.isEmpty || !_heroController.hasClients) return;
      final next = (_heroIndex + 1) % _trending.take(5).length;
      _heroController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _openDetail(MediaItem item) {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(builder: (_) => DetailScreen(item: item)),
    ).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.transparent,
      child: _loading
          ? const Center(child: IOSLoading(message: 'Curating the best content...'))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: GestureDetector(
                        onTap: widget.onSearch,
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: isDark 
                                ? CupertinoColors.systemGrey6.darkColor 
                                : CupertinoColors.systemGrey6,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(
                                FluentIcons.search_24_regular,
                                color: CupertinoColors.systemGrey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Search movies, shows, anime...',
                                style: TextStyle(
                                  color: CupertinoColors.systemGrey,
                                  fontSize: 16,
                                  fontFamily: GoogleFonts.inter().fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _HeroCarousel(
                  items: _trending.take(5).toList(),
                  heroIndex: _heroIndex,
                  controller: _heroController,
                  onPageChanged: (i) => setState(() => _heroIndex = i),
                  onTap: _openDetail,
                  onSearch: widget.onSearch,
                )),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ContentSection(
                        title: 'Trending Now',
                        items: _trending,
                        onTap: _openDetail,
                      ),
                      _ContentSection(
                        title: 'Trending Series',
                        items: _trendingTv,
                        onTap: _openDetail,
                      ),
                      _ContentSection(
                        title: 'Now Playing',
                        items: _nowPlayingMovies,
                        onTap: _openDetail,
                      ),
                      _ContentSection(
                        title: 'Airing Today',
                        items: _airingTodayTv,
                        onTap: _openDetail,
                      ),
                      _ContentSection(
                        title: 'Popular Movies',
                        items: _popularMovies,
                        onTap: _openDetail,
                      ),
                      _ContentSection(
                        title: 'Popular Series',
                        items: _popularTv,
                        onTap: _openDetail,
                      ),
                      _ContentSection(
                        title: 'All-Time Best Series',
                        items: _topRatedTv,
                        onTap: _openDetail,
                      ),
                      _ContentSection(
                        title: 'Anime Hits',
                        items: _animeMovies,
                        onTap: _openDetail,
                      ),
                      const NativeAdWidget(size: NativeAdSize.medium),
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _HeroCarousel extends StatelessWidget {
  final List<MediaItem> items;
  final int heroIndex;
  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<MediaItem> onTap;
  final VoidCallback? onSearch;

  const _HeroCarousel({
    required this.items,
    required this.heroIndex,
    required this.controller,
    required this.onPageChanged,
    required this.onTap,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    // Set PageView height for the popup card layout
    final viewH = (screenH * 0.52).clamp(340.0, 500.0);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: viewH,
          child: PageView.builder(
            controller: controller,
            onPageChanged: onPageChanged,
            itemCount: items.length,
            itemBuilder: (_, i) => _HeroCard(
              item: items[i],
              onTap: () => onTap(items[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(items.length, (i) {
            final active = i == heroIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 6),
              width: active ? 16 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active
                    ? AppTheme.neonYellow
                    : (isDark
                        ? CupertinoColors.white.withValues(alpha: 0.3)
                        : CupertinoColors.black.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const _HeroCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.fullBackdropUrl.isNotEmpty ? item.fullBackdropUrl : item.fullPosterUrl;
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: isDark ? CupertinoColors.black : CupertinoColors.white,
          boxShadow: [
            BoxShadow(
              color: isDark 
                  ? CupertinoColors.black.withValues(alpha: 0.5) 
                  : CupertinoColors.black.withValues(alpha: 0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image (Completely clean, no gradients/overlays directly on it)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              placeholder: (_, _) => const ColoredBox(color: Color(0xFF111111)),
              errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF111111)),
            ),
            // Frosted Glass details card overlayed at the bottom of the card
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (isDark
                          ? CupertinoColors.black.withValues(alpha: 0.55)
                          : CupertinoColors.white.withValues(alpha: 0.7)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (isDark
                            ? CupertinoColors.white.withValues(alpha: 0.08)
                            : CupertinoColors.black.withValues(alpha: 0.08)),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            // Type badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.neonYellow,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                (item.mediaType == 'tv' ? 'SERIES' : 'FILM').toUpperCase(),
                                style: const TextStyle(
                                  color: CupertinoColors.black,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Rating
                            const Icon(FluentIcons.star_24_filled, size: 12, color: AppTheme.neonYellow),
                            const SizedBox(width: 3),
                            Text(
                              item.ratingStr,
                              style: TextStyle(
                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Year
                            Text(
                              item.year,
                              style: TextStyle(
                                color: isDark ? const Color(0xFFAAAAAA) : const Color(0xFF666666),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Title
                        Text(
                          item.title.toUpperCase(),
                          style: TextStyle(
                            color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: onTap,
                                child: Container(
                                  height: 36,
                                  decoration: AppTheme.brutalistDecoration(
                                    context: context,
                                    color: AppTheme.neonYellow,
                                    borderRadius: 8.0,
                                    shadowOffset: 0.0,
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(FluentIcons.play_24_filled, color: CupertinoColors.black, size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'PLAY NOW',
                                        style: TextStyle(
                                          color: CupertinoColors.black,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: onTap,
                                child: Container(
                                  height: 36,
                                  decoration: AppTheme.brutalistDecoration(
                                    context: context,
                                    color: isDark
                                        ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
                                        : const Color(0x77FFFFFF),
                                    borderRadius: 8.0,
                                    shadowOffset: 0.0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(FluentIcons.info_24_regular, color: isDark ? CupertinoColors.white : CupertinoColors.black, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        'INFO',
                                        style: TextStyle(
                                          color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
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
      ),
    );
  }
}

class _ContentSection extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;

  const _ContentSection({required this.title, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final onSurface = isDark ? CupertinoColors.white : CupertinoColors.black;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: onSurface,
                  ),
                ),
              ),
              Text(
                'SEE ALL',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: isDark ? AppTheme.neonYellow : CupertinoColors.black,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _ContentCard(item: items[i], onTap: () => onTap(items[i])),
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _ContentCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const _ContentCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: isDark
              ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
              : const Color(0x77FFFFFF),
          borderRadius: 12.0,
          shadowOffset: 0.0,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: item.fullPosterUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: isDark
                  ? (SettingsService.instance.isAmoled ? const Color(0xFF121212) : const Color(0xFF1E1E1E))
                  : const Color(0xFFE5E5EA),
            ),
            errorWidget: (_, __, ___) => Container(
              color: isDark
                  ? (SettingsService.instance.isAmoled ? const Color(0xFF121212) : const Color(0xFF1E1E1E))
                  : const Color(0xFFE5E5EA),
              child: const Icon(FluentIcons.video_clip_24_regular, size: 24, color: CupertinoColors.systemGrey),
            ),
          ),
        ),
      ),
    );
  }
}
