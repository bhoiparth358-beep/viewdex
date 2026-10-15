import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class SlideParagraphItem {
  final String text;
  final int level;
  final bool isBold;
  final bool isItalic;
  final TextAlign alignment;
  final double? fontSize;
  final bool isSubtitle;

  const SlideParagraphItem({
    required this.text,
    this.level = 0,
    this.isBold = false,
    this.isItalic = false,
    this.alignment = TextAlign.start,
    this.fontSize,
    this.isSubtitle = false,
  });
}

class SlideTableItem {
  final List<List<String>> rows;

  const SlideTableItem({required this.rows});
}

class SlideData {
  final int slideIndex;
  final String? title;
  final List<dynamic> items; // SlideParagraphItem or SlideTableItem

  const SlideData({
    required this.slideIndex,
    this.title,
    required this.items,
  });

  bool get isEmpty => (title == null || title!.trim().isEmpty) && items.isEmpty;
}

class PptxViewerScreen extends StatefulWidget {
  final String filePath;

  const PptxViewerScreen({super.key, required this.filePath});

  @override
  State<PptxViewerScreen> createState() => _PptxViewerScreenState();
}

class _PptxViewerScreenState extends State<PptxViewerScreen> {
  final PageController _pageController = PageController();
  bool _isLoading = true;
  String? _errorMessage;
  List<SlideData> _slides = [];
  int _currentSlideIndex = 0;

