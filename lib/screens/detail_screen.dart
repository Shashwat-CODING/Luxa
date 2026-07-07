import 'dart:ui';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import '../services/bookmark_service.dart';
import '../services/ad_service.dart';
import 'package:share_plus/share_plus.dart';

import 'anime_player_screen.dart';
import 'player_screen.dart';
import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';

class DetailScreen extends StatefulWidget {
  final MediaItem item;
  const DetailScreen({super.key, required this.item});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _api = ApiService.instance;
  MediaDetail? _detail;
  List<MediaItem> _similar = [];
  bool _loading = true;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _isFavorite = BookmarkService.isBookmarked(widget.item.id);
    _load();
  }

  void _toggleBookmark() {
    BookmarkService.toggleBookmark(widget.item);
    setState(() => _isFavorite = BookmarkService.isBookmarked(widget.item.id));
  }

  Future<void> _load() async {
    MediaDetail? detail;
    try {
      if (widget.item.mediaType == 'anime') {
        detail = await _api.getAnimeDetail(widget.item);
      } else {
        detail = widget.item.mediaType == 'tv'
            ? await _api.getTvDetail(widget.item.id)
            : await _api.getMovieDetail(widget.item.id);
      }
    } catch (e) {
      debugPrint('Error loading details: $e');
    }
    if (mounted) {
      setState(() => _detail = detail);
      _loadSimilar();
    }
  }

  Future<void> _loadSimilar() async {
    try {
      if (widget.item.mediaType == 'anime') {
        _similar = []; // No similar anime for now
        if (mounted) setState(() { _loading = false; });
        return;
      }
      final similar = widget.item.mediaType == 'tv'
          ? await _api.getSimilarTv(widget.item.id)
          : await _api.getSimilarMovies(widget.item.id);
      if (mounted) setState(() { _similar = similar; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    if (_loading) {
      return CupertinoPageScaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        child: const Center(child: IOSLoading(message: 'Gathering metadata...')),
      );
    }

    final isDark = theme.brightness == Brightness.dark;

    final item = _detail ?? MediaDetail(
      id: widget.item.id,
      title: widget.item.title,
      overview: widget.item.overview ?? '',
      posterPath: widget.item.posterPath ?? '',
      backdropPath: widget.item.backdropPath ?? '',
      releaseDate: widget.item.releaseDate ?? '',
      voteAverage: widget.item.voteAverage,
      mediaType: widget.item.mediaType,
      genres: [],
      cast: [],
    );

    return CupertinoPageScaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _DetailHeaderDelegate(
              item: item,
              isFavorite: _isFavorite,
              onBack: () => Navigator.pop(context),
              onBookmark: _toggleBookmark,
              expandedHeight: MediaQuery.of(context).size.height * 0.50,
            ),
          ),
          SliverToBoxAdapter(child: _buildBody(item, theme)),
        ],
      ),
    );
  }

  Widget _buildBody(MediaDetail item, CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            item.title.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
              height: 1.0,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          // Meta row
          Row(
            children: [
              const Icon(FluentIcons.star_24_filled, size: 13, color: AppTheme.neonYellow),
              const SizedBox(width: 4),
              Text(
                item.ratingStr,
                style: GoogleFonts.spaceGrotesk(color: isDark ? CupertinoColors.white : CupertinoColors.black, fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 10),
              Container(width: 3, height: 3, decoration: const BoxDecoration(color: Color(0xFF6E6E73), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text(
                item.year,
                style: GoogleFonts.spaceGrotesk(color: CupertinoColors.systemGrey, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              if ((item.runtime ?? 0) > 0) ...[
                const SizedBox(width: 10),
                Container(width: 3, height: 3, decoration: const BoxDecoration(color: Color(0xFF6E6E73), shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(
                  '${item.runtime}m',
                  style: GoogleFonts.spaceGrotesk(color: CupertinoColors.systemGrey, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          if (item.genres.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: item.genres.map((genre) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: AppTheme.brutalistDecoration(
                    context: context,
                    color: isDark
                        ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
                        : const Color(0x77FFFFFF),
                    borderRadius: 4.0,
                    shadowOffset: 2.0,
                    customBorderColor: AppTheme.neonYellow,
                  ),
                  child: Text(
                    genre.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 24),
          // Play button - full width prominent
          GestureDetector(
            onTap: () {
              if (item.mediaType == 'tv' || (item.mediaType == 'anime' && item.extras?['anime_type'] == 'series')) {
                _showEpisodeSelector(item);
              } else {
                AdService.showRewardedAd(
                  context: context,
                  onComplete: () {
                    if (context.mounted) {
                      if (item.mediaType == 'anime') {
                        Navigator.of(context, rootNavigator: true).push(CupertinoPageRoute(
                          builder: (_) => AnimePlayerScreen(
                            item: item,
                            slug: item.extras?['slug'] ?? '',
                            type: 'movie',
                          ),
                        ));
                      } else {
                        Navigator.of(context, rootNavigator: true).push(CupertinoPageRoute(
                          builder: (_) => PlayerScreen(item: item),
                        ));
                      }
                    }
                  },
                );
              }
            },
            child: Container(
              height: 52,
              decoration: AppTheme.brutalistDecoration(
                context: context,
                color: AppTheme.neonYellow,
                borderRadius: 4.0,
                shadowOffset: 3.5,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    (item.mediaType == 'tv' || (item.mediaType == 'anime' && item.extras?['anime_type'] == 'series'))
                        ? FluentIcons.list_24_regular
                        : FluentIcons.play_24_filled,
                    size: 18,
                    color: CupertinoColors.black,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    ((item.mediaType == 'tv' || (item.mediaType == 'anime' && item.extras?['anime_type'] == 'series'))
                        ? 'EPISODES'
                        : 'PLAY NOW').toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: CupertinoColors.black,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Secondary actions row
          Row(
            children: [
              Expanded(
                child: _DetailActionBtn(
                  icon: _isFavorite ? FluentIcons.heart_24_filled : FluentIcons.heart_24_regular,
                  label: _isFavorite ? 'SAVED' : 'WATCHLIST',
                  onPressed: _toggleBookmark,
                  active: _isFavorite,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DetailActionBtn(
                  icon: FluentIcons.share_24_regular,
                  label: 'SHARE',
                  onPressed: () {
                    final url = '${ApiService.websiteUrl}/details?type=${item.mediaType}&id=${item.id}';
                    Share.share('Check out "${item.title}" on Luxa!\n\nWatch here: $url');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Overview
          Text(
            item.overview ?? 'No description available.',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: isDark ? const Color(0xFFAAAAAA) : const Color(0xFF333333),
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (item.cast.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              'CAST',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: item.cast.length.clamp(0, 10),
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _CastMember(cast: item.cast[i]),
              ),
            ),
          ],
          if (_similar.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(
              'MORE LIKE THIS',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _similar.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final simItem = _similar[i];
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => DetailScreen(item: simItem))),
                    child: Container(
                      width: 120,
                      decoration: AppTheme.brutalistDecoration(
                        context: context,
                        color: isDark
                            ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
                            : const Color(0x77FFFFFF),
                        borderRadius: 4.0,
                        shadowOffset: 2.5,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: simItem.fullPosterUrl.isNotEmpty
                            ? CachedNetworkImage(imageUrl: simItem.fullPosterUrl, fit: BoxFit.cover, width: 120)
                            : Container(
                                width: 120,
                                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE5E5EA),
                                child: const Icon(FluentIcons.movies_and_tv_24_regular),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  void _showEpisodeSelector(MediaDetail item) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => _EpisodeSheet(item: item),
    );
  }
}

class _DetailHeaderDelegate extends SliverPersistentHeaderDelegate {
  final MediaDetail item;
  final bool isFavorite;
  final VoidCallback onBack;
  final VoidCallback onBookmark;
  final double expandedHeight;

  _DetailHeaderDelegate({
    required this.item,
    required this.isFavorite,
    required this.onBack,
    required this.onBookmark,
    required this.expandedHeight,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final progress = (shrinkOffset / (expandedHeight - 88)).clamp(0.0, 1.0);
    final isAmoled = SettingsService.instance.isAmoled;
    final bgColor = isDark
        ? (isAmoled ? AppTheme.pureBlack : AppTheme.softDarkBg)
        : AppTheme.creamBg;
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Image
        Opacity(
          opacity: (1 - progress * 1.3).clamp(0.0, 1.0),
          child: item.fullBackdropUrl.isNotEmpty
              ? CachedNetworkImage(imageUrl: item.fullBackdropUrl, fit: BoxFit.cover)
              : Container(color: const Color(0xFF111111)),
        ),
        // Gradient overlay
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CupertinoColors.black.withValues(alpha: 0.25 * (1 - progress)),
                CupertinoColors.transparent,
                bgColor.withValues(alpha: 0.7 + (0.3 * progress)),
                bgColor,
              ],
              stops: const [0.0, 0.35, 0.75, 1.0],
            ),
          ),
        ),
        
        // Floating Thumbnail/Poster on the Banner
        if (item.fullPosterUrl.isNotEmpty)
          Positioned(
            left: 20,
            bottom: 24,
            child: Opacity(
              opacity: (1 - progress * 1.5).clamp(0.0, 1.0),
              child: Container(
                width: 110,
                height: 165,
                decoration: AppTheme.brutalistDecoration(
                  context: context,
                  color: isDark
                      ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
                      : const Color(0x77FFFFFF),
                  borderRadius: 4.0,
                  shadowOffset: 3.0,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: CachedNetworkImage(
                    imageUrl: item.fullPosterUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(color: CupertinoColors.systemGrey6),
                    errorWidget: (_, _, _) => const Icon(FluentIcons.image_24_regular),
                  ),
                ),
              ),
            ),
          ),
        
        // Blurred bar when shrunk
        if (progress > 0.3)
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12 * progress, sigmaY: 12 * progress),
              child: Container(
                color: theme.barBackgroundColor.withValues(alpha: (progress - 0.3) * 1.2),
              ),
            ),
          ),
          
        // Top Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: onBack,
                      child: Container(
                        width: 38, height: 38,
                        decoration: AppTheme.brutalistDecoration(
                          context: context,
                          color: isDark
                              ? (SettingsService.instance.isAmoled ? AppTheme.amoledSurface : AppTheme.darkSlate)
                              : AppTheme.neonYellow,
                          borderRadius: 4.0,
                          shadowOffset: 2.0,
                        ),
                        child: Icon(
                          FluentIcons.chevron_left_24_regular,
                          size: 22,
                          color: isDark ? CupertinoColors.white : CupertinoColors.black,
                        ),
                      ),
                    ),
                    Expanded(
                      child: progress > 0.6
                          ? Text(
                              item.title.toUpperCase(),
                              style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ).animate().fadeIn(duration: 180.ms)
                          : const SizedBox.shrink(),
                    ),
                    GestureDetector(
                      onTap: onBookmark,
                      child: Container(
                        width: 38, height: 38,
                        decoration: AppTheme.brutalistDecoration(
                          context: context,
                          color: isDark
                              ? (SettingsService.instance.isAmoled ? AppTheme.amoledSurface : AppTheme.darkSlate)
                              : (isFavorite ? AppTheme.neonYellow : CupertinoColors.white),
                          borderRadius: 4.0,
                          shadowOffset: 2.0,
                        ),
                        child: Icon(
                          isFavorite ? FluentIcons.heart_24_filled : FluentIcons.heart_24_regular,
                          size: 20,
                          color: isFavorite
                              ? CupertinoColors.black
                              : (isDark ? CupertinoColors.white : CupertinoColors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  double get maxExtent => expandedHeight;

  @override
  double get minExtent => 88;

  @override
  bool shouldRebuild(covariant _DetailHeaderDelegate oldDelegate) => true;
}

class _DetailActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;
  const _DetailActionBtn({required this.icon, required this.label, required this.onPressed, this.active = false});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 44,
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: active
              ? AppTheme.neonYellow
              : (isDark
                  ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
                  : const Color(0x77FFFFFF)),
          borderRadius: 4.0,
          shadowOffset: 2.5,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: active
                  ? CupertinoColors.black
                  : (isDark ? CupertinoColors.white : CupertinoColors.black),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                color: active
                    ? CupertinoColors.black
                    : (isDark ? CupertinoColors.white : CupertinoColors.black),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastMember extends StatelessWidget {
  final dynamic cast;
  const _CastMember({required this.cast});

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasImage = cast.fullProfileUrl != null && cast.fullProfileUrl.isNotEmpty;
    final borderColor = isDark ? CupertinoColors.white : CupertinoColors.black;

    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.neonYellow,
              width: 2.0,
            ),
            color: isDark
                ? (SettingsService.instance.isAmoled ? const Color(0xFF121212) : AppTheme.darkSlate)
                : AppTheme.neonYellow,
            image: hasImage
                ? DecorationImage(
                    image: CachedNetworkImageProvider(cast.fullProfileUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: !hasImage
              ? Icon(
                  FluentIcons.person_24_filled,
                  size: 30,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                )
              : null,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 80,
          child: Text(
            cast.name, 
            style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold), 
            textAlign: TextAlign.center, 
            maxLines: 2
          ),
        ),
      ],
    );
  }
}

class _EpisodeSheet extends StatefulWidget {
  final MediaDetail item;
  const _EpisodeSheet({required this.item});

  @override
  State<_EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<_EpisodeSheet> {
  int _selectedSeason = 1;
  List<TvEpisode> _episodes = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    setState(() => _loading = true);
    if (widget.item.mediaType == 'anime') {
       setState(() {
         _episodes = widget.item.seasons.isNotEmpty ? widget.item.seasons[0].episodes ?? [] : [];
         _loading = false;
       });
       return;
    }
    final season = await ApiService.instance.getTvSeasonDetail(widget.item.id, _selectedSeason);
    if (mounted) {
       setState(() {
         _episodes = season?.episodes ?? [];
         _loading = false;
       });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    
    return GlassBox(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Episodes', 
                  style: GoogleFonts.inter(
                    fontSize: 22, 
                    fontWeight: FontWeight.w600,
                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                  )
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      FluentIcons.dismiss_24_regular, 
                      size: 18,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (widget.item.seasons.length > 1)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.item.seasons.length,
                  itemBuilder: (_, i) {
                    final s = widget.item.seasons[i];
                    final active = _selectedSeason == s.seasonNumber;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedSeason = s.seasonNumber);
                        _loadEpisodes();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: active
                              ? AppTheme.neonYellow
                              : (isDark
                                  ? (SettingsService.instance.isAmoled ? const Color(0xFF121212) : const Color(0xFF2C2C2E))
                                  : const Color(0xFFE5E5EA)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            s.name, 
                            style: TextStyle(
                              fontWeight: FontWeight.w600, 
                              fontSize: 12,
                              color: active ? CupertinoColors.black : (isDark ? CupertinoColors.white : CupertinoColors.black),
                            )
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 20),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : ListView.separated(
                      itemCount: _episodes.length,
                      separatorBuilder: (_, __) => Container(
                        height: 0.5, 
                        color: isDark ? const Color(0x33FFFFFF) : const Color(0x33000000),
                      ),
                      itemBuilder: (_, i) {
                        final ep = _episodes[i];
                        return CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          onPressed: () {
                            Navigator.pop(context);
                            if (widget.item.mediaType == 'anime') {
                              Navigator.of(context, rootNavigator: true).push(CupertinoPageRoute(
                                builder: (_) => AnimePlayerScreen(
                                  item: widget.item as MediaDetail,
                                  slug: ep.extras?['slug'] ?? '',
                                  type: 'episode',
                                ),
                              ));
                            } else {
                              Navigator.of(context, rootNavigator: true).push(CupertinoPageRoute(
                                builder: (_) => PlayerScreen(
                                  item: widget.item as MediaDetail,
                                  season: _selectedSeason,
                                  episode: ep.episodeNumber,
                                ),
                              ));
                            }
                          },
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8.0), 
                                child: CachedNetworkImage(
                                  imageUrl: ep.fullStillUrl, 
                                  width: 100, 
                                  height: 60, 
                                  fit: BoxFit.cover, 
                                  errorWidget: (_, __, ___) => Container(
                                    width: 100, 
                                    height: 60, 
                                    color: isDark ? CupertinoColors.systemGrey6 : CupertinoColors.systemGrey,
                                    child: Icon(
                                      FluentIcons.movies_and_tv_24_regular,
                                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                      size: 20,
                                    ),
                                  )
                                )
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, 
                                  children: [
                                    Text(
                                      '${ep.episodeNumber}. ${ep.name}', 
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600, 
                                        fontSize: 13, 
                                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                      )
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      ep.overview ?? '', 
                                      style: const TextStyle(
                                        fontSize: 11, 
                                        color: CupertinoColors.systemGrey,
                                      ), 
                                      maxLines: 2, 
                                      overflow: TextOverflow.ellipsis,
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
          ],
        ),
      ),
    );
  }
}
