import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class ExcelSheetData {
  final String name;
  final List<List<String>> rows;
  final int totalRowsCount;
  final int totalColsCount;
  final int maxColumns;

  const ExcelSheetData({
    required this.name,
    required this.rows,
    required this.totalRowsCount,
    required this.totalColsCount,
    required this.maxColumns,
  });

  bool get isEmpty =>
      rows.isEmpty || (rows.length == 1 && rows.first.every((c) => c.isEmpty));
}

class XlsxViewerScreen extends StatefulWidget {
  final String filePath;

  const XlsxViewerScreen({super.key, required this.filePath});

  @override
  State<XlsxViewerScreen> createState() => _XlsxViewerScreenState();
}

class _XlsxViewerScreenState extends State<XlsxViewerScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<ExcelSheetData> _sheets = [];
  int _selectedSheetIndex = 0;

  // Selected cell coordinates (rowIndex, colIndex)
  int? _selectedRow;
  int? _selectedCol;

  // Search in current sheet
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWorkbook();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkbook() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _sheets = [];
      _selectedSheetIndex = 0;
      _selectedRow = null;
      _selectedCol = null;
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

      // Check for ZIP magic numbers (PK..)
      if (bytes.length < 4 ||
          bytes[0] != 0x50 ||
          bytes[1] != 0x4B ||
          bytes[2] != 0x03 ||
          bytes[3] != 0x04) {
        if (ext == '.xls') {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Legacy binary Excel (.xls) format is not supported in the built-in viewer. Please convert to .xlsx or open in an external office app.';
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
              'Could not unpack spreadsheet archive. The file might be corrupted or in an unsupported format ($e).';
        });
        return;
      }

      // 1. Parse shared strings table (xl/sharedStrings.xml)
      final List<String> sharedStrings = _extractSharedStrings(archive);

      // 2. Parse workbook to find sheets (xl/workbook.xml & xl/_rels/workbook.xml.rels)
      final sheetsInfo = _extractSheetsInfo(archive);

      if (sheetsInfo.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No sheets found in this Excel workbook.';
        });
        return;
      }

      // 3. Parse each sheet
      final List<ExcelSheetData> parsedSheets = [];
      for (final sInfo in sheetsInfo) {
        final sheetXml = _findArchiveFileContent(archive, sInfo.targetPath);
        if (sheetXml != null) {
          final sheetData = _parseSheetXml(sheetXml, sharedStrings, sInfo.name);
          parsedSheets.add(sheetData);
        } else {
          parsedSheets.add(
            ExcelSheetData(
              name: sInfo.name,
              rows: [],
              totalRowsCount: 0,
              totalColsCount: 0,
              maxColumns: 0,
            ),
          );
        }
      }

      setState(() {
        _sheets = parsedSheets;
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrint('Error loading XLSX: $e\n$stack');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to read spreadsheet: $e';
      });
    }
  }

  List<String> _extractSharedStrings(Archive archive) {
    final List<String> sharedStrings = [];
    final xmlContent =
        _findArchiveFileContent(archive, 'xl/sharedStrings.xml') ??
        _findArchiveFileContent(archive, 'xl/SharedStrings.xml');

    if (xmlContent == null) return sharedStrings;

    // Matches each <si>...</si> item
    final siMatches = RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true).allMatches(xmlContent);
    for (final siMatch in siMatches) {
      String siBody = siMatch.group(1) ?? '';
      // Remove phonetic runs <rPh>...</rPh>
      siBody = siBody.replaceAll(RegExp(r'<rPh\b[^>]*>.*?</rPh>', dotAll: true), '');

      // Match all text elements <t>...</t> inside the si element
      final tMatches = RegExp(r'<t(?:\s+[^>]*)?>(.*?)</t>', dotAll: true).allMatches(siBody);
      final sb = StringBuffer();
      for (final tm in tMatches) {
        sb.write(_unescapeXml(tm.group(1) ?? ''));
      }
      sharedStrings.add(sb.toString());
    }

    return sharedStrings;
  }

  List<_SheetEntry> _extractSheetsInfo(Archive archive) {
    final List<_SheetEntry> result = [];

    // Map relationships from xl/_rels/workbook.xml.rels
    final Map<String, String> rels = {};
    final relsXml =
        _findArchiveFileContent(archive, 'xl/_rels/workbook.xml.rels') ??
        _findArchiveFileContent(archive, 'xl/_rels/Workbook.xml.rels');

    if (relsXml != null) {
      final relMatches = RegExp(r'<Relationship\b([^>]*)/?>').allMatches(relsXml);
      for (final rm in relMatches) {
        final attrs = rm.group(1) ?? '';
        final idMatch = RegExp(r'Id="([^"]*)"').firstMatch(attrs);
        final targetMatch = RegExp(r'Target="([^"]*)"').firstMatch(attrs);
        if (idMatch != null && targetMatch != null) {
          String target = targetMatch.group(1)!.replaceAll('\\', '/');
          if (target.startsWith('/')) target = target.substring(1);
          if (!target.toLowerCase().startsWith('xl/')) {
            target = 'xl/$target';
          }
          rels[idMatch.group(1)!] = target;
        }
      }
    }

    // Parse xl/workbook.xml
    final workbookXml =
        _findArchiveFileContent(archive, 'xl/workbook.xml') ??
        _findArchiveFileContent(archive, 'xl/Workbook.xml');

    if (workbookXml != null) {
      final sheetMatches = RegExp(r'<sheet\b([^>]*)/?>').allMatches(workbookXml);
      int fallbackIndex = 1;
      for (final sm in sheetMatches) {
        final attrs = sm.group(1) ?? '';
        final nameMatch = RegExp(r'name="([^"]*)"').firstMatch(attrs);
        final rIdMatch = RegExp(r'r:id="([^"]*)"').firstMatch(attrs);

        final name = _unescapeXml(nameMatch?.group(1) ?? 'Sheet$fallbackIndex');
        final rId = rIdMatch?.group(1);

        String targetPath = '';
        if (rId != null && rels.containsKey(rId)) {
          targetPath = rels[rId]!;
        } else {
          targetPath = 'xl/worksheets/sheet$fallbackIndex.xml';
        }

        result.add(_SheetEntry(name: name, targetPath: targetPath));
        fallbackIndex++;
      }
    }

    // Fallback if no sheets were found in workbook.xml
    if (result.isEmpty) {
      int idx = 1;
      for (final entry in archive) {
        final norm = entry.name.replaceAll('\\', '/');
        if (norm.toLowerCase().startsWith('xl/worksheets/sheet') &&
            norm.toLowerCase().endsWith('.xml')) {
          result.add(_SheetEntry(name: 'Sheet$idx', targetPath: norm));
          idx++;
        }
      }
    }

    return result;
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

  ExcelSheetData _parseSheetXml(
    String sheetXml,
    List<String> sharedStrings,
    String sheetName,
  ) {
    final Map<int, Map<int, String>> rowMap = {};
    int maxRow = 0;
    int maxCol = 0;

    final rowMatches = RegExp(r'<row\b([^>]*)>(.*?)</row>', dotAll: true).allMatches(sheetXml);

    int fallbackRowIdx = 0;
    for (final rowMatch in rowMatches) {
      final rowAttrs = rowMatch.group(1) ?? '';
      final rowBody = rowMatch.group(2) ?? '';

      final rMatch = RegExp(r'r="(\d+)"').firstMatch(rowAttrs);
      final int rowIdx = rMatch != null ? int.parse(rMatch.group(1)!) - 1 : fallbackRowIdx;
      fallbackRowIdx = rowIdx + 1;

      if (rowIdx > maxRow) maxRow = rowIdx;

      final cellMatches =
          RegExp(r'<c\b([^>]*?)(?:>(.*?)</c>|/>)', dotAll: true).allMatches(rowBody);

      int fallbackColIdx = 0;
      for (final cellMatch in cellMatches) {
        final cellAttrs = cellMatch.group(1) ?? '';
        final cellBody = cellMatch.group(2) ?? '';

        final refMatch = RegExp(r'r="([A-Za-z]+)(\d+)"').firstMatch(cellAttrs);
        int colIdx = fallbackColIdx;
        if (refMatch != null) {
          colIdx = _colLettersToIndex(refMatch.group(1)!.toUpperCase());
        }
        fallbackColIdx = colIdx + 1;

        if (colIdx > maxCol) maxCol = colIdx;

        final typeMatch = RegExp(r't="([^"]*)"').firstMatch(cellAttrs);
        final cellType = typeMatch?.group(1);

        String cellValue = '';
        if (cellType == 'inlineStr') {
          final tMatches = RegExp(r'<t(?:\s+[^>]*)?>(.*?)</t>', dotAll: true).allMatches(cellBody);
          final sb = StringBuffer();
          for (final tm in tMatches) {
            sb.write(_unescapeXml(tm.group(1) ?? ''));
          }
          cellValue = sb.toString();
        } else {
          final vMatch = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(cellBody);
          if (vMatch != null) {
            final rawVal = vMatch.group(1) ?? '';
            if (cellType == 's') {
              final idx = int.tryParse(rawVal);
              if (idx != null && idx >= 0 && idx < sharedStrings.length) {
                cellValue = sharedStrings[idx];
              } else {
                cellValue = rawVal;
              }
            } else if (cellType == 'b') {
              cellValue = (rawVal == '1' || rawVal.toLowerCase() == 'true') ? 'TRUE' : 'FALSE';
            } else {
              cellValue = _unescapeXml(rawVal);
            }
          }
        }

        if (cellValue.isNotEmpty) {
          rowMap.putIfAbsent(rowIdx, () => {})[colIdx] = cellValue;
        }
      }
    }

    // Safety limits for responsive UI performance
    const int maxDisplayRows = 3000;
    const int maxDisplayCols = 60;

    final int effectiveRows = (maxRow + 1).clamp(0, maxDisplayRows);
    final int effectiveCols = (maxCol + 1).clamp(1, maxDisplayCols);

    final List<List<String>> rows = [];
    for (int r = 0; r < effectiveRows; r++) {
      final List<String> rowList = List.filled(effectiveCols, '');
      final cols = rowMap[r];
      if (cols != null) {
        for (final entry in cols.entries) {
          if (entry.key < effectiveCols) {
            rowList[entry.key] = entry.value;
          }
        }
      }
      rows.add(rowList);
    }

    return ExcelSheetData(
      name: sheetName,
      rows: rows,
      totalRowsCount: maxRow + 1,
      totalColsCount: maxCol + 1,
      maxColumns: effectiveCols,
    );
  }

  static int _colLettersToIndex(String letters) {
    int result = 0;
    for (int i = 0; i < letters.length; i++) {
      result = result * 26 + (letters.codeUnitAt(i) - 64);
    }
    return result - 1;
  }

  static String _indexToColLetters(int colIndex) {
    String result = '';
    int n = colIndex + 1;
    while (n > 0) {
      final rem = (n - 1) % 26;
      result = String.fromCharCode(65 + rem) + result;
      n = (n - 1) ~/ 26;
    }
    return result;
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

  void _showCellDetails(int rowIdx, int colIdx, String value) {
    final cellRef = '${_indexToColLetters(colIdx)}${rowIdx + 1}';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Cell $cellRef',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: 'Copy value',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: value));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied "$value" to clipboard')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Content:',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    value.isEmpty ? '(Empty cell)' : value,
                    style: TextStyle(
                      fontStyle: value.isEmpty ? FontStyle.italic : FontStyle.normal,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.filePath);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search sheet...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                style: const TextStyle(fontSize: 16),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim().toLowerCase();
                  });
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (_sheets.isNotEmpty && _selectedSheetIndex < _sheets.length)
                    Text(
                      '${_sheets[_selectedSheetIndex].name} • ${_sheets[_selectedSheetIndex].totalRowsCount} rows × ${_sheets[_selectedSheetIndex].totalColsCount} cols',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? 'Close search' : 'Search sheet',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: _shareFile,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new_outlined),
            tooltip: 'Open in external app',
            onPressed: _openExternal,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
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
            Text('Parsing spreadsheet...'),
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
                'Unable to display spreadsheet',
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
                    onPressed: _loadWorkbook,
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

    if (_sheets.isEmpty) {
      return const Center(
        child: Text('No sheets available.'),
      );
    }

    final currentSheet = _sheets[_selectedSheetIndex];
    if (currentSheet.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_rows_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Sheet "${currentSheet.name}" is empty',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return _buildSheetTable(currentSheet);
  }

  Widget _buildSheetTable(ExcelSheetData sheet) {
    final theme = Theme.of(context);
    const double rowHeaderWidth = 48.0;
    const double rowHeight = 36.0;
    const double colHeaderHeight = 32.0;

    // Estimate column widths
    final List<double> colWidths = List.generate(sheet.maxColumns, (colIdx) {
      int maxLen = _indexToColLetters(colIdx).length;
      final sampleRows = min(sheet.rows.length, 60);
      for (int r = 0; r < sampleRows; r++) {
        final cellVal = sheet.rows[r][colIdx];
        if (cellVal.length > maxLen) {
          maxLen = cellVal.length;
        }
      }
      return (maxLen * 8.5 + 24.0).clamp(70.0, 240.0);
    });

    final double totalWidth = rowHeaderWidth + colWidths.fold(0.0, (sum, w) => sum + w);

    return Column(
      children: [
        // Selected cell formula bar preview
        if (_selectedRow != null && _selectedCol != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_indexToColLetters(_selectedCol!)}${_selectedRow! + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sheet.rows[_selectedRow!][_selectedCol!],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen, size: 18),
                  tooltip: 'View full cell',
                  onPressed: () => _showCellDetails(
                    _selectedRow!,
                    _selectedCol!,
                    sheet.rows[_selectedRow!][_selectedCol!],
                  ),
                ),
              ],
            ),
          ),

        // Scrollable Table (Horizontal outer scroll, vertical inner list)
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    // Sticky Column Header Row
                    Container(
                      height: colHeaderHeight,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        border: Border(
                          bottom: BorderSide(color: theme.dividerColor, width: 1.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: rowHeaderWidth,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(right: BorderSide(color: theme.dividerColor)),
                            ),
                            child: Text(
                              '#',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          ...List.generate(sheet.maxColumns, (colIdx) {
                            return Container(
                              width: colWidths[colIdx],
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(right: BorderSide(color: theme.dividerColor)),
                              ),
                              child: Text(
                                _indexToColLetters(colIdx),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                    // Virtualized Rows
                    Expanded(
                      child: ListView.builder(
                        itemCount: sheet.rows.length,
                        itemExtent: rowHeight,
                        itemBuilder: (context, rowIdx) {
                          final rowData = sheet.rows[rowIdx];
                          final isEven = rowIdx % 2 == 0;
                          final baseRowColor = isEven
                              ? theme.colorScheme.surface
                              : theme.colorScheme.surfaceContainerLowest;

                          return Row(
                            children: [
                              // Row number index
                              Container(
                                width: rowHeaderWidth,
                                height: rowHeight,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHigh,
                                  border: Border(
                                    right: BorderSide(color: theme.dividerColor),
                                    bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
                                  ),
                                ),
                                child: Text(
                                  '${rowIdx + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),

                              // Cells in row
                              ...List.generate(sheet.maxColumns, (colIdx) {
                                final cellValue = rowData[colIdx];
                                final isSelected =
                                    _selectedRow == rowIdx && _selectedCol == colIdx;
                                final isMatched = _searchQuery.isNotEmpty &&
                                    cellValue.toLowerCase().contains(_searchQuery);

                                Color cellBg = baseRowColor;
                                if (isSelected) {
                                  cellBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.5);
                                } else if (isMatched) {
                                  cellBg = Colors.amber.withValues(alpha: 0.4);
                                }

                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedRow = rowIdx;
                                      _selectedCol = colIdx;
                                    });
                                  },
                                  onDoubleTap: () {
                                    _showCellDetails(rowIdx, colIdx, cellValue);
                                  },
                                  child: Container(
                                    width: colWidths[colIdx],
                                    height: rowHeight,
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: cellBg,
                                      border: Border(
                                        right: BorderSide(
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : theme.dividerColor.withValues(alpha: 0.5),
                                          width: isSelected ? 2 : 1,
                                        ),
                                        bottom: BorderSide(
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : theme.dividerColor.withValues(alpha: 0.5),
                                          width: isSelected ? 2 : 1,
                                        ),
                                        left: isSelected
                                            ? BorderSide(color: theme.colorScheme.primary, width: 2)
                                            : BorderSide.none,
                                        top: isSelected
                                            ? BorderSide(color: theme.colorScheme.primary, width: 2)
                                            : BorderSide.none,
                                      ),
                                    ),
                                    child: Text(
                                      cellValue,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isMatched ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildBottomBar() {
    if (_sheets.isEmpty) return null;

    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: _sheets.length,
            itemBuilder: (context, index) {
              final isSelected = index == _selectedSheetIndex;
              final sheet = _sheets[index];

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.table_chart_outlined,
                        size: 15,
                        color: isSelected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(sheet.name),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedSheetIndex = index;
                        _selectedRow = null;
                        _selectedCol = null;
                      });
                    }
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SheetEntry {
  final String name;
  final String targetPath;

  _SheetEntry({required this.name, required this.targetPath});
}
