import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/file_manager/presentation/file_open_handler.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Manages and persists the application's [ThemeMode] using [SharedPreferences].
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const String _themeKey = 'theme_mode';

  ThemeModeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  /// Loads the persisted theme mode from SharedPreferences.
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_themeKey);
      if (savedTheme != null) {
        switch (savedTheme) {
          case 'light':
            state = ThemeMode.light;
            break;
          case 'dark':
            state = ThemeMode.dark;
            break;
          case 'system':
          default:
            state = ThemeMode.system;
            break;
        }
      }
    } catch (_) {
      // Gracefully fallback to ThemeMode.system on any read error
      state = ThemeMode.system;
    }
  }

  /// Updates the current theme mode and saves the preference to SharedPreferences.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      String value;
      switch (mode) {
        case ThemeMode.light:
          value = 'light';
          break;
        case ThemeMode.dark:
          value = 'dark';
          break;
        case ThemeMode.system:
          value = 'system';
          break;
      }
      await prefs.setString(_themeKey, value);
    } catch (_) {
      // Gracefully handle storage errors
    }
  }
}

/// Provider exposing the [ThemeModeNotifier] and current [ThemeMode].
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ViewdexApp extends ConsumerStatefulWidget {
  const ViewdexApp({super.key});

  @override
  ConsumerState<ViewdexApp> createState() => _ViewdexAppState();
}

class _ViewdexAppState extends ConsumerState<ViewdexApp> {
  static const _fileChannel = MethodChannel('com.viewdex.app/file_open');

  @override
  void initState() {
    super.initState();
    _fileChannel.setMethodCallHandler(_handleNativeFileMethod);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialFile();
    });
  }

  Future<void> _checkInitialFile() async {
    try {
      final initialPath =
          await _fileChannel.invokeMethod<String>('getInitialFile');
      if (initialPath != null && initialPath.isNotEmpty) {
        _openExternalFile(initialPath);
      }
    } catch (_) {}
  }

  Future<dynamic> _handleNativeFileMethod(MethodCall call) async {
    if (call.method == 'onFileOpened') {
      final path = call.arguments as String?;
      if (path != null && path.isNotEmpty) {
        _openExternalFile(path);
      }
    }
  }

  void _openExternalFile(String path) {
    final context = AppRouter.rootNavigatorKey.currentContext;
    if (context != null) {
      FileOpenHandler.openFilePath(context, path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Viewdex',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: AppRouter.router,
    );
  }
}
