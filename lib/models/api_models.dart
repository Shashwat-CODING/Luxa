
class Subtitle {
  final String url;
  final String lang;
  Subtitle({required this.url, required this.lang});

  Map<String, String> toJson() => {'url': url, 'lang': lang};
  factory Subtitle.fromJson(Map<String, dynamic> json) => Subtitle(
    url: json['url']?.toString() ?? '',
    lang: (json['lang'] ?? json['language'] ?? 'Unknown').toString(),
  );
}

class StreamSource {
  final String quality;
  final String url;
  final String source;
  final int serverId;
  final String? referer;
  final String? origin;
  final String? size;
  final List<Subtitle>? subtitles;
  final Map<String, String>? headers;
  final int priority;

  /// When true, the player must send NO headers at all for this source.
  final bool noHeaders;
  final int fileSize;
  final String? sizeText; // Human-readable size (e.g. "25.30 GB")
  final String? type;     // Content type (e.g. "mp4", "m3u8")
  final String? language;

  static const String kDefaultReferer = 'https://rivestream.app/';
  static const String kDefaultOrigin = 'https://rivestream.app';

  String get resolvedReferer =>
      serverId == 9 ? 'https://cinemaos.live' : ((referer != null && referer!.isNotEmpty) ? referer! : kDefaultReferer);
  String get resolvedOrigin =>
      serverId == 9 ? 'https://cinemaos.live' : ((origin != null && origin!.isNotEmpty) ? origin! : kDefaultOrigin);

  StreamSource({
    required this.quality,
    required this.url,
    required this.source,
    required this.serverId,
    String? referer,
    String? origin,
    this.size,
    this.subtitles,
    Map<String, String>? headers,
    this.priority = 10,
    this.noHeaders = false,
    this.fileSize = 0,
    this.sizeText,
    this.type,
    this.language,
  })  : this.referer = serverId == 9 ? 'https://cinemaos.live' : referer,
        this.origin = serverId == 9 ? 'https://cinemaos.live' : origin,
        this.headers = serverId == 9
            ? {
                ...?headers,
                'Referer': 'https://cinemaos.live',
                'Origin': 'https://cinemaos.live',
              }
            : (serverId == 6 && (referer != null || origin != null))
                ? {
                    ...?headers,
                    if (referer != null) 'Referer': referer,
                    if (origin != null) 'Origin': origin,
                    'User-Agent':
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
                  }
                : headers;

  factory StreamSource.fromJson(Map<String, dynamic> json) {
    var rawQuality = json['quality'];
    String q = 'Auto';
    if (rawQuality is num) {
      q = '${rawQuality}p';
    } else if (rawQuality != null) {
      q = rawQuality.toString();
      if (!q.contains('p') && int.tryParse(q) != null) q = '${q}p';
    }

    final String metadata = (json['metadata'] ?? json['server'] ?? json['provider'] ?? 'Unknown').toString();
    
    // Extract language from various potential fields
    String? language = (json['lang'] ?? json['language'])?.toString();
    
    // Handle the new Language:Type format (e.g., "Hindi:dubbed", "Arabic:subtitle")
    if (language != null && language.contains(':')) {
      final parts = language.split(':');
      if (parts.length == 2) {
        String langName = parts[0].trim();
        String typeLabel = parts[1].trim().toLowerCase();
        
        // Capitalize language name (e.g. ptbr -> Ptbr)
        if (langName.isNotEmpty) {
          langName = langName[0].toUpperCase() + langName.substring(1);
        }

        if (typeLabel == 'dubbed' || typeLabel == 'dub') {
           language = '$langName Dubbed';
        } else if (typeLabel == 'subtitle' || typeLabel == 'sub') {
           language = '$langName Subbed';
        } else if (typeLabel == 'audio') {
           language = langName; // Original:audio -> Original
        } else {
           language = '$langName ${typeLabel[0].toUpperCase()}${typeLabel.substring(1)}';
        }
      }
    }

    // Handle the 'type' field as requested: sun -> Subtitles, dub -> Dubbed
    final String? typeField = json['type']?.toString().toLowerCase();
    if (language == null || language.toLowerCase() == 'unknown') {
      if (typeField == 'sun' || typeField == 'sub') {
        language = 'Subbed';
      } else if (typeField == 'dub') {
        language = 'Dubbed';
      }
    }

    if (language == null || language.isEmpty || language.toLowerCase() == 'unknown') {
      final metaMatch = RegExp(r'\((.*?)\)', caseSensitive: false).firstMatch(metadata);
      if (metaMatch != null) {
        final String content = metaMatch.group(1)!;
        final String lowerContent = content.toLowerCase();

        if (lowerContent.contains('dub')) {
          String langName = content.replaceAll(RegExp(r'dub', caseSensitive: false), '').trim();
          language = langName.isEmpty ? 'Dubbed' : '$langName Dubbed';
        } else if (lowerContent.contains('sub') || lowerContent.contains('sun')) {
          String langName = content.replaceAll(RegExp(r'sub|sun', caseSensitive: false), '').trim();
          language = langName.isEmpty ? 'Subbed' : '$langName Subbed';
        } else if (lowerContent.contains('original') || lowerContent.contains('audio')) {
          language = 'Original';
        } else {
          language = content; // Fallback to content inside parentheses
        }
      } else {
        // Fallback checks for keywords outside of parentheses
        final String lowerMeta = metadata.toLowerCase();
        if (lowerMeta.contains('sun') || lowerMeta.contains('sub')) {
          language = 'Subbed';
        } else if (lowerMeta.contains('dub')) {
          language = 'Dubbed';
        }
      }
    }

    // Final fallback: if it's from server 2 and still unknown, check if the URL contains clues
    if ((language == null || language.toLowerCase() == 'unknown') && json['serverId'] == 2) {
       final url = json['url']?.toString().toLowerCase() ?? '';
       if (url.contains('dub')) language = 'Dubbed';
       else if (url.contains('sub')) language = 'Subbed';
    }

    final String rawUrl = json['url']?.toString() ?? '';
    final bool isAudioOnly = q.toLowerCase().startsWith('audio');

    return StreamSource(
      quality: q,
      url: isAudioOnly ? '' : rawUrl,
      source: metadata,
      serverId: json['serverId'] ?? 0,
      referer: json['referer']?.toString(),
      origin: json['origin']?.toString(),
      size: json['size']?.toString(),
      sizeText: json['sizeText']?.toString(),
      type: typeField,
      headers: (json['headers'] as Map?)?.cast<String, String>(),
      language: language,
    );
  }
  @override
  String toString() => '[$serverId] $source ($quality) ${language != null ? "[$language]" : ""} - $url';
}

class User {
  final int id;
  final String username;
  final String email;
  final String? name;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.name,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    username: json['username'],
    email: json['email'],
    name: json['name'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'name': name,
  };
}
