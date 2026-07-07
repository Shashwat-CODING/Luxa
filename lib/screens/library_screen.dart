import 'package:flutter/cupertino.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../models/collection_models.dart';
import '../models/download_item.dart';
import '../services/watch_history.dart';
import '../services/bookmark_service.dart';
import '../services/collection_service.dart';
import '../services/api_service.dart';
import '../services/streaming_service.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';
import 'package:google_fonts/google_fonts.dart';

class LibraryScreen extends StatefulWidget {
  final VoidCallback onSearch;
  const LibraryScreen({super.key, required this.onSearch});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selectedSegment = 1;
  final _api = ApiService.instance;

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.transparent,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          WatchHistory.listChanged,
          BookmarkService.listChanged,
          CollectionService.instance,
          StreamingService.listChanged,
        ]),
        builder: (context, _) {
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              CupertinoSliverNavigationBar(
                transitionBetweenRoutes: false,
                largeTitle: Text('MY LIBRARY', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                backgroundColor: CupertinoColors.transparent,
                border: null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: widget.onSearch,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: AppTheme.brutalistDecoration(
                          context: context,
                          color: isDark
                              ? (SettingsService.instance.isAmoled ? AppTheme.amoledSurface : AppTheme.darkSlate)
                              : AppTheme.neonYellow,
                          borderRadius: 4,
                          shadowOffset: 2.0,
                        ),
                        child: Icon(
                          FluentIcons.search_24_regular,
                          size: 18,
                          color: isDark ? CupertinoColors.white : CupertinoColors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      decoration: AppTheme.brutalistDecoration(
                        context: context,
                        color: isDark
                            ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
                            : const Color(0x77FFFFFF),
                        borderRadius: 4.0,
                        shadowOffset: 2.0,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: CupertinoSlidingSegmentedControl<int>(
                        groupValue: _selectedSegment,
                        backgroundColor: CupertinoColors.transparent,
                        thumbColor: AppTheme.neonYellow,
                        children: {
                          0: _buildTabText('Watchlist', theme, _selectedSegment == 0),
                          1: _buildTabText('History', theme, _selectedSegment == 1),
                          2: _buildTabText('Downloads', theme, _selectedSegment == 2),
                          3: _buildTabText('Collections', theme, _selectedSegment == 3),
                        },
                        onValueChanged: (val) {
                          if (val != null) setState(() => _selectedSegment = val);
                        },
                      ),
                    ),
                  ),
                ),
              ),
              SliverFillRemaining(
                child: _buildSelectedTab(theme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectedTab(CupertinoThemeData theme) {
    Widget content;
    switch (_selectedSegment) {
      case 0: content = _buildWatchlistTab(theme); break;
      case 1: content = _buildHistoryTab(theme); break;
      case 2: content = _buildDownloadsTab(theme); break;
      case 3: content = _buildCollectionsTab(theme); break;
      default: content = const SizedBox.shrink();
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: content,
      ),
    );
  }

  Widget _buildWatchlistTab(CupertinoThemeData theme) {
    final movies = BookmarkService.bookmarks.where((m) => m.mediaType == 'movie').toList();
    final tv = BookmarkService.bookmarks.where((m) => m.mediaType == 'tv' || m.mediaType == 'anime').toList();

    if (movies.isEmpty && tv.isEmpty) return _buildEmptyState('Your watchlist is empty', theme);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (movies.isNotEmpty) ...[
          _buildSubHeader('Movies', movies.length, theme),
          _buildMediaGrid(movies, theme),
          const SizedBox(height: 24),
        ],
        if (tv.isNotEmpty) ...[
          _buildSubHeader('Shows & Anime', tv.length, theme),
          _buildMediaGrid(tv, theme),
        ],
        const SizedBox(height: 140),
      ],
    );
  }

  Widget _buildHistoryTab(CupertinoThemeData theme) {
    final movies = WatchHistory.history.where((m) => m.mediaType == 'movie').toList();
    final seriesProgress = CollectionService.instance.seriesProgress.values.toList()
      ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));

    if (movies.isEmpty && seriesProgress.isEmpty) {
      return _buildEmptyState('No watch history yet', theme);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (seriesProgress.isNotEmpty) ...[
          _buildSubHeader('Series Progress', seriesProgress.length, theme),
          ...seriesProgress.map((s) => _buildSeriesProgressCard(s, theme)),
          const SizedBox(height: 24),
        ],
        if (movies.isNotEmpty) ...[
          _buildSubHeader('Recent Movies', movies.length, theme),
          _buildMediaGrid(movies, theme, isHistory: true),
        ],
        const SizedBox(height: 140),
      ],
    );
  }

  Widget _buildDownloadsTab(CupertinoThemeData theme) {
    final downloads = StreamingService.instance.downloads;
    if (downloads.isEmpty) return _buildEmptyState('No downloads found', theme);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: downloads.length,
      itemBuilder: (context, index) {
        final item = downloads[index];
        return _buildDownloadTile(item, theme);
      },
    );
  }

  Widget _buildDownloadTile(DownloadItem item, CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        if (item.status == DownloadStatus.completed) {
          Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(
              builder: (_) => PlayerScreen(
                item: item.mediaItem is MediaDetail ? item.mediaItem as MediaDetail : null,
                offlinePath: item.filePath,
              ),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: isDark
              ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
              : const Color(0x77FFFFFF),
          borderRadius: 12.0,
          shadowOffset: 2.5,
        ),
        child: Row(
          children: [
            Container(
              decoration: AppTheme.brutalistDecoration(
                context: context,
                borderRadius: 12.0,
                shadowOffset: 1.5,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: item.mediaItem.fullPosterUrl,
                  width: 50,
                  height: 75,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(color: CupertinoColors.black.withValues(alpha: 0.1)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.mediaItem.title.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w900, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (item.status == DownloadStatus.downloading) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: item.progress,
                      backgroundColor: CupertinoColors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.neonYellow),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(item.progress * 100).toStringAsFixed(1)}% · ${item.speedText ?? ""}'.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(fontSize: 10, color: CupertinoColors.systemGrey, fontWeight: FontWeight.bold),
                    ),
                  ] else ...[
                    Text(
                      (item.status == DownloadStatus.completed ? 'Completed · ${item.sizeText ?? ""}' : 'Failed').toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        color: item.status == DownloadStatus.completed ? CupertinoColors.systemGreen : CupertinoColors.systemRed,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (item.status == DownloadStatus.completed)
              const Icon(FluentIcons.play_circle_24_filled, color: CupertinoColors.systemGrey2)
            else if (item.status == DownloadStatus.downloading)
              const CupertinoActivityIndicator(radius: 8)
            else
              const Icon(FluentIcons.error_circle_24_regular, color: CupertinoColors.systemRed),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionsTab(CupertinoThemeData theme) {
    final collections = CollectionService.instance.collections;
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = (width / 260).floor().clamp(2, 6);
    final childAspectRatio = width > 800 ? 1.4 : 1.1;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCreateButton('New Collection', FluentIcons.folder_add_24_regular, theme.primaryColor, () => _showCreateCollectionDialog(), theme),
        const SizedBox(height: 16),
        if (collections.isEmpty)
          _buildEmptyState('No collections created', theme)
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: collections.length,
            itemBuilder: (context, index) => _buildCollectionCard(collections[index], theme),
          ),
        const SizedBox(height: 140),
      ],
    );
  }

  Widget _buildSubHeader(String title, int count, CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '${title.toUpperCase()} ($count)',
        style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w900, color: isDark ? CupertinoColors.white : CupertinoColors.black),
      ),
    );
  }

  Widget _buildMediaGrid(List<MediaItem> items, CupertinoThemeData theme, {bool isHistory = false}) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = (width / 180).floor().clamp(3, 8);
    final isDark = theme.brightness == Brightness.dark;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount, 
        mainAxisSpacing: 12, 
        crossAxisSpacing: 12, 
        childAspectRatio: 2 / 3,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onTap: () => _openDetail(item),
          onLongPress: isHistory ? () => _showHistoryItemOptions(item) : null,
          child: Container(
            decoration: AppTheme.brutalistDecoration(
              context: context,
              color: isDark
                  ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
                  : const Color(0x77FFFFFF),
              borderRadius: 12.0,
              shadowOffset: 2.5,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: item.fullPosterUrl, 
                fit: BoxFit.cover, 
                errorWidget: (_, __, ___) => Container(color: CupertinoColors.black.withValues(alpha: 0.12))
              ),
            ),
          ),
        );
      },
    );
  }

  void _showHistoryItemOptions(MediaItem item) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: Text(item.title),
        message: const Text('Would you like to remove this from your history?'),
        actions: [
          CompactActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              WatchHistory.removeItem(item.id);
              Navigator.pop(ctx);
            },
            child: const Text('Remove from History'),
          ),
        ],
        cancelButton: CompactActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _buildSeriesProgressCard(SeriesProgress progress, CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _showSeriesProgressDetail(progress, theme),
      onLongPress: () => _showSeriesProgressOptions(progress),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: isDark
              ? (SettingsService.instance.isAmoled ? const Color(0x77121212) : const Color(0x771C1C1E))
              : const Color(0x77FFFFFF),
          borderRadius: 12.0,
          shadowOffset: 2.5,
        ),
        child: Row(
          children: [
            Container(
              decoration: AppTheme.brutalistDecoration(
                context: context,
                borderRadius: 12.0,
                shadowOffset: 1.5,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(imageUrl: 'https://image.tmdb.org/t/p/w200${progress.posterPath}', width: 50, height: 75, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(progress.title.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('IN PROGRESS', style: GoogleFonts.spaceGrotesk(color: AppTheme.neonYellow, fontSize: 11, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const Icon(FluentIcons.chevron_right_24_regular, size: 16, color: CupertinoColors.systemGrey),
          ],
        ),
      ),
    );
  }

  void _showSeriesProgressOptions(SeriesProgress progress) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CompactActionSheet(
        title: Text(progress.title),
        message: const Text('Would you like to remove this series progress?'),
        actions: [
          CompactActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              CollectionService.instance.removeSeriesProgress(progress.seriesId);
              Navigator.pop(ctx);
            },
            child: const Text('Clear Progress'),
          ),
        ],
        cancelButton: CompactActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _buildCollectionCard(MediaCollection collection, CupertinoThemeData theme) {
    return GlassBox(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(FluentIcons.folder_24_filled, size: 40, color: AppTheme.neonYellow),
          const SizedBox(height: 8),
          Text(collection.name.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w900), maxLines: 1),
          const SizedBox(height: 2),
          Text('${collection.items.length} ITEMS', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: CupertinoColors.systemGrey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCreateButton(String label, IconData icon, Color color, VoidCallback onTap, CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.brutalistDecoration(
          context: context,
          color: isDark
              ? (SettingsService.instance.isAmoled ? AppTheme.amoledSurface : AppTheme.darkSlate)
              : AppTheme.neonYellow,
          borderRadius: 4.0,
          shadowOffset: 3.0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isDark ? CupertinoColors.white : CupertinoColors.black),
            const SizedBox(width: 12),
            Text(
              label.toUpperCase(), 
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w900, 
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                letterSpacing: 0.5,
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, CupertinoThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(FluentIcons.library_24_regular, size: 64, color: CupertinoColors.systemGrey4),
          const SizedBox(height: 16),
          Text(message.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w900, color: CupertinoColors.systemGrey)),
        ],
      ),
    );
  }

  void _openDetail(MediaItem item) {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(builder: (_) => DetailScreen(item: item)),
    );
  }

  void _showCreateCollectionDialog() {
    final controller = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('New Collection'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Collection Name',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              if (controller.text.isNotEmpty) {
                CollectionService.instance.createCollection(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabText(String text, CupertinoThemeData theme, bool selected) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: selected
              ? CupertinoColors.black
              : (isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73)),
        ),
      ),
    );
  }

  void _showSeriesProgressDetail(SeriesProgress progress, CupertinoThemeData theme) {
    final item = MediaItem(
      id: progress.seriesId,
      title: progress.title,
      overview: '',
      posterPath: progress.posterPath,
      backdropPath: '',
      voteAverage: 0.0,
      releaseDate: '',
      mediaType: 'tv',
    );
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(builder: (_) => DetailScreen(item: item)),
    );
  }

}

class LinearProgressIndicator extends StatelessWidget {
  final double value;
  final Color backgroundColor;
  final AlwaysStoppedAnimation<Color> valueColor;
  final double minHeight;

  const LinearProgressIndicator({
    super.key,
    required this.value,
    required this.backgroundColor,
    required this.valueColor,
    required this.minHeight,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final borderColor = isDark ? CupertinoColors.white : CupertinoColors.black;
    return Container(
      height: minHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: valueColor.value,
            borderRadius: BorderRadius.circular(0),
          ),
        ),
      ),
    );
  }
}
