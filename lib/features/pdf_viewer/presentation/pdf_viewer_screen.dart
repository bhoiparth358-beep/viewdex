import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';

/// PDF Viewer screen supporting both Read Mode and Edit Mode.
///
/// In Read Mode:
/// - Smooth PDF viewing, scrolling, pinch-to-zoom
/// - Text search with match highlighting and prev/next navigation
/// - Bookmark / Table of Contents navigation
/// - Go-to-page navigation
/// - Sharing and opening with external applications
///
/// In Edit Mode:
/// - Horizontal scrollable page thumbnail strip
/// - Multi-page selection
/// - Page operation controls (Pages, Add, Delete, Rotate)
/// - Transparent feedback per spec rules regarding native manipulation engine requirements
class PdfViewerScreen extends StatefulWidget {
  final String path;

  const PdfViewerScreen({super.key, required this.path});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  late final PdfTextSearcher _textSearcher;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  PdfDocument? _document;
  int _currentPage = 1;
  int _pageCount = 0;
  bool _isEditMode = false;
  bool _isSearchMode = false;
  final Set<int> _selectedPages = <int>{};
  List<PdfOutlineNode>? _outline;
  bool _outlineLoaded = false;

  @override
  void initState() {
    super.initState();
    _textSearcher = PdfTextSearcher(_pdfViewerController)
      ..addListener(_onSearchUpdated);
  }