  // Search in presentation
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<_PptxSearchMatch> _matches = [];
  int _currentMatchIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPresentation();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPresentation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _slides = [];
      _currentSlideIndex = 0;
    });

    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'File does not exist: ${widget.filePath}';
        });
        return;
      }

      final ext = p.extension(widget.filePath).toLowerCase();
      final bytes = await file.readAsBytes();

      // Check ZIP header
      if (bytes.length < 4 ||
          bytes[0] != 0x50 ||
          bytes[1] != 0x4B ||
          bytes[2] != 0x03 ||
          bytes[3] != 0x04) {
        if (ext == '.ppt') {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Legacy binary PowerPoint (.ppt) format is not supported in the built-in viewer. Please convert to .pptx or open in an external office app.';
          });
          return;
        }
      }

      Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Could not unpack presentation archive. The file might be corrupted or in an unsupported format ($e).';
        });
        return;
      }

      // 1. Find slide order from ppt/presentation.xml and relationships
      final slidePaths = _extractSlidePaths(archive);

      if (slidePaths.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No slides found in this presentation.';
        });
        return;
      }

      // 2. Parse each slide XML
      final List<SlideData> parsedSlides = [];
      int currentNumber = 1;
      for (final slidePath in slidePaths) {
        final slideXml = _findArchiveFileContent(archive, slidePath);
        if (slideXml != null) {
          final slide = _parseSlideXml(slideXml, currentNumber);
          parsedSlides.add(slide);
        } else {
          parsedSlides.add(
            SlideData(slideIndex: currentNumber, title: null, items: []),
          );
        }
        currentNumber++;
      }

      setState(() {
        _slides = parsedSlides;
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('Error loading PPTX: $e\n$stack');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to read presentation: $e';
      });
    }
  }

  List<String> _extractSlidePaths(Archive archive) {
    final List<String> paths = [];

    // Parse ppt/_rels/presentation.xml.rels
    final Map<String, String> rels = {};
    final relsXml =
        _findArchiveFileContent(archive, 'ppt/_rels/presentation.xml.rels') ??
        _findArchiveFileContent(archive, 'ppt/_rels/Presentation.xml.rels');

    if (relsXml != null) {
      final relMatches = RegExp(r'<Relationship\b([^>]*)/?>').allMatches(relsXml);
      for (final rm in relMatches) {
        final attrs = rm.group(1) ?? '';
        final idMatch = RegExp(r'Id="([^"]*)"').firstMatch(attrs);
        final targetMatch = RegExp(r'Target="([^"]*)"').firstMatch(attrs);
        if (idMatch != null && targetMatch != null) {
          String target = targetMatch.group(1)!.replaceAll('\\', '/');
          if (target.startsWith('/')) target = target.substring(1);
          if (!target.toLowerCase().startsWith('ppt/')) {
            target = 'ppt/$target';
          }
          rels[idMatch.group(1)!] = target;
        }
      }
    }

    // Parse ppt/presentation.xml
    final presentationXml =
        _findArchiveFileContent(archive, 'ppt/presentation.xml') ??
        _findArchiveFileContent(archive, 'ppt/Presentation.xml');

    if (presentationXml != null) {
      final sldIdMatches = RegExp(r'<p:sldId\b([^>]*)/?>').allMatches(presentationXml);
      for (final sm in sldIdMatches) {
        final attrs = sm.group(1) ?? '';
        final rIdMatch = RegExp(r'r:id="([^"]*)"').firstMatch(attrs);
        if (rIdMatch != null) {
          final rId = rIdMatch.group(1)!;
          if (rels.containsKey(rId)) {
            paths.add(rels[rId]!);
          }
        }
      }
    }

    // Fallback: search all files matching ppt/slides/slide*.xml and sort naturally
    if (paths.isEmpty) {
      final List<MapEntry<int, String>> fallbackList = [];
      for (final entry in archive) {
        final norm = entry.name.replaceAll('\\', '/');
        final match = RegExp(r'^ppt/slides/slide(\d+)\.xml$', caseSensitive: false).firstMatch(norm);
        if (match != null) {
          final num = int.tryParse(match.group(1)!) ?? 0;
          fallbackList.add(MapEntry(num, norm));
        }
      }
      fallbackList.sort((a, b) => a.key.compareTo(b.key));
      paths.addAll(fallbackList.map((e) => e.value));
    }

    return paths;
  }

  String? _findArchiveFileContent(Archive archive, String path) {
    final normPath = path.replaceAll('\\', '/').toLowerCase();
    for (final file in archive) {
      if (file.isFile && file.name.replaceAll('\\', '/').toLowerCase() == normPath) {
        return utf8.decode(file.content as List<int>, allowMalformed: true);
      }
    }
    return null;
  }

  SlideData _parseSlideXml(String slideXml, int slideNumber) {
    String? title;
    final List<dynamic> items = [];

    // Parse shapes <p:sp>
    final shapeMatches = RegExp(r'<p:sp\b[^>]*>(.*?)</p:sp>', dotAll: true).allMatches(slideXml);
    for (final sm in shapeMatches) {
      final shapeContent = sm.group(1) ?? '';

      // Check if shape is title or subtitle
      final bool isTitleShape = shapeContent.contains('type="title"') ||
          shapeContent.contains('type="ctrTitle"');
      final bool isSubtitleShape = shapeContent.contains('type="subTitle"');

      // Extract text body <p:txBody>
      final txBodyMatch =
          RegExp(r'<p:txBody\b[^>]*>(.*?)</p:txBody>', dotAll: true).firstMatch(shapeContent);
      if (txBodyMatch == null) continue;

      final txBody = txBodyMatch.group(1) ?? '';
      final paragraphs = _parseParagraphs(txBody, isSubtitle: isSubtitleShape);

      if (paragraphs.isEmpty) continue;

      if (isTitleShape && title == null) {
        title = paragraphs.first.text;
        // Remaining paragraphs in title shape can be added to items
        for (int i = 1; i < paragraphs.length; i++) {
          items.add(paragraphs[i]);
        }
      } else {
        items.addAll(paragraphs);
      }
    }

    // Parse tables <a:tbl> inside <p:graphicFrame>
    final tblMatches = RegExp(r'<a:tbl\b[^>]*>(.*?)</a:tbl>', dotAll: true).allMatches(slideXml);
    for (final tm in tblMatches) {
      final tblContent = tm.group(1) ?? '';
      final List<List<String>> tableRows = [];

      final trMatches = RegExp(r'<a:tr\b[^>]*>(.*?)</a:tr>', dotAll: true).allMatches(tblContent);
      for (final tr in trMatches) {
        final trContent = tr.group(1) ?? '';
        final List<String> cellValues = [];

        final tcMatches =
            RegExp(r'<a:tc\b[^>]*>(.*?)</a:tc>', dotAll: true).allMatches(trContent);
        for (final tc in tcMatches) {
          final tcContent = tc.group(1) ?? '';
          final tMatches =
              RegExp(r'<a:t(?:\s+[^>]*)?>(.*?)</a:t>', dotAll: true).allMatches(tcContent);
          final cellText = tMatches.map((m) => _unescapeXml(m.group(1) ?? '')).join(' ');
          cellValues.add(cellText.trim());
        }

        if (cellValues.any((c) => c.isNotEmpty)) {
          tableRows.add(cellValues);
        }
      }

      if (tableRows.isNotEmpty) {
        items.add(SlideTableItem(rows: tableRows));
      }
    }

    // Heuristic: If no title was found, and first item is a single short paragraph, treat as title
    if (title == null && items.isNotEmpty && items.first is SlideParagraphItem) {
      final firstItem = items.first as SlideParagraphItem;
      if (firstItem.text.length <= 80 && items.length > 1) {
        title = firstItem.text;
        items.removeAt(0);
      }
    }

    return SlideData(
      slideIndex: slideNumber,
      title: title,
      items: items,
    );
  }

  List<SlideParagraphItem> _parseParagraphs(String txBody, {bool isSubtitle = false}) {
    final List<SlideParagraphItem> list = [];
    final pMatches = RegExp(r'<a:p\b[^>]*>(.*?)</a:p>', dotAll: true).allMatches(txBody);

    for (final pm in pMatches) {
      final pContent = pm.group(1) ?? '';

      // Paragraph properties
      int level = 0;
      TextAlign alignment = TextAlign.start;
      final pPrMatch = RegExp(r'<a:pPr\b([^>]*)(?:>(.*?)</a:pPr>|/?>)', dotAll: true).firstMatch(pContent);
      if (pPrMatch != null) {
        final attrs = pPrMatch.group(1) ?? '';
        final lvlMatch = RegExp(r'lvl="(\d+)"').firstMatch(attrs);
        if (lvlMatch != null) {
          level = int.tryParse(lvlMatch.group(1)!) ?? 0;
        }
        final algnMatch = RegExp(r'algn="([^"]*)"').firstMatch(attrs);
        if (algnMatch != null) {
          final algn = algnMatch.group(1);
          if (algn == 'ctr') alignment = TextAlign.center;
          if (algn == 'r') alignment = TextAlign.end;
        }
      }

      // Collect text runs
      bool isBold = false;
      bool isItalic = false;
      double? fontSize;

      final sb = StringBuffer();
      // Runs and breaks
      final elementMatches = RegExp(
        r'(?:<a:r\b[^>]*>(.*?)</a:r>|<a:br\b[^>]*/>|<a:fld\b[^>]*>(.*?)</a:fld>)',
        dotAll: true,
      ).allMatches(pContent);

      for (final em in elementMatches) {
        final matchedText = em.group(0) ?? '';
        if (matchedText.startsWith('<a:br')) {
          sb.write('\n');
          continue;
        }

        final inner = em.group(1) ?? em.group(2) ?? '';
        // Check run properties
        final rPrMatch = RegExp(r'<a:rPr\b([^>]*)/?>').firstMatch(inner);
        if (rPrMatch != null) {
          final attrs = rPrMatch.group(1) ?? '';
          if (attrs.contains('b="1"') || attrs.contains("b='1'")) isBold = true;
          if (attrs.contains('i="1"') || attrs.contains("i='1'")) isItalic = true;
          final szMatch = RegExp(r'sz="(\d+)"').firstMatch(attrs);
          if (szMatch != null) {
            final sz = int.tryParse(szMatch.group(1)!);
            if (sz != null) fontSize = sz / 100.0;
          }
        }

        // Extract <a:t>
        final tMatches = RegExp(r'<a:t(?:\s+[^>]*)?>(.*?)</a:t>', dotAll: true).allMatches(inner);
        for (final tm in tMatches) {
          sb.write(_unescapeXml(tm.group(1) ?? ''));
        }
      }

      final fullText = sb.toString().trim();
      if (fullText.isNotEmpty) {
        list.add(
          SlideParagraphItem(
            text: fullText,
            level: level,
            isBold: isBold,
            isItalic: isItalic,
            alignment: alignment,
            fontSize: fontSize,
            isSubtitle: isSubtitle,
          ),
        );
      }
    }

    return list;
  }

  static String _unescapeXml(String input) {
    return input
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final code = int.tryParse(m.group(1)!, radix: 16);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        });
  }

  Future<void> _shareFile() async {
    try {
      await Share.shareXFiles([XFile(widget.filePath)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share file: $e')),
        );
      }
    }
  }

  Future<void> _openExternal() async {
    try {
      final result = await OpenFilex.open(widget.filePath);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file: $e')),
        );
      }
    }
  }

  void _goToSlide(int index) {
    if (index >= 0 && index < _slides.length) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showSlidePicker() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'All Slides (${_slides.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _slides.length,
                    itemBuilder: (context, idx) {
                      final slide = _slides[idx];
                      final isCurrent = idx == _currentSlideIndex;
                      final titleText = slide.title ??
                          (slide.items.isNotEmpty && slide.items.first is SlideParagraphItem
                              ? (slide.items.first as SlideParagraphItem).text
                              : '(No text on slide)');

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          foregroundColor: isCurrent
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          child: Text('${idx + 1}', style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text(
                          titleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: isCurrent
                            ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          _goToSlide(idx);
                        },
                      );
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

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim();
      _matches = [];
      _currentMatchIndex = 0;
    });

    if (_searchQuery.isEmpty) return;

    final queryLower = _searchQuery.toLowerCase();
    final newMatches = <_PptxSearchMatch>[];

    for (int i = 0; i < _slides.length; i++) {
      final slide = _slides[i];
      if (slide.title != null && slide.title!.toLowerCase().contains(queryLower)) {
        newMatches.add(_PptxSearchMatch(slideIndex: i, text: slide.title!));
      }
      for (final item in slide.items) {
        if (item is SlideParagraphItem && item.text.toLowerCase().contains(queryLower)) {
          newMatches.add(_PptxSearchMatch(slideIndex: i, text: item.text));
        } else if (item is SlideTableItem) {
          for (final row in item.rows) {
            for (final cell in row) {
              if (cell.toLowerCase().contains(queryLower)) {
                newMatches.add(_PptxSearchMatch(slideIndex: i, text: cell));
              }
            }
          }
        }
      }
    }

    setState(() {
      _matches = newMatches;
      if (_matches.isNotEmpty) {
        _currentMatchIndex = 0;
        _jumpToMatch(0);
      }
    });
  }

  void _goToNextMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    });
    _jumpToMatch(_currentMatchIndex);
  }

  void _goToPrevMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _matches.length) % _matches.length;
    });
    _jumpToMatch(_currentMatchIndex);
  }

  void _jumpToMatch(int index) {
    if (index < 0 || index >= _matches.length) return;
    final match = _matches[index];
    _goToSlide(match.slideIndex);
  }

  TextSpan _buildHighlightedSpan(String text, TextStyle baseStyle) {
    if (_searchQuery.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final queryLower = _searchQuery.toLowerCase();
    final textLower = text.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = textLower.indexOf(queryLower, start);
      if (index == -1) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        }
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: baseStyle));
      }

      final matchedText = text.substring(index, index + queryLower.length);
      spans.add(TextSpan(
        text: matchedText,
        style: baseStyle.copyWith(
          backgroundColor: Colors.amber.shade300,
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));

      start = index + queryLower.length;
    }

    return TextSpan(children: spans);
  }

  void _showGoToSlideDialog() {
    final controller = TextEditingController(text: '${_currentSlideIndex + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to Slide'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter slide number (1 to ${_slides.length}):'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Slide Number',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
              onSubmitted: (val) {
                final slide = int.tryParse(val);
                if (slide != null && slide >= 1 && slide <= _slides.length) {
                  Navigator.pop(ctx);
                  _goToSlide(slide - 1);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final slide = int.tryParse(controller.text);
              if (slide != null && slide >= 1 && slide <= _slides.length) {
                Navigator.pop(ctx);
                _goToSlide(slide - 1);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please enter a valid slide (1-${_slides.length})'),
                  ),
                );
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.filePath);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _isSearchMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearchMode = false;
                    _searchQuery = '';
                    _matches = [];
                    _searchController.clear();
                  });
                },
              ),
              title: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search in slides...',
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
              ),
              actions: [
                if (_searchQuery.isNotEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        _matches.isEmpty
                            ? '0 found'
                            : '${_currentMatchIndex + 1}/${_matches.length} (Slide ${_matches[_currentMatchIndex].slideIndex + 1})',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: 'Previous match',
                  onPressed: _matches.isNotEmpty ? _goToPrevMatch : null,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Next match',
                  onPressed: _matches.isNotEmpty ? _goToNextMatch : null,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
              ],
            )
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (_slides.isNotEmpty)
                    Text(
                      'Slide ${_currentSlideIndex + 1} of ${_slides.length}',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
              actions: [
                if (_slides.isNotEmpty) ...[
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search slides',
                    onPressed: () {
                      setState(() {
                        _isSearchMode = true;
                      });
                      _searchFocusNode.requestFocus();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.view_carousel_outlined),
                    tooltip: 'Slide list',
                    onPressed: _showSlidePicker,
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: 'Share',
                  onPressed: _shareFile,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (val) {
                    if (val == 'goto') _showGoToSlideDialog();
                    if (val == 'open_external') _openExternal();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'goto',
                      child: Row(
                        children: [
                          Icon(Icons.pin_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('Go to Slide'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'open_external',
                      child: Row(
                        children: [
                          Icon(Icons.open_in_new_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('Open in Office App'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading presentation...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Unable to display presentation',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _loadPresentation,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  FilledButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open Externally'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_slides.isEmpty) {
      return const Center(
        child: Text('No slides in presentation.'),
      );
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _slides.length,
      onPageChanged: (index) {
        setState(() {
          _currentSlideIndex = index;
        });
      },
      itemBuilder: (context, index) {
        return _buildSlideCard(_slides[index]);
      },
    );
  }

  Widget _buildSlideCard(SlideData slide) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        color: theme.colorScheme.surfaceContainerLowest,
        child: Column(
          children: [
            // Slide Header with index badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainer,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Slide ${slide.slideIndex}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Text(
                    '${slide.slideIndex} / ${_slides.length}',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            // Slide Content
            Expanded(
              child: slide.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.slideshow_outlined,
                            size: 64,
                            color: theme.colorScheme.outline.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Visual Slide',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'This slide contains images, shapes, or media elements without readable text.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Scrollbar(
                      thumbVisibility: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Slide Title
                            if (slide.title != null && slide.title!.isNotEmpty) ...[
                              SelectableText.rich(
                                _buildHighlightedSpan(
                                  slide.title!,
                                  theme.textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ) ??
                                      const TextStyle(),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 48,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Slide Items
                            ...slide.items.map((item) {
                              if (item is SlideParagraphItem) {
                                return _buildParagraphWidget(item, theme);
                              } else if (item is SlideTableItem) {
                                return _buildTableWidget(item, theme);
                              }
                              return const SizedBox.shrink();
                            }),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParagraphWidget(SlideParagraphItem item, ThemeData theme) {
    final double leftIndent = item.level * 16.0;

    return Padding(
      padding: EdgeInsets.only(left: leftIndent, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bullet indicator
          if (item.level > 0)
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 8),
              child: Container(
                width: item.level == 1 ? 5 : 4,
                height: item.level == 1 ? 5 : 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.level == 1 ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
              ),
            )
          else if (!item.isSubtitle)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),

          Expanded(
            child: SelectableText.rich(
              _buildHighlightedSpan(
                item.text,
                TextStyle(
                  fontSize: item.fontSize != null
                      ? item.fontSize!.clamp(13.0, 22.0)
                      : (item.isSubtitle ? 15 : 14),
                  fontWeight: item.isBold
                      ? FontWeight.bold
                      : (item.isSubtitle ? FontWeight.w500 : FontWeight.normal),
                  fontStyle: item.isItalic ? FontStyle.italic : FontStyle.normal,
                  color: item.isSubtitle
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
              textAlign: item.alignment,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableWidget(SlideTableItem table, ThemeData theme) {
    if (table.rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(
              horizontalInside: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
              verticalInside: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
            ),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: table.rows.asMap().entries.map((entry) {
              final rowIdx = entry.key;
              final rowCells = entry.value;
              final isHeader = rowIdx == 0;

              return TableRow(
                decoration: BoxDecoration(
                  color: isHeader
                      ? theme.colorScheme.surfaceContainerHighest
                      : (rowIdx % 2 == 0
                          ? theme.colorScheme.surface
                          : theme.colorScheme.surfaceContainerLowest),
                ),
                children: rowCells.map((cell) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: SelectableText.rich(
                      _buildHighlightedSpan(
                        cell,
                        TextStyle(
                          fontSize: 12,
                          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget? _buildBottomNav() {
    if (_slides.isEmpty) return null;

    final theme = Theme.of(context);
    final canGoBack = _currentSlideIndex > 0;
    final canGoForward = _currentSlideIndex < _slides.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                tooltip: 'Previous slide',
                onPressed: canGoBack ? () => _goToSlide(_currentSlideIndex - 1) : null,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _currentSlideIndex.toDouble(),
                      min: 0,
                      max: (_slides.length - 1).toDouble().clamp(0.0, double.infinity),
                      divisions: _slides.length > 1 ? _slides.length - 1 : 1,
                      label: 'Slide ${_currentSlideIndex + 1}',
                      onChanged: (val) {
                        _goToSlide(val.round());
                      },
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                tooltip: 'Next slide',
                onPressed: canGoForward ? () => _goToSlide(_currentSlideIndex + 1) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PptxSearchMatch {
  final int slideIndex;
  final String text;

  const _PptxSearchMatch({
    required this.slideIndex,
    required this.text,
  });
}
