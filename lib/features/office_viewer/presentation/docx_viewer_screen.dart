import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// Represents a formatted text run inside a Word paragraph.
class DocxRun {
  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrike;

  const DocxRun({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrike = false,
  });
}

/// Represents a single paragraph in a Word document.
class DocxParagraph {
  final List<DocxRun> runs;
  final bool isHeading;
  final int headingLevel;
  final TextAlign alignment;
  final bool isBullet;
  final bool isPageBreakAfter;

  const DocxParagraph({
    required this.runs,
    this.isHeading = false,
    this.headingLevel = 1,
    this.alignment = TextAlign.start,
    this.isBullet = false,
    this.isPageBreakAfter = false,
  });

  String get fullText => runs.map((r) => r.text).join();
  bool get isEmpty => fullText.trim().isEmpty;
}

/// Represents a table in a Word document.
class DocxTable {
  final List<List<List<DocxParagraph>>> rows;

  const DocxTable({required this.rows});

  bool get isEmpty => rows.isEmpty;
}

/// Base class for elements that can appear on a Word page.
sealed class DocxElement {}

class DocxParagraphElement extends DocxElement {
  final DocxParagraph paragraph;
  DocxParagraphElement(this.paragraph);
}

class DocxTableElement extends DocxElement {
  final DocxTable table;
  DocxTableElement(this.table);
}

/// Represents an individual A4-styled page in the document.
class DocxPage {
  final int pageNumber;
  final List<DocxElement> elements;

  const DocxPage({
    required this.pageNumber,
    required this.elements,
  });

  bool get isEmpty => elements.isEmpty;
}

class DocxViewerScreen extends StatefulWidget {
  final String filePath;

  const DocxViewerScreen({super.key, required this.filePath});

  @override
  State<DocxViewerScreen> createState() => _DocxViewerScreenState();
}

