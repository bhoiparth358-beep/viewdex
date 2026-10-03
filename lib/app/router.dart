import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/file_manager/domain/universal_file.dart';
import '../shared/widgets/bottom_nav_shell.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/file_manager/presentation/file_manager_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/image_viewer/presentation/image_viewer_screen.dart';
import '../features/video_player/presentation/video_player_screen.dart';
import '../features/text_viewer/presentation/text_viewer_screen.dart';
import '../features/pdf_viewer/presentation/pdf_viewer_screen.dart';
import '../features/archive_viewer/presentation/archive_viewer_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => BottomNavShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/files',
            builder: (context, state) => const FileManagerScreen(),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchScreen(),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Viewer routes (full-screen, no bottom nav)
      GoRoute(
        path: '/viewer/image',
        builder: (context, state) =>
            ImageViewerScreen(filePath: state.extra as String),
      ),
      GoRoute(
        path: '/viewer/video',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return VideoPlayerScreen(
            filePath: extra['path'] as String,
            isAudio: extra['isAudio'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/viewer/audio',
        builder: (context, state) => VideoPlayerScreen(
          filePath: state.extra as String,
          isAudio: true,
        ),
      ),
      GoRoute(
        path: '/viewer/text',
        builder: (context, state) =>
            TextViewerScreen(filePath: state.extra as String),
      ),
      GoRoute(
        path: '/viewer/pdf',
        builder: (context, state) =>
            PdfViewerScreen(path: state.extra as String),
      ),
      GoRoute(
        path: '/viewer/archive',
        builder: (context, state) =>
            ArchiveViewerScreen(path: state.extra as String),
      ),
    ],
  );

  static String viewerRouteForFileType(FileType type) {
    return switch (type) {
      FileType.image => '/viewer/image',
      FileType.video => '/viewer/video',
      FileType.audio => '/viewer/audio',
      FileType.text => '/viewer/text',
      FileType.pdf => '/viewer/pdf',
      FileType.archive => '/viewer/archive',
      _ => '/viewer/text',
    };
  }
}
