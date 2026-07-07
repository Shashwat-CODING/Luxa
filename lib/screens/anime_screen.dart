import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import 'detail_screen.dart';
import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';

class AnimeScreen extends StatefulWidget {
  final VoidCallback onSearch;
  const AnimeScreen({super.key, required this.onSearch});

  @override
  State<AnimeScreen> createState() => _AnimeScreenState();
}

class _AnimeScreenState extends State<AnimeScreen> {
  final _api = ApiService.instance;
  Map<String, List<MediaItem>> _homeData = {};
  List<MediaItem> _trending = [];
  bool _loading = true;

  int _carouselIndex = 0;
  Timer? _carouselTimer;
  final PageController _carouselCtrl = PageController(viewportFraction: 1.0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _carouselCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _api.getAnimeHome();
    if (mounted) {
      setState(() {
        _homeData = data;
        // Take "Trending Series" or the first category as trending for carousel
        if (data.containsKey('Trending Series')) {
          _trending = data['Trending Series']!;
        } else if (data.isNotEmpty) {
          _trending = data.values.first;
        }
        _loading = false;
      });
      _startCarousel();
    }
  }

  void _startCarousel() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _trending.isEmpty || !_carouselCtrl.hasClients) return;
      final next = (_carouselIndex + 1) % _trending.take(6).length;
      _carouselCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.transparent,
      child: _loading
          ? const Center(child: IOSLoading(message: 'Gathering the best anime...'))
          : CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                if (_trending.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildCarousel(theme),
                  ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final category = _homeData.keys.elementAt(index);
                      final items = _homeData[category]!;
                      return _buildCategorySection(category, items, theme);
                    },
                    childCount: _homeData.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 140)),
              ],
            ),
    );
  }

  Widget _buildCarousel(CupertinoThemeData theme) {
    final items = _trending.take(5).toList();
    final isDark = theme.brightness == Brightness.dark;
    final screenH = MediaQuery.of(context).size.height;
    final cardH = (screenH * 0.65).clamp(420.0, 700.0);

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        SizedBox(
          height: cardH,
          child: PageView.builder(
            controller: _carouselCtrl,
            onPageChanged: (i) => setState(() => _carouselIndex = i),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              return GestureDetector(
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute(builder: (_) => DetailScreen(item: item)),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: item.fullPosterUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: isDark ? const Color(0xFF121212) : const Color(0xFFE5E5EA)),
                      errorWidget: (_, _, _) => Container(color: isDark ? const Color(0xFF121212) : const Color(0xFFE5E5EA)),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.3, 0.6, 1.0],
                          colors: [
                            CupertinoColors.black.withValues(alpha: 0.2),
                            CupertinoColors.transparent,
                            CupertinoColors.black.withValues(alpha: 0.55),
                            CupertinoColors.black,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.neonYellow,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ANIME',
                              style: TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.title.toUpperCase(),
                            style: const TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                              height: 1.1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context, rootNavigator: true).push(
                                    CupertinoPageRoute(builder: (_) => DetailScreen(item: item)),
                                  ),
                                  child: Container(
                                    height: 44,
                                    decoration: AppTheme.brutalistDecoration(
                                      context: context,
                                      color: AppTheme.neonYellow,
                                      borderRadius: 12.0,
                                      shadowOffset: 0.0,
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(FluentIcons.play_24_filled, color: CupertinoColors.white, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'PLAY NOW',
                                          style: TextStyle(
                                            color: CupertinoColors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context, rootNavigator: true).push(
                                    CupertinoPageRoute(builder: (_) => DetailScreen(item: item)),
                                  ),
                                  child: Container(
                                    height: 44,
                                    decoration: AppTheme.brutalistDecoration(
                                      context: context,
                                      color: isDark ? const Color(0x771C1C1E) : const Color(0x77FFFFFF),
                                      borderRadius: 12.0,
                                      shadowOffset: 0.0,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(FluentIcons.info_24_regular, color: isDark ? CupertinoColors.white : CupertinoColors.black, size: 18),
                                        const SizedBox(width: 8),
                                        Text(
                                          'INFO',
                                          style: TextStyle(
                                            color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
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
                  ],
                ),
              );
            },
          ),
        ),
        // Dot indicators
        Positioned(
          bottom: 96,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(items.length, (i) {
              final active = i == _carouselIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(right: 6),
                width: active ? 16 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? AppTheme.neonYellow
                      : CupertinoColors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection(String title, List<MediaItem> items, CupertinoThemeData theme) {
    if (items.isEmpty) return const SizedBox.shrink();
    final isDark = theme.brightness == Brightness.dark;
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
          height: 235,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: 110,
              child: _AnimeGridCard(item: items[i]),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }
}

class _AnimeGridCard extends StatelessWidget {
  final MediaItem item;
  const _AnimeGridCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final hasImage = item.fullPosterUrl.isNotEmpty;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    
    return GestureDetector(
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(builder: (_) => DetailScreen(item: item)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: 'anime_grid_${item.id}_${item.extras?['slug']}',
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Container(
                decoration: AppTheme.brutalistDecoration(
                  context: context,
                  color: isDark ? const Color(0x771C1C1E) : const Color(0x77FFFFFF),
                  borderRadius: 12.0,
                  shadowOffset: 2.5,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: hasImage
                      ? CachedNetworkImage(
                          imageUrl: item.fullPosterUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E5EA)),
                          errorWidget: (_, __, ___) => Container(
                            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E5EA),
                            child: const Icon(FluentIcons.video_clip_24_regular, size: 24, color: CupertinoColors.systemGrey),
                          ),
                        )
                      : Container(
                          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E5EA),
                          child: const Icon(FluentIcons.video_clip_24_regular, size: 24, color: CupertinoColors.systemGrey),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.extras?['quality'] != null || item.extras?['episode'] != null) ...[
            const SizedBox(height: 2),
            Text(
              '${item.extras?['quality'] ?? ''} ${item.extras?['episode'] != null ? '· Ep ${item.extras?['episode']}' : ''}'.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: CupertinoColors.systemGrey,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class AnimeSearchScreen extends StatefulWidget {
  const AnimeSearchScreen({super.key});

  @override
  State<AnimeSearchScreen> createState() => _AnimeSearchScreenState();
}

class _AnimeSearchScreenState extends State<AnimeSearchScreen> {
  final _api = ApiService.instance;
  final _controller = TextEditingController();
  List<MediaItem> _results = [];
  bool _searching = false;

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _searching = true);
    final results = await _api.searchAnime(q);
    if (mounted) {
      setState(() {
        _results = results;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.transparent,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: Text('SEARCH ANIME', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        trailing: _searching ? const CupertinoActivityIndicator() : null,
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: IOSSearchField(
                    controller: _controller,
                    placeholder: 'Search for anime...',
                    onSubmitted: _doSearch,
                  ),
                ),
                Expanded(
                  child: _results.isEmpty && !_searching
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FluentIcons.search_24_regular, size: 64, color: CupertinoColors.systemGrey4),
                              const SizedBox(height: 16),
                              Text('Search for your favorite anime'.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: CupertinoColors.systemGrey)),
                            ],
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final gridWidth = constraints.maxWidth;
                            final crossAxisCount = (gridWidth / 200).floor().clamp(2, 8);
                            final cellWidth = (gridWidth - (crossAxisCount - 1) * 16) / crossAxisCount;
                            final childAspectRatio = cellWidth / (cellWidth * 1.5 + 72);

                            return GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: childAspectRatio,
                              ),
                              itemCount: _results.length,
                              itemBuilder: (context, index) => _AnimeGridCard(item: _results[index]),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