class _DocxViewerScreenState extends State<DocxViewerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<DocxPage> _pages = [];
  double _baseFontSize = 15.0;

  // View mode: continuous vertical scroll vs horizontal page-by-page flip
  bool _isPageFlipMode = false;
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();
  int _currentPageIndex = 0;

  // Search in document
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<_DocxSearchMatch> _matches = [];
  int _currentMatchIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDocx();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ==========================================
  // DOCX Parsing & Pagination
  // ==========================================

  Future<void> _loadDocx() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _pages = [];
    });

    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() {
          _errorMessage = 'File not found: ${widget.filePath}';
          _isLoading = false;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      if (bytes.length < 4 ||
          bytes[0] != 0x50 ||
          bytes[1] != 0x4B ||
          bytes[2] != 0x03 ||
          bytes[3] != 0x04) {
        setState(() {
          _errorMessage =
              'This is not a valid modern Word (.docx) document. Legacy binary .doc files must be opened in an external Office app.';
          _isLoading = false;
        });
        return;
      }

      final archive = ZipDecoder().decodeBytes(bytes);
      final documentFile = archive.findFile('word/document.xml');

      if (documentFile == null) {
        setState(() {
          _errorMessage =
              'Invalid DOCX structure: word/document.xml is missing from the package.';
          _isLoading = false;
        });
        return;
      }

      final xmlString = String.fromCharCodes(documentFile.content as List<int>);
      final pages = _parseAndPaginateDocx(xmlString);

      setState(() {
        _pages = pages;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error reading Word document: $e';
        _isLoading = false;
      });
    }
  }

  /// Parses OpenXML and groups elements into clean Word pages.
  List<DocxPage> _parseAndPaginateDocx(String xml) {
    final rawElements = <DocxElement>[];

    // Find all <w:p> paragraphs and <w:tbl> tables in document body
    // Using a regex scanner that steps through the body
    final bodyMatch = RegExp(r'<w:body>(.*?)<\/w:body>', dotAll: true).firstMatch(xml);
    final bodyContent = bodyMatch != null ? (bodyMatch.group(1) ?? xml) : xml;

    // Tokenize body by top-level <w:p> and <w:tbl>
    final elementRegex = RegExp(r'<(w:p|w:tbl)(?:[\s>].*?)<\/\1>', dotAll: true);

    for (final match in elementRegex.allMatches(bodyContent)) {
      final tagXml = match.group(0) ?? '';
      final tagName = match.group(1) ?? '';

      if (tagName == 'w:p') {
        final paragraph = _parseParagraph(tagXml);
        if (paragraph != null) {
          rawElements.add(DocxParagraphElement(paragraph));
        }
      } else if (tagName == 'w:tbl') {
        final table = _parseTable(tagXml);
        if (table != null && !table.isEmpty) {
          rawElements.add(DocxTableElement(table));
        }
      }
    }

    if (rawElements.isEmpty) {
      return [const DocxPage(pageNumber: 1, elements: [])];
    }

    // Now organize elements into pages
    final pages = <DocxPage>[];
    var currentPageElements = <DocxElement>[];
    int currentCharsOnPage = 0;
    const int maxCharsPerPage = 1750; // Standard single-spaced A4 page threshold

    for (final element in rawElements) {
      bool isExplicitPageBreak = false;
      int elementCharCount = 0;

      if (element is DocxParagraphElement) {
        elementCharCount = element.paragraph.fullText.length;
        isExplicitPageBreak = element.paragraph.isPageBreakAfter;
      } else if (element is DocxTableElement) {
        // Approximate character count for table
        elementCharCount = 400;
      }

      // If current page is getting full or explicit break encountered
      if (currentPageElements.isNotEmpty &&
          (isExplicitPageBreak ||
              (currentCharsOnPage + elementCharCount > maxCharsPerPage &&
                  currentCharsOnPage > 600))) {
        pages.add(DocxPage(
          pageNumber: pages.length + 1,
          elements: List.from(currentPageElements),
        ));
        currentPageElements = <DocxElement>[];
        currentCharsOnPage = 0;
      }

      currentPageElements.add(element);
      currentCharsOnPage += elementCharCount;

      if (isExplicitPageBreak && currentPageElements.isNotEmpty) {
        pages.add(DocxPage(
          pageNumber: pages.length + 1,
          elements: List.from(currentPageElements),
        ));
        currentPageElements = <DocxElement>[];
        currentCharsOnPage = 0;
      }
    }

    if (currentPageElements.isNotEmpty) {
      pages.add(DocxPage(
        pageNumber: pages.length + 1,
        elements: currentPageElements,
      ));
    }

    return pages.isEmpty ? [const DocxPage(pageNumber: 1, elements: [])] : pages;
  }

  /// Parses a single `<w:p>` paragraph with accurate run-level styling and clean text extraction.
  DocxParagraph? _parseParagraph(String pXml) {
    // 1. Check for explicit page break in paragraph or run
    final hasPageBreak = pXml.contains('w:type="page"') ||
        pXml.contains('<w:lastRenderedPageBreak/>') ||
        pXml.contains('<w:pageBreakBefore/>');

    // 2. Paragraph style (Headings, Title, etc.)
    bool isHeading = false;
    int headingLevel = 1;
    final pStyleMatch =
        RegExp(r'<w:pStyle\s+[^>]*w:val="([^"]+)"', caseSensitive: false).firstMatch(pXml);
    if (pStyleMatch != null) {
      final styleVal = (pStyleMatch.group(1) ?? '').toLowerCase();
      if (styleVal.contains('heading1') || styleVal == 'title') {
        isHeading = true;
        headingLevel = 1;
      } else if (styleVal.contains('heading2') || styleVal == 'subtitle') {
        isHeading = true;
        headingLevel = 2;
      } else if (styleVal.contains('heading3')) {
        isHeading = true;
        headingLevel = 3;
      } else if (styleVal.contains('heading')) {
        isHeading = true;
        headingLevel = 4;
      }
    }

    // 3. Paragraph alignment (<w:jc w:val="center|right|both"/>)
    TextAlign alignment = TextAlign.start;
    final jcMatch =
        RegExp(r'<w:jc\s+[^>]*w:val="([^"]+)"', caseSensitive: false).firstMatch(pXml);
    if (jcMatch != null) {
      final val = (jcMatch.group(1) ?? '').toLowerCase();
      if (val == 'center') {
        alignment = TextAlign.center;
      } else if (val == 'right') {
        alignment = TextAlign.right;
      } else if (val == 'both' || val == 'justify') {
        alignment = TextAlign.justify;
      }
    }

    // 4. Bullet / Numbered list check (<w:numPr>)
    final isBullet = pXml.contains('<w:numPr>') || pXml.contains('<w:numPr/>');

    // 5. Extract runs (<w:r>)
    final runs = <DocxRun>[];
    final runRegex = RegExp(r'<w:r(?:[\s>].*?)<\/w:r>', dotAll: true);

    // Text tag regex that matches opening tag with ANY attributes safely without leakage
    final textRegex = RegExp(r'<w:t(?:\s+[^>]*)?>(.*?)<\/w:t>', dotAll: true);
    final boldRegex = RegExp(r'<w:b\s*\/>|<w:b\s+[^>]*w:val="(?:true|1)"', caseSensitive: false);
    final italicRegex = RegExp(r'<w:i\s*\/>|<w:i\s+[^>]*w:val="(?:true|1)"', caseSensitive: false);
    final underlineRegex = RegExp(r'<w:u\s+[^>]*w:val="(?!none)[^"]+"|<w:u\s*\/?>', caseSensitive: false);
    final strikeRegex = RegExp(r'<w:strike\s*\/>|<w:strike\s+[^>]*w:val="(?:true|1)"', caseSensitive: false);

    for (final rMatch in runRegex.allMatches(pXml)) {
      final rXml = rMatch.group(0) ?? '';

      final isBold = boldRegex.hasMatch(rXml);
      final isItalic = italicRegex.hasMatch(rXml);
      final isUnderline = underlineRegex.hasMatch(rXml);
      final isStrike = strikeRegex.hasMatch(rXml);

      // Collect all text in this run
      final runTextBuffer = StringBuffer();
      for (final tMatch in textRegex.allMatches(rXml)) {
        final rawText = tMatch.group(1) ?? '';
        runTextBuffer.write(_cleanXmlText(rawText));
      }

      final runText = runTextBuffer.toString();
      if (runText.isNotEmpty) {
        runs.add(DocxRun(
          text: runText,
          isBold: isBold,
          isItalic: isItalic,
          isUnderline: isUnderline,
          isStrike: isStrike,
        ));
      }
    }

    // Fallback: If no <w:r> found, extract any raw <w:t> tags directly
    if (runs.isEmpty) {
      final buffer = StringBuffer();
      for (final tMatch in textRegex.allMatches(pXml)) {
        final rawText = tMatch.group(1) ?? '';
        buffer.write(_cleanXmlText(rawText));
      }
      final fallbackText = buffer.toString();
      if (fallbackText.trim().isNotEmpty) {
        runs.add(DocxRun(text: fallbackText));
      }
    }

    // If still completely empty and not a page break, return null
    if (runs.isEmpty && !hasPageBreak) {
      return null;
    }

    return DocxParagraph(
      runs: runs,
      isHeading: isHeading,
      headingLevel: headingLevel,
      alignment: alignment,
      isBullet: isBullet,
      isPageBreakAfter: hasPageBreak,
    );
  }

  /// Parses a Word table (`<w:tbl>`).
  DocxTable? _parseTable(String tblXml) {
    final rows = <List<List<DocxParagraph>>>[];
    final trRegex = RegExp(r'<w:tr(?:[\s>].*?)<\/w:tr>', dotAll: true);
    final tcRegex = RegExp(r'<w:tc(?:[\s>].*?)<\/w:tc>', dotAll: true);
    final pRegex = RegExp(r'<w:p(?:[\s>].*?)<\/w:p>', dotAll: true);

    for (final trMatch in trRegex.allMatches(tblXml)) {
      final trXml = trMatch.group(0) ?? '';
      final rowCells = <List<DocxParagraph>>[];

      for (final tcMatch in tcRegex.allMatches(trXml)) {
        final tcXml = tcMatch.group(0) ?? '';
        final cellParagraphs = <DocxParagraph>[];

        for (final pMatch in pRegex.allMatches(tcXml)) {
          final pXml = pMatch.group(0) ?? '';
          final p = _parseParagraph(pXml);
          if (p != null) {
            cellParagraphs.add(p);
          }
        }

        rowCells.add(cellParagraphs);
      }

      if (rowCells.isNotEmpty) {
        rows.add(rowCells);
      }
    }

    return rows.isNotEmpty ? DocxTable(rows: rows) : null;
  }

  /// Completely unescapes XML entities and strips any leaked XML tags.
  static String _cleanXmlText(String raw) {
    if (raw.isEmpty) return '';

    // Strip any leaked XML tags like <w:...> or <... > that might get through
    var text = raw.replaceAll(RegExp(r'<[^>]*>'), '');

    // Strip any raw xml:space="preserve" artifacts if ever present
    text = text.replaceAll(RegExp(r'xml:space="preserve">?'), '');

    // Unescape XML entities
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#xA;', '\n')
        .replaceAll('&#xD;', '')
        .replaceAll('&nbsp;', ' ');

    return text;
  }

  // ==========================================
  // In-Document Search
  // ==========================================

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim();
      _matches = [];
      _currentMatchIndex = 0;
    });

    if (_searchQuery.isEmpty) return;

    final queryLower = _searchQuery.toLowerCase();
    final newMatches = <_DocxSearchMatch>[];

    for (int pIndex = 0; pIndex < _pages.length; pIndex++) {
      final page = _pages[pIndex];
      for (int eIndex = 0; eIndex < page.elements.length; eIndex++) {
        final element = page.elements[eIndex];
        if (element is DocxParagraphElement) {
          final textLower = element.paragraph.fullText.toLowerCase();
          int startIndex = 0;
          while (true) {
            final matchPos = textLower.indexOf(queryLower, startIndex);
            if (matchPos == -1) break;
            newMatches.add(_DocxSearchMatch(
              pageIndex: pIndex,
              elementIndex: eIndex,
              characterOffset: matchPos,
            ));
            startIndex = matchPos + queryLower.length;
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

  void _jumpToMatch(int matchIndex) {
    if (matchIndex < 0 || matchIndex >= _matches.length) return;
    final match = _matches[matchIndex];

    if (_isPageFlipMode) {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          match.pageIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else {
      // In scroll mode, scroll to the page estimate
      if (_scrollController.hasClients) {
        final totalPages = _pages.length;
        if (totalPages > 0) {
          final targetOffset =
              (match.pageIndex / totalPages) * _scrollController.position.maxScrollExtent;
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    }
  }

  void _showGoToPageDialog() {
    final controller = TextEditingController(text: '${_currentPageIndex + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to Page'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter page number (1 to ${_pages.length}):'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Page Number',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
              onSubmitted: (val) {
                final page = int.tryParse(val);
                if (page != null && page >= 1 && page <= _pages.length) {
                  Navigator.pop(ctx);
                  _navigateToPage(page - 1);
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
              final page = int.tryParse(controller.text);
              if (page != null && page >= 1 && page <= _pages.length) {
                Navigator.pop(ctx);
                _navigateToPage(page - 1);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please enter a valid page (1-${_pages.length})'),
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

  void _navigateToPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() {
      _currentPageIndex = index;
    });

    if (_isPageFlipMode) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
    } else {
      if (_scrollController.hasClients && _pages.isNotEmpty) {
        final targetOffset =
            (index / _pages.length) * _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _openInExternalApp() {
    OpenFilex.open(widget.filePath).then((res) {
      if (!mounted) return;
      if (res.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open externally: ${res.message}')),
        );
      }
    });
  }

  // ==========================================
  // UI Builders
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = p.basename(widget.filePath);

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : const Color(0xFFEFEFEF),
      appBar: _isSearchMode ? _buildSearchAppBar(theme) : _buildStandardAppBar(theme, fileName),
      body: _buildBody(theme),
      bottomNavigationBar: _buildBottomBar(theme),
    );
  }

  PreferredSizeWidget _buildStandardAppBar(ThemeData theme, String fileName) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fileName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          if (_pages.isNotEmpty)
            Text(
              'Page ${_currentPageIndex + 1} of ${_pages.length}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search text in document',
          onPressed: () {
            setState(() {
              _isSearchMode = true;
            });
            _searchFocusNode.requestFocus();
          },
        ),
        IconButton(
          icon: Icon(_isPageFlipMode ? Icons.view_stream_outlined : Icons.menu_book_outlined),
          tooltip: _isPageFlipMode ? 'Continuous page scroll' : 'Page flip mode',
          onPressed: () {
            setState(() {
              _isPageFlipMode = !_isPageFlipMode;
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.text_decrease),
          tooltip: 'Smaller text',
          onPressed: () {
            if (_baseFontSize > 11) {
              setState(() => _baseFontSize -= 1.5);
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.text_increase),
          tooltip: 'Larger text',
          onPressed: () {
            if (_baseFontSize < 28) {
              setState(() => _baseFontSize += 1.5);
            }
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (val) {
            switch (val) {
              case 'goto':
                _showGoToPageDialog();
                break;
              case 'open_external':
                _openInExternalApp();
                break;
              case 'share':
                Share.shareXFiles([XFile(widget.filePath)]);
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
              value: 'open_external',
              child: Row(
                children: [
                  Icon(Icons.open_in_new, size: 20),
                  SizedBox(width: 12),
                  Text('Open in Office App'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 12),
                  Text('Share Document'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSearchAppBar(ThemeData theme) {
    return AppBar(
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
          hintText: 'Search within Word document...',
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
                    : '${_currentMatchIndex + 1}/${_matches.length}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Rendering Word document...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 54, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openInExternalApp,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in external app'),
              ),
            ],
          ),
        ),
      );
    }

    if (_pages.isEmpty || (_pages.length == 1 && _pages.first.isEmpty)) {
      return const Center(
        child: Text('Document is empty or contains no readable text.'),
      );
    }

    if (_isPageFlipMode) {
      return PageView.builder(
        controller: _pageController,
        itemCount: _pages.length,
        onPageChanged: (idx) {
          setState(() {
            _currentPageIndex = idx;
          });
        },
        itemBuilder: (context, index) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: _buildA4PageCard(theme, _pages[index]),
          );
        },
      );
    }

    // Continuous vertical scroll of A4 sheets
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _pages.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: _buildA4PageCard(theme, _pages[index]),
        );
      },
    );
  }

  /// Renders a single Word page styled like an authentic A4 paper sheet.
  Widget _buildA4PageCard(ThemeData theme, DocxPage page) {
    final isDark = theme.brightness == Brightness.dark;

    final paperColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final paperBorderColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      decoration: BoxDecoration(
        color: paperColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: paperBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Page Header
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  p.basenameWithoutExtension(widget.filePath),
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Page ${page.pageNumber}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 24, endIndent: 24),

          // Page Content
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: page.elements.map((elem) {
                if (elem is DocxParagraphElement) {
                  return _buildParagraphWidget(theme, elem.paragraph);
                } else if (elem is DocxTableElement) {
                  return _buildTableWidget(theme, elem.table);
                }
                return const SizedBox.shrink();
              }).toList(),
            ),
          ),

          // Page Footer Divider & Number
          const Divider(height: 1, indent: 24, endIndent: 24),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              '— Page ${page.pageNumber} of ${_pages.length} —',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParagraphWidget(ThemeData theme, DocxParagraph paragraph) {
    if (paragraph.isEmpty) {
      return const SizedBox(height: 8);
    }

    final isDark = theme.brightness == Brightness.dark;

    // Heading styles
    if (paragraph.isHeading) {
      final double headingSize = switch (paragraph.headingLevel) {
        1 => _baseFontSize * 1.5,
        2 => _baseFontSize * 1.3,
        3 => _baseFontSize * 1.15,
        _ => _baseFontSize * 1.05,
      };

      return Padding(
        padding: const EdgeInsets.only(top: 18.0, bottom: 8.0),
        child: SelectableText.rich(
          TextSpan(
            children: paragraph.runs
                .map((r) => _buildHighlightedSpan(
                      r.text,
                      TextStyle(
                        fontSize: headingSize,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                        height: 1.3,
                      ),
                    ))
                .toList(),
          ),
          textAlign: paragraph.alignment,
        ),
      );
    }

    // Bullet / list item
    Widget content;
    final textSpans = paragraph.runs.map((r) {
      final style = TextStyle(
        fontSize: _baseFontSize,
        height: 1.5,
        fontWeight: r.isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: r.isItalic ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (r.isUnderline) TextDecoration.underline,
          if (r.isStrike) TextDecoration.lineThrough,
        ]),
        color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF222222),
      );

      return _buildHighlightedSpan(r.text, style);
    }).toList();

    if (paragraph.isBullet) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Icon(
              Icons.circle,
              size: 6,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          Expanded(
            child: SelectableText.rich(
              TextSpan(children: textSpans),
              textAlign: paragraph.alignment,
            ),
          ),
        ],
      );
    } else {
      content = SelectableText.rich(
        TextSpan(children: textSpans),
        textAlign: paragraph.alignment,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: content,
    );
  }

  /// Builds TextSpans with amber search highlights if a search query is active.
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

  /// Builds a rendered table widget for Word tables.
  Widget _buildTableWidget(ThemeData theme, DocxTable table) {
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white24 : Colors.black26;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: borderColor, width: 1),
          children: table.rows.asMap().entries.map((rowEntry) {
            final rowIndex = rowEntry.key;
            final cells = rowEntry.value;
            final isHeader = rowIndex == 0;

            return TableRow(
              decoration: BoxDecoration(
                color: isHeader
                    ? (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))
                    : null,
              ),
              children: cells.map((cellParagraphs) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: cellParagraphs
                        .map((p) => _buildParagraphWidget(theme, p))
                        .toList(),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget? _buildBottomBar(ThemeData theme) {
    if (_pages.isEmpty) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _showGoToPageDialog,
              icon: const Icon(Icons.pin_outlined, size: 18),
              label: Text('Page ${_currentPageIndex + 1} of ${_pages.length}'),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous page',
                  onPressed: _currentPageIndex > 0
                      ? () => _navigateToPage(_currentPageIndex - 1)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next page',
                  onPressed: _currentPageIndex < _pages.length - 1
                      ? () => _navigateToPage(_currentPageIndex + 1)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DocxSearchMatch {
  final int pageIndex;
  final int elementIndex;
  final int characterOffset;

  const _DocxSearchMatch({
    required this.pageIndex,
    required this.elementIndex,
    required this.characterOffset,
  });
}