  void _onSearchUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _textSearcher.removeListener(_onSearchUpdated);
    _textSearcher.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ==========================================
  // Mode & Selection Handlers
  // ==========================================

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (!_isEditMode) {
        _selectedPages.clear();
      }
    });

    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEditMode
              ? 'Entered Edit Mode. Tap thumbnails to select pages.'
              : 'Switched to Read Mode.',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _togglePageSelection(int pageNumber) {
    setState(() {
      if (_selectedPages.contains(pageNumber)) {
        _selectedPages.remove(pageNumber);
      } else {
        _selectedPages.add(pageNumber);
      }
    });
  }

  void _selectAllPages() {
    if (_pageCount <= 0) return;
    setState(() {
      _selectedPages.addAll(List.generate(_pageCount, (index) => index + 1));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPages.clear();
    });
  }

  // ==========================================
  // Edit Operations
  // ==========================================

  void _showEditOperationUnavailable(String operation) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'PDF page manipulation requires additional setup. Coming in future update.',
        ),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPagesOverviewDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.pages_outlined),
              SizedBox(width: 8),
              Text('Page Overview'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Pages: $_pageCount'),
              const SizedBox(height: 8),
              Text('Current Page: $_currentPage'),
              const SizedBox(height: 8),
              Text(
                'Selected Pages: ${_selectedPages.isEmpty ? "None" : (_selectedPages.toList()..sort()).join(", ")}',
              ),
              const SizedBox(height: 12),
              const Text(
                'Note: Advanced PDF restructuring (merging, splitting, reordering) requires native engine integration.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // Navigation & Dialogs
  // ==========================================

  void _goToPage(int pageNumber) {
    if (pageNumber >= 1 && pageNumber <= _pageCount) {
      _pdfViewerController.goToPage(pageNumber: pageNumber);
      setState(() {
        _currentPage = pageNumber;
      });
    }
  }

  void _showGoToPageDialog() {
    final textController = TextEditingController(text: '$_currentPage');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Go to Page'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter page number (1 to $_pageCount):'),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                keyboardType: TextInputType.number,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Page',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
                onSubmitted: (value) {
                  final target = int.tryParse(value);
                  if (target != null && target >= 1 && target <= _pageCount) {
                    Navigator.of(context).pop();
                    _goToPage(target);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final target = int.tryParse(textController.text);
                if (target != null && target >= 1 && target <= _pageCount) {
                  Navigator.of(context).pop();
                  _goToPage(target);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please enter a valid page number between 1 and $_pageCount.',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Go'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadOutlineIfNeeded() async {
    if (!_outlineLoaded && _document != null) {
      try {
        final outline = await _document!.loadOutline();
        setState(() {
          _outline = outline;
          _outlineLoaded = true;
        });
      } catch (e) {
        setState(() {
          _outline = null;
          _outlineLoaded = true;
        });
      }
    }
  }

  Future<void> _showBookmarksSheet() async {
    await _loadOutlineIfNeeded();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final outline = _outline;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.bookmark_outline),
                      const SizedBox(width: 8),
                      Text(
                        'Document Bookmarks',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: outline == null || outline.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bookmark_border, size: 48, color: Colors.grey),
                              SizedBox(height: 12),
                              Text(
                                'No bookmarks or outline found in this PDF.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: outline.length,
                          itemBuilder: (context, index) {
                            return _buildOutlineTile(outline[index]);
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOutlineTile(PdfOutlineNode node) {
    if (node.children.isNotEmpty) {
      return ExpansionTile(
        leading: const Icon(Icons.bookmark, size: 20),
        title: Text(node.title.isEmpty ? 'Untitled' : node.title),
        children: node.children.map(_buildOutlineTile).toList(),
        onExpansionChanged: (expanded) {
          if (node.dest != null) {
            _pdfViewerController.goToDest(node.dest);
          }
        },
      );
    } else {
      return ListTile(
        leading: const Icon(Icons.bookmark_border, size: 20),
        title: Text(node.title.isEmpty ? 'Untitled' : node.title),
        onTap: () {
          Navigator.of(context).pop();
          if (node.dest != null) {
            _pdfViewerController.goToDest(node.dest);
          }
        },
      );
    }
  }

  // ==========================================
  // External Sharing & Actions
  // ==========================================

  Future<void> _sharePdf() async {
    try {
      await Share.shareXFiles(
        [XFile(widget.path)],
        text: p.basename(widget.path),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share PDF: $e')),
        );
      }
    }
  }

  Future<void> _openExternally() async {
    try {
      final result = await OpenFilex.open(widget.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.isNotEmpty
                  ? result.message
                  : 'No app available to open this PDF externally.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open PDF externally: $e')),
        );
      }
    }
  }

  // ==========================================
  // Search Controls
  // ==========================================

  void _openSearch() {
    setState(() {
      _isSearchMode = true;
    });
    _searchFocusNode.requestFocus();
  }

  void _closeSearch() {
    _searchController.clear();
    _textSearcher.resetTextSearch();
    setState(() {
      _isSearchMode = false;
    });
  }

  void _performSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      _textSearcher.startTextSearch(trimmed, caseInsensitive: true);
    } else {
      _textSearcher.resetTextSearch();
    }
  }

  // ==========================================
  // App Bar Builders
  // ==========================================

  PreferredSizeWidget _buildStandardAppBar(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  p.basename(widget.path),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isEditMode) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'EDIT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_pageCount > 0)
            Text(
              'Page $_currentPage of $_pageCount',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search text',
          onPressed: _openSearch,
        ),
        IconButton(
          icon: Icon(
            _isEditMode ? Icons.check_circle : Icons.edit,
            color: _isEditMode ? theme.colorScheme.primary : null,
          ),
          tooltip: _isEditMode ? 'Exit Edit Mode' : 'Enter Edit Mode',
          onPressed: _toggleEditMode,
        ),
        IconButton(
          icon: const Icon(Icons.share),
          tooltip: 'Share PDF',
          onPressed: _sharePdf,
        ),
        IconButton(
          icon: const Icon(Icons.open_in_new),
          tooltip: 'Open in external app',
          onPressed: _openExternally,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'More actions',
          onSelected: (value) {
            switch (value) {
              case 'goto':
                _showGoToPageDialog();
                break;
              case 'bookmarks':
                _showBookmarksSheet();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'goto',
              child: Row(
                children: [
                  Icon(Icons.pin_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Go to Page'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'bookmarks',
              child: Row(
                children: [
                  Icon(Icons.bookmark_outline, size: 20),
                  SizedBox(width: 12),
                  Text('Bookmarks / Outline'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSearchAppBar(BuildContext context) {
    final matchesCount = _textSearcher.matches.length;
    final isSearching = _textSearcher.isSearching;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Close search',
        onPressed: _closeSearch,
      ),
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search within PDF...',
          border: InputBorder.none,
        ),
        textInputAction: TextInputAction.search,
        onChanged: _performSearch,
        onSubmitted: _performSearch,
      ),
      actions: [
        if (isSearching)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_searchController.text.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '$matchesCount found',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up),
          tooltip: 'Previous match',
          onPressed: matchesCount > 0 ? () => _textSearcher.goToPrevMatch() : null,
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip: 'Next match',
          onPressed: matchesCount > 0 ? () => _textSearcher.goToNextMatch() : null,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Clear',
          onPressed: () {
            _searchController.clear();
            _textSearcher.resetTextSearch();
          },
        ),
      ],
    );
  }

  // ==========================================
  // Edit Mode Bottom Panel
  // ==========================================

  Widget _buildEditModeBottomPanel(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Selection header strip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedPages.isEmpty
                        ? 'Select pages from the strip below'
                        : '${_selectedPages.length} of $_pageCount page(s) selected',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _selectAllPages,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Select All'),
                  ),
                  if (_selectedPages.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _clearSelection,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),

            // 2. Horizontal scrollable thumbnails strip
            SizedBox(
              height: 130,
              child: _document == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _pageCount,
                      itemBuilder: (context, index) {
                        final pageNumber = index + 1;
                        final isSelected = _selectedPages.contains(pageNumber);
                        final isCurrent = _currentPage == pageNumber;

                        return Container(
                          width: 84,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : isCurrent
                                      ? theme.colorScheme.tertiary
                                      : theme.dividerColor.withValues(alpha: 0.5),
                              width: isSelected || isCurrent ? 2.5 : 1,
                            ),
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              _togglePageSelection(pageNumber);
                              _pdfViewerController.goToPage(pageNumber: pageNumber);
                            },
                            child: Stack(
                              children: [
                                // Thumbnail Page View
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Center(
                                    child: PdfPageView(
                                      document: _document,
                                      pageNumber: pageNumber,
                                      maximumDpi: 80,
                                    ),
                                  ),
                                ),
                                // Selection Checkbox
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : Colors.black.withValues(alpha: 0.35),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      isSelected ? Icons.check : Icons.circle_outlined,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                // Page Number Badge
                                Positioned(
                                  bottom: 4,
                                  left: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Page $pageNumber',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),

            // 3. Edit mode action buttons toolbar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  _buildToolbarButton(
                    icon: Icons.pages_outlined,
                    label: 'Pages',
                    onPressed: _showPagesOverviewDialog,
                  ),
                  _buildToolbarButton(
                    icon: Icons.note_add_outlined,
                    label: 'Add',
                    onPressed: () => _showEditOperationUnavailable('Add Page'),
                  ),
                  _buildToolbarButton(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    color: theme.colorScheme.error,
                    onPressed: () => _showEditOperationUnavailable('Delete Page'),
                  ),
                  _buildToolbarButton(
                    icon: Icons.rotate_right_outlined,
                    label: 'Rotate',
                    onPressed: () => _showEditOperationUnavailable('Rotate Page'),
                  ),
                  const VerticalDivider(width: 16, indent: 8, endIndent: 8),
                  _buildToolbarButton(
                    icon: Icons.pin_outlined,
                    label: 'Go to Page',
                    onPressed: _showGoToPageDialog,
                  ),
                  _buildToolbarButton(
                    icon: Icons.search,
                    label: 'Search',
                    onPressed: _openSearch,
                  ),
                  _buildToolbarButton(
                    icon: Icons.bookmark_outline,
                    label: 'Bookmark',
                    onPressed: _showBookmarksSheet,
                  ),
                  _buildToolbarButton(
                    icon: Icons.share_outlined,
                    label: 'Share',
                    onPressed: _sharePdf,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final buttonColor = color ?? theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: buttonColor),
        label: Text(label, style: TextStyle(color: buttonColor, fontSize: 12)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  // ==========================================
  // Main Build Method
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSearchMode ? _buildSearchAppBar(context) : _buildStandardAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                PdfViewer.file(
                  widget.path,
                  controller: _pdfViewerController,
                  params: PdfViewerParams(
                    pagePaintCallbacks: [
                      _textSearcher.pageTextMatchPaintCallback,
                    ],
                    onViewerReady: (document, controller) {
                      setState(() {
                        _document = document;
                        _pageCount = document.pages.length;
                        _currentPage = controller.pageNumber ?? 1;
                      });
                      _loadOutlineIfNeeded();
                    },
                    onPageChanged: (pageNumber) {
                      setState(() {
                        _currentPage = pageNumber ?? 1;
                      });
                    },
                    loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                        const Center(child: CircularProgressIndicator()),
                    errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                        Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.red),
                            const SizedBox(height: 12),
                            Text(
                              'Error loading PDF: $error',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Search status chip overlay when search is active
                if (_isSearchMode &&
                    !_textSearcher.isSearching &&
                    _textSearcher.matches.isNotEmpty)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: Theme.of(context).colorScheme.inverseSurface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          '${_textSearcher.matches.length} matches found',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onInverseSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Edit Mode Bottom Panel
          if (_isEditMode) _buildEditModeBottomPanel(context),
        ],
      ),
    );
  }
}
