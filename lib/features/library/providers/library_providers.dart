import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

class FavoritesNotifier extends StateNotifier<List<String>> {
  final SharedPreferences? _prefs;

  FavoritesNotifier(this._prefs) : super([]) {
    _loadFavorites();
  }

  void _loadFavorites() {
    if (_prefs != null) {
      final list = _prefs.getStringList('favorites') ?? [];
      state = list;
    }
  }

  void addFavorite(String path) {
    if (!state.contains(path)) {
      state = [...state, path];
      _saveFavorites();
    }
  }

  void removeFavorite(String path) {
    state = state.where((p) => p != path).toList();
    _saveFavorites();
  }

  bool isFavorite(String path) => state.contains(path);

  void toggle(String path) {
    if (isFavorite(path)) {
      removeFavorite(path);
    } else {
      addFavorite(path);
    }
  }

  void _saveFavorites() {
    _prefs?.setStringList('favorites', state);
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<String>>((ref) {
  final prefsAsync = ref.watch(sharedPrefsProvider);
  return prefsAsync.maybeWhen(
    data: (prefs) => FavoritesNotifier(prefs),
    orElse: () => FavoritesNotifier(null),
  );
});

class RecentFilesNotifier extends StateNotifier<List<String>> {
  final SharedPreferences? _prefs;

  RecentFilesNotifier(this._prefs) : super([]) {
    _loadRecents();
  }

  void _loadRecents() {
    if (_prefs != null) {
      final list = _prefs.getStringList('recent_files') ?? [];
      state = list;
    }
  }

  void addRecent(String path) {
    final newList = state.where((p) => p != path).toList();
    newList.insert(0, path);
    if (newList.length > 50) newList.removeLast();
    state = newList;
    _saveRecents();
  }

  void _saveRecents() {
    _prefs?.setStringList('recent_files', state);
  }
}

final recentFilesProvider =
    StateNotifierProvider<RecentFilesNotifier, List<String>>((ref) {
  final prefsAsync = ref.watch(sharedPrefsProvider);
  return prefsAsync.maybeWhen(
    data: (prefs) => RecentFilesNotifier(prefs),
    orElse: () => RecentFilesNotifier(null),
  );
});
