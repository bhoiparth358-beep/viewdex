import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/search_providers.dart';
import '../../file_manager/domain/universal_file.dart';
import '../../file_manager/presentation/file_open_handler.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = query;
    });
  }

  IconData _getIconForType(FileType type) {
    return switch (type) {
      FileType.folder => Icons.folder,
      FileType.pdf => Icons.picture_as_pdf,
      FileType.archive => Icons.archive,
      FileType.document => Icons.description,
      FileType.spreadsheet => Icons.table_chart,
      FileType.presentation => Icons.slideshow,
      FileType.image => Icons.image,
      FileType.video => Icons.video_file,
      FileType.audio => Icons.audio_file,
      FileType.text => Icons.text_snippet,
      FileType.unknown => Icons.insert_drive_file,
    };
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final filter = ref.watch(searchFilterProvider);
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SearchBar(
              controller: _controller,
              onChanged: _onSearchChanged,
              leading: const Icon(Icons.search),
              trailing: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      _onSearchChanged('');
                    },
                  ),
              ],
              hintText: 'Search files...',
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildFilterChip('All', null, filter),
                const SizedBox(width: 8),
                _buildFilterChip('PDF', FileType.pdf, filter),
                const SizedBox(width: 8),
                _buildFilterChip('Archive', FileType.archive, filter),
                const SizedBox(width: 8),
                _buildFilterChip('Documents', FileType.document, filter),
                const SizedBox(width: 8),
                _buildFilterChip('Images', FileType.image, filter),
                const SizedBox(width: 8),
                _buildFilterChip('Videos', FileType.video, filter),
                const SizedBox(width: 8),
                _buildFilterChip('Audio', FileType.audio, filter),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: query.length < 2
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Search your files'),
                      ],
                    ),
                  )
                : resultsAsync.when(
                    data: (results) {
                      if (results.isEmpty) {
                        return const Center(
                          child: Text('No files found'),
                        );
                      }
                      return ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final file = results[index];
                          return ListTile(
                            leading: Icon(_getIconForType(file.fileType)),
                            title: Text(file.name),
                            subtitle: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Text(file.formattedSize),
                            onTap: () {
                              FileOpenHandler.openFile(context, file);
                            },
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, stack) => Center(child: Text('Error: $err')),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, FileType? type, FileType? currentFilter) {
    return FilterChip(
      label: Text(label),
      selected: currentFilter == type,
      onSelected: (selected) {
        ref.read(searchFilterProvider.notifier).state = selected ? type : null;
      },
    );
  }
}
