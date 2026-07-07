import 'dart:convert';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import '../models/api_models.dart';
import '../services/auth_service.dart';
import '../main.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // ── APP CONFIG ──────────────────────────────────────────────────────────
  static const String appVersion = 'v2.7.0';
  static const String websiteUrl = 'https://luxa-app.vercel.app';

  // ── LOGGING ─────────────────────────────────────────────────────────────
  void _logReq(String url) => debugPrint('🚀 [API REQ] $url');
  void _logRes(String url, int code) =>
      debugPrint('${code == 200 ? '✅' : '❌'} [API RES] $code: $url');
  void _logErr(String url, dynamic e) => debugPrint('💥 [API ERR] $e: $url');

  List<String> _instances = [];
  int _currentInstanceIndex = 0;
  bool _isNoInstanceDialogShowing = false;

  String get currentBaseUrl => _instances.isNotEmpty ? _instances[_currentInstanceIndex] : 'https://docker-11-7860.ny1.zerops.app';

  String get apiBase => '$currentBaseUrl/api';
  String get _apiBase => '$currentBaseUrl/api';

  String get streamingBase => '$_apiBase/media';
  String get downloadBase => '$_apiBase/download';

  // ── UPDATE CONFIG ────────────────────────────────────────────────────────
  static const String _repoOwner = 'Shashwat-CODING';
  static const String _repoName = 'Luxa';
  static const String _updateUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  Future<void> init() async {
    await _fetchInstancesList();
  }

  Future<void> _fetchInstancesList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList('backend_instances');
      if (cached != null && cached.isNotEmpty) {
        _instances = cached;
        debugPrint('📂 Loaded instances from SharedPreferences: $_instances');
      }
    } catch (e) {
      debugPrint('💥 Error reading SharedPreferences: $e');
    }

    const url = 'https://raw.githubusercontent.com/Shashwat-CODING/Luxa/refs/heads/main/instances.txt';
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final content = res.body.trim();
        if (content.isNotEmpty) {
          final list = content.split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (list.isNotEmpty) {
            _instances = list;
            debugPrint('🚀 Updated instances from Github: $_instances');
            
            final prefs = await SharedPreferences.getInstance();
            await prefs.setStringList('backend_instances', _instances);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('💥 Error fetching instances list from Github: $e');
    }

    if (_instances.isEmpty) {
      _instances = [
        'https://docker-11-7860.ny1.zerops.app',
        'https://docker-23e8-7860.prg1.zerops.app'
      ];
      debugPrint('⚠️ Used fallback instances: $_instances');
    }
  }

  Future<http.Response> _executeWithFailover(
    Future<http.Response> Function(String baseUrl) requestFn,
  ) async {
    if (_instances.isEmpty) {
      await _fetchInstancesList();
    }
    if (_instances.isEmpty) {
      _showNoInstanceDialog();
      throw Exception('No instance available');
    }

    dynamic lastError;
    int attempts = _instances.length;

    for (int i = 0; i < attempts; i++) {
      final index = (_currentInstanceIndex + i) % _instances.length;
      final baseUrl = _instances[index];
      try {
        final response = await requestFn(baseUrl);
        if (response.statusCode >= 500) {
          throw Exception('Server error: ${response.statusCode}');
        }
        _currentInstanceIndex = index;
        return response;
      } catch (e) {
        debugPrint('💥 Request to $baseUrl failed: $e. Trying next...');
        lastError = e;
      }
    }

    _showNoInstanceDialog();
    throw Exception('No instance available: $lastError');
  }

  void _showNoInstanceDialog() {
    if (_isNoInstanceDialogShowing) return;
    final context = navigatorKey.currentContext;
    if (context == null) return;
    _isNoInstanceDialogShowing = true;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Connection Error'),
        content: const Text('No instance available. Please check your connection or try again later.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () {
              _isNoInstanceDialogShowing = false;
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Future<http.Response> rawGet(String path, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 15)}) async {
    return _executeWithFailover((baseUrl) {
      final uri = Uri.parse('$baseUrl$path');
      _logReq(uri.toString());
      return http.get(uri, headers: headers).timeout(timeout);
    });
  }

  Future<http.Response> rawPost(String path, {Map<String, String>? headers, dynamic body, Duration timeout = const Duration(seconds: 15)}) async {
    return _executeWithFailover((baseUrl) {
      final uri = Uri.parse('$baseUrl$path');
      _logReq(uri.toString());
      return http.post(uri, headers: headers, body: body).timeout(timeout);
    });
  }

  Future<dynamic> post(String endpoint, dynamic body) async {
    if (!isConfigured) return null;
    final headers = {
      ...AuthService.instance.authHeaders,
      'Content-Type': 'application/json',
    };
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api$endpoint');
        _logReq(uri.toString());
        return http.post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 15));
      });
      _logRes(endpoint, res.statusCode);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body);
      }
    } catch (e) {
      _logErr(endpoint, e);
    }
    return null;
  }

  bool get isConfigured => true;

  // ── TMDB METHODS ─────────────────────────────────────────────────────────

  Future<List<MediaItem>> _fetchTmdbMovies(
    String endpoint, {
    Map<String, String>? extra,
  }) async {
    if (!isConfigured) return [];
    final headers = {
      ...AuthService.instance.authHeaders,
      'Content-Type': 'application/json',
    };
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/tmdb$endpoint').replace(queryParameters: extra);
        _logReq(uri.toString());
        return http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      });
      _logRes(endpoint, res.statusCode);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List? ?? [];
        return results
            .map((j) => MediaItem.fromMovieJson(j))
            .where((m) => m.posterPath != null)
            .toList();
      }
    } catch (e) {
      _logErr(endpoint, e);
    }
    return [];
  }

  Future<List<MediaItem>> _fetchTmdbTv(
    String endpoint, {
    Map<String, String>? extra,
  }) async {
    if (!isConfigured) return [];
    final headers = {
      ...AuthService.instance.authHeaders,
      'Content-Type': 'application/json',
    };
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/tmdb$endpoint').replace(queryParameters: extra);
        _logReq(uri.toString());
        return http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      });
      _logRes(endpoint, res.statusCode);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List? ?? [];
        return results
            .map((j) => MediaItem.fromTvJson(j))
            .where((m) => m.posterPath != null)
            .toList();
      }
    } catch (e) {
      _logErr(endpoint, e);
    }
    return [];
  }

  Future<List<MediaItem>> getTrendingMovies() =>
      _fetchTmdbMovies('/trending/movie/week');
  Future<List<MediaItem>> getPopularMovies() =>
      _fetchTmdbMovies('/movie/popular');
  Future<List<MediaItem>> getTopRatedMovies() =>
      _fetchTmdbMovies('/movie/top_rated');
  Future<List<MediaItem>> getUpcomingMovies() =>
      _fetchTmdbMovies('/movie/upcoming');
  Future<List<MediaItem>> getNowPlayingMovies() =>
      _fetchTmdbMovies('/movie/now_playing');

  Future<List<MediaItem>> getPopularTvShows() => _fetchTmdbTv('/tv/popular');
  Future<List<MediaItem>> getTopRatedTvShows() => _fetchTmdbTv('/tv/top_rated');
  Future<List<MediaItem>> getTrendingTv() => _fetchTmdbTv('/trending/tv/week');
  Future<List<MediaItem>> getAiringTodayTv() =>
      _fetchTmdbTv('/tv/airing_today');

  Future<List<MediaItem>> getAnimeMovies() => _fetchTmdbMovies(
    '/discover/movie',
    extra: {'with_genres': '16', 'sort_by': 'popularity.desc'},
  );
  Future<List<MediaItem>> getAnimeTv() => _fetchTmdbTv(
    '/discover/tv',
    extra: {'with_genres': '16', 'sort_by': 'popularity.desc'},
  );

  Future<List<MediaItem>> search(String query) async {
    if (!isConfigured || query.trim().isEmpty) return [];
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/tmdb/search/multi').replace(queryParameters: {'query': query});
        _logReq(uri.toString());
        return http.get(uri).timeout(const Duration(seconds: 10));
      });
      _logRes('search/multi', res.statusCode);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['results'] as List? ?? [];
        return results
            .map((j) {
              if (j['media_type'] == 'person') return null;
              final m = MediaItem.fromSearchJson(j);
              if (m.id == 0) return null;
              return m;
            })
            .whereType<MediaItem>()
            .where((m) => m.posterPath != null || m.backdropPath != null)
            .toList();
      }
    } catch (e) {
      _logErr('search/multi', e);
    }
    return [];
  }

  Future<MediaDetail?> getMovieDetail(int id) async {
    if (!isConfigured) return null;
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/tmdb/movie/$id').replace(queryParameters: {'append_to_response': 'credits'});
        _logReq(uri.toString());
        return http.get(uri).timeout(const Duration(seconds: 10));
      });
      _logRes('movie/$id', res.statusCode);
      if (res.statusCode == 200) {
        return MediaDetail.fromMovieDetailJson(jsonDecode(res.body));
      }
    } catch (e) {
      _logErr('movie/$id', e);
    }
    return null;
  }

  Future<MediaDetail?> getTvDetail(int id) async {
    if (!isConfigured) return null;
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/tmdb/tv/$id').replace(queryParameters: {'append_to_response': 'credits'});
        _logReq(uri.toString());
        return http.get(uri).timeout(const Duration(seconds: 10));
      });
      _logRes('tv/$id', res.statusCode);
      if (res.statusCode == 200) {
        return MediaDetail.fromTvDetailJson(jsonDecode(res.body));
      }
    } catch (e) {
      _logErr('tv/$id', e);
    }
    return null;
  }

  Future<TvSeason?> getTvSeasonDetail(int tvId, int seasonNumber) async {
    if (!isConfigured) return null;
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/tmdb/tv/$tvId/season/$seasonNumber');
        _logReq(uri.toString());
        return http.get(uri).timeout(const Duration(seconds: 10));
      });
      _logRes('tv/$tvId/season/$seasonNumber', res.statusCode);
      if (res.statusCode == 200) {
        return TvSeason.fromJson(jsonDecode(res.body));
      }
    } catch (e) {
      _logErr('tv/$tvId/season/$seasonNumber', e);
    }
    return null;
  }

  Future<TvEpisode?> getTvEpisodeDetail(
    int tvId,
    int season,
    int episode,
  ) async {
    if (!isConfigured) return null;
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/tmdb/tv/$tvId/season/$season/episode/$episode');
        _logReq(uri.toString());
        return http.get(uri).timeout(const Duration(seconds: 10));
      });
      _logRes('tv/$tvId/season/$season/episode/$episode', res.statusCode);
      if (res.statusCode == 200) {
        return TvEpisode.fromJson(jsonDecode(res.body));
      }
    } catch (e) {
      _logErr('tv/$tvId/season/$season/episode/$episode', e);
    }
    return null;
  }

  Future<List<MediaItem>> getSimilarMovies(int id) =>
      _fetchTmdbMovies('/movie/$id/similar');
  Future<List<MediaItem>> getSimilarTv(int id) =>
      _fetchTmdbTv('/tv/$id/similar');


  // ── UPDATE METHODS ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> checkForUpdate() async {
    _logReq(_updateUrl);
    try {
      final response = await http.get(Uri.parse(_updateUrl));
      _logRes(_updateUrl, response.statusCode);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestTag = data['tag_name'] as String;
        final latest = latestTag.startsWith('v')
            ? latestTag.substring(1)
            : latestTag;
        final current = appVersion.startsWith('v')
            ? appVersion.substring(1)
            : appVersion;
        if (_isNewer(latest, current)) {
          return {
            'version': latestTag,
            'changelog': data['body'],
            'url': data['html_url'],
          };
        }
      }
    } catch (e) {
      _logErr(_updateUrl, e);
    }
    return null;
  }

  bool _isNewer(String latest, String current) {
    List<int> l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    int maxLen = l.length > c.length ? l.length : c.length;
    for (int i = 0; i < maxLen; i++) {
      int lVal = i < l.length ? l[i] : 0;
      int cVal = i < c.length ? c[i] : 0;
      if (lVal > cVal) return true;
      if (lVal < cVal) return false;
    }
    return false;
  }



  // ── ANIME METHODS ───────────────────────────────────────────────────────

  Future<Map<String, List<MediaItem>>> getAnimeHome() async {
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/anime/home');
        _logReq(uri.toString());
        return http.get(uri).timeout(const Duration(seconds: 15));
      });
      _logRes('anime/home', res.statusCode);
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body)['data'];
        final Map<String, List<MediaItem>> result = {};
        
        data.forEach((category, items) {
          if (items is List) {
            result[category] = items.map((j) => _mapAnimeToMediaItem(j)).toList();
          }
        });
        return result;
      }
    } catch (e) {
      _logErr('anime/home', e);
    }
    return {};
  }

  Future<List<MediaItem>> searchAnime(String query, {int page = 1}) async {
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/anime/search?s=$query&page=$page');
        _logReq(uri.toString());
        return http.get(uri).timeout(const Duration(seconds: 15));
      });
      _logRes('anime/search', res.statusCode);
      if (res.statusCode == 200) {
        final List results = jsonDecode(res.body)['results'] ?? [];
        return results.map((j) => _mapAnimeToMediaItem(j)).toList();
      }
    } catch (e) {
      _logErr('anime/search', e);
    }
    return [];
  }

  MediaItem _mapAnimeToMediaItem(Map<String, dynamic> json) {
    final slug = json['slug'] ?? '';
    final type = json['type'] ?? 'movie';
    String image = json['image'] ?? '';
    if (image.startsWith('//')) image = 'https:$image';
    
    return MediaItem(
      id: slug.hashCode,
      title: json['title'] ?? 'Unknown',
      overview: null,
      posterPath: image,
      backdropPath: image,
      voteAverage: 0.0,
      releaseDate: null,
      mediaType: 'anime',
      extras: {
        'slug': slug,
        'anime_type': type, // 'movie' or 'series'
        'api_route': json['api_route'],
        'quality': json['quality'],
        'episode': json['episode'],
      },
    );
  }

  Future<MediaDetail?> getAnimeDetail(MediaItem item) async {
    final slug = item.extras?['slug'];
    final type = item.extras?['anime_type'] ?? 'movie';
    if (slug == null) return null;

    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/anime/details/$type/$slug');
        _logReq(uri.toString());
        return http.get(uri).timeout(const Duration(seconds: 15));
      });
      _logRes('anime/details/$type/$slug', res.statusCode);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is! Map || decoded['data'] == null) {
          debugPrint('❌ [API ERR] Invalid detail response: ${res.body}');
          return null;
        }
        final data = decoded['data'];
        
        String image = data['image'] ?? item.posterPath;
        if (image.startsWith('//')) image = 'https:$image';

        List<TvSeason> seasons = [];
        if (type == 'series' && data['episodes'] != null) {
          final episodes = (data['episodes'] as List).map((e) {
            String epImg = e['thumbnail'] ?? '';
            if (epImg.startsWith('//')) epImg = 'https:$epImg';
            return TvEpisode(
              id: (e['slug'] ?? '').hashCode,
              name: e['title'] ?? '',
              overview: null,
              stillPath: epImg,
              episodeNumber: int.tryParse(e['episode_number']?.toString() ?? '0') ?? 0,
              seasonNumber: 1,
              voteAverage: 0.0,
              extras: {'slug': e['slug']},
            );
          }).toList();

          seasons = [
            TvSeason(
              id: 1,
              name: 'Season 1',
              seasonNumber: 1,
              episodeCount: episodes.length,
              episodes: episodes,
            )
          ];
        }

        return MediaDetail(
          id: item.id,
          title: data['title'] ?? item.title,
          overview: data['description'],
          posterPath: image,
          backdropPath: image,
          voteAverage: 0.0,
          releaseDate: data['year']?.toString(),
          mediaType: 'anime',
          genres: (data['genres'] as List?)?.map((g) => g['name'].toString()).toList() ?? [],
          seasons: seasons,
          extras: {
            ...item.extras ?? {},
            'servers': data['servers'],
          },
        );
      }
    } catch (e) {
      _logErr('anime/details/$type/$slug', e);
    }
    return null;
  }

  Future<Map<String, dynamic>?> getAnimePlaybackDetails(String slug, String type) async {
    try {
      final res = await _executeWithFailover((baseUrl) {
        final uri = Uri.parse('$baseUrl/api/anime/details/$type/$slug');
        _logReq(uri.toString());
        return http.get(uri).timeout(const Duration(seconds: 15));
      });
      _logRes('anime/playback/$type/$slug', res.statusCode);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is! Map || decoded['data'] == null) {
          debugPrint('❌ [API ERR] Invalid playback response: ${res.body}');
          return null;
        }
        final data = decoded['data'];
        final List servers = data['servers'] ?? [];
        
        List<StreamSource> sources = servers.map((s) {
          final streamData = s['streamData'];
          String streamUrl = s['hls'] ?? s['url'] ?? '';
          if (streamData != null && streamData['videoSource'] != null) {
            streamUrl = streamData['videoSource'];
          }
          
          return StreamSource(
            quality: 'HD',
            url: streamUrl,
            source: s['name'] ?? 'AnimeSalt',
            serverId: s['id'] ?? 0,
            referer: 'https://animesalt.ac/',
            origin: 'https://animesalt.ac',
          );
        }).toList();

        // Ensure Server 1 is first, filter out broken ones if needed
        sources.sort((a, b) => a.serverId.compareTo(b.serverId));

        return {
          'sources': sources,
          'next_slug': _extractSlugFromRoute(data['next_episode_route']),
          'prev_slug': _extractSlugFromRoute(data['prev_episode_route']),
          'title': data['title'],
          'episode_info': data['episode_info'],
        };
      }
    } catch (e) {
      _logErr('anime/playback/$type/$slug', e);
    }
    return null;
  }

  String? _extractSlugFromRoute(String? route) {
    if (route == null || route.isEmpty) return null;
    return route.split('/').last;
  }

}
