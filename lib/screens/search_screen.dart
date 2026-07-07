import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../models/media_item.dart';
import '../services/api_service.dart';
import 'detail_screen.dart';
import '../widgets/ios_widgets.dart';

class SearchScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final String? initialQuery;
  final TextEditingController? controller;
  final bool isTab;
  const SearchScreen({super.key, this.onBack, this.initialQuery, this.controller, this.isTab = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _controller;
  final _api = ApiService.instance;

  List<MediaItem> _results = [];
  List<MediaItem> _popular = [];
  bool _loading = false;
  bool _loadingPopular = true;
  bool _searched = false;
  String _filter = 'all';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onControllerChanged);
    _loadPopular();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _doSearch(widget.initialQuery!));
    } else if (_controller.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _doSearch(_controller.text));
    }
  }

  void _onControllerChanged() {
    _onChanged(_controller.text);
  }

  Future<void> _loadPopular() async {
    try {
      final movies = await _api.getTrendingMovies();
      if (mounted) {
        setState(() {
          _popular = movies.take(12).toList();
          _loadingPopular = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPopular = false);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 600), () => _doSearch(q));
  }

  Future<void> _doSearch(String q) async {
    if (!mounted || q.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final futures = [
        _api.search(q.trim()),
        _api.searchAnime(q.trim()),
      ];
      final results = await Future.wait(futures);
      final tmdbResults = results[0];
      final animeResults = results[1];

      if (mounted) {
        setState(() {
          _results = [...tmdbResults, ...animeResults];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MediaItem> get _shown {
    if (_filter == 'all') return _results;
    return _results.where((m) => m.mediaType == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);

    return CupertinoPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: const Text('Search'),
            backgroundColor: CupertinoColors.transparent,
            border: null,
          ),
          if (!widget.isTab)
            SliverToBoxAdapter(
              child: IOSSearchField(
                controller: _controller,
                onChanged: _onChanged,
                placeholder: 'Movies, TV Shows & more',
              ),
            ),
          if (_searched && _results.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(label: 'All', active: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                      const SizedBox(width: 10),
                      _FilterChip(label: 'Movies', active: _filter == 'movie', onTap: () => setState(() => _filter = 'movie')),
                      const SizedBox(width: 10),
                      _FilterChip(label: 'TV Shows', active: _filter == 'tv', onTap: () => setState(() => _filter = 'tv')),
                      const SizedBox(width: 10),
                      _FilterChip(label: 'Anime', active: _filter == 'anime', onTap: () => setState(() => _filter = 'anime')),
                    ],
                  ),
                ),
              ),
            ),
          SliverFillRemaining(
            child: _buildBody(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(CupertinoThemeData theme) {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 15));
    }

    if (!_searched) {
      return _buildDiscoverView(theme);
    }

    final shown = _shown;
    if (shown.isEmpty) {
      return _buildNoResults(theme);
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: shown.length,
      itemBuilder: (_, i) => _ResultCard(
        item: shown[i],
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute(builder: (_) => DetailScreen(item: shown[i])),
        ),
      ).animate().fadeIn(delay: (i * 30).ms),
    );
  }

  Widget _buildDiscoverView(CupertinoThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Popular Now',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? CupertinoColors.white : CupertinoColors.black,
          ),
        ),
        const SizedBox(height: 16),
        if (_loadingPopular)
          const Center(child: CupertinoActivityIndicator())
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            itemCount: _popular.length,
            itemBuilder: (_, i) => _ResultCard(
              item: _popular[i],
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(builder: (_) => DetailScreen(item: _popular[i])),
              ),
            ).animate().fadeIn(delay: (i * 30).ms),
          ),
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildNoResults(CupertinoThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.search_24_regular, size: 64, color: CupertinoColors.systemGrey3),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = CupertinoTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? theme.primaryColor : CupertinoColors.systemGrey6,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: active ? CupertinoColors.white : CupertinoColors.systemGrey,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  const _ResultCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: item.fullPosterUrl,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: CupertinoColors.systemGrey5),
        ),
      ),
    );
  }
}
