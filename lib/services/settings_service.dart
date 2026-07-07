import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'sync_service.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._internal();
  SettingsService._internal();

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  // Settings keys
  static const _keyThemeMode = 'theme_mode';
  static const _keyCustomFont = 'custom_font';
  static const _keyAmoledTheme = 'amoled_theme';

  // Default values: 0 = system, 1 = dark, 2 = light
  int _themeMode = 0;
  bool _amoledTheme = false;
  String _customFont = 'Inter'; 
  String _appVersion = 'Unknown';
  Color? _accentColor;

  int get themeMode => _themeMode;
  bool get amoledTheme => _amoledTheme;
  bool get isAmoled => _amoledTheme;
  String get customFont => _customFont;
  String get appVersion => _appVersion;
  Color? get accentColor => _accentColor;

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    
    // Load settings
    _themeMode = _prefs.getInt(_keyThemeMode) ?? 0;
    // Migrate old themeMode = 3 to themeMode = 1 (dark) and amoledTheme = true
    if (_themeMode == 3) {
      _themeMode = 1;
      _amoledTheme = true;
      await _prefs.setInt(_keyThemeMode, 1);
      await _prefs.setBool(_keyAmoledTheme, true);
    } else {
      _amoledTheme = _prefs.getBool(_keyAmoledTheme) ?? false;
    }
    _customFont = _prefs.getString(_keyCustomFont) ?? 'Inter';
    final accentVal = _prefs.getInt('accent_color');
    if (accentVal != null) _accentColor = Color(accentVal);

    final info = await PackageInfo.fromPlatform();
    _appVersion = '${info.version}+${info.buildNumber}';

    _isInitialized = true;
    notifyListeners();
  }

  void restore(Map<String, dynamic> data) {
    _themeMode = data['theme_mode'] ?? (data['theme'] == 'dark' ? 1 : (data['theme'] == 'light' ? 2 : 0));
    _amoledTheme = data['amoled_theme'] ?? false;
    _customFont = data['custom_font'] ?? 'Inter';
    if (data['accent_color'] != null) {
      _accentColor = Color(data['accent_color']);
    }
    
    _prefs.setInt(_keyThemeMode, _themeMode);
    _prefs.setBool(_keyAmoledTheme, _amoledTheme);
    _prefs.setString(_keyCustomFont, _customFont);
    if (_accentColor != null) {
       _prefs.setInt('accent_color', _accentColor!.value);
    }
    
    notifyListeners();
  }

  Future<void> setAccentColor(Color? color) async {
    _accentColor = color;
    if (color == null) {
      await _prefs.remove('accent_color');
    } else {
      await _prefs.setInt('accent_color', color.value);
    }
    notifyListeners();
    SyncService.instance.syncSettings();
  }

  Future<void> setThemeMode(int mode) async {
    _themeMode = mode;
    await _prefs.setInt(_keyThemeMode, mode);
    notifyListeners();
    SyncService.instance.syncSettings();
  }

  Future<void> setAmoledTheme(bool val) async {
    _amoledTheme = val;
    await _prefs.setBool(_keyAmoledTheme, val);
    notifyListeners();
    SyncService.instance.syncSettings();
  }

  Future<void> setCustomFont(String font) async {
    _customFont = font;
    await _prefs.setString(_keyCustomFont, font);
    notifyListeners();
    SyncService.instance.syncSettings();
  }



  Future<void> clearCache() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
