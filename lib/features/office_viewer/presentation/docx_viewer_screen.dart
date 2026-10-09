import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class DocxParagraph {
  final String text;
  final bool isHeading;
  final int headingLevel;
  final bool isBold;

  DocxParagraph({
    required this.text,
    this.isHeading = false,
    this.headingLevel = 1,
    this.isBold = false,
  });
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
  List<DocxParagraph> _paragraphs = [];
  double _fontSize = 16.0;

  @override
  void initState() {
    super.initState();
    _loadDocx();
  }

  Future<void> _loadDocx() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
      final archive = ZipDecoder().decodeBytes(bytes);
      final documentFile = archive.findFile('word/document.xml');

      if (documentFile == null) {
        setState(() {
          _errorMessage = 'Invalid DOCX structure: word/document.xml missing.';
          _isLoading = false;
        });
        return;
      }

      final xmlString = String.fromCharCodes(documentFile.content as List<int>);
      final parsed = _parseDocxXml(xmlString);

      setState(() {
        _paragraphs = parsed;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error reading DOCX: $e';
        _isLoading = false;
      });
    }
  }

  List<DocxParagraph> _parseDocxXml(String xml) {
    final result = <DocxParagraph>[];

    // Split by paragraph tags <w:p>
    final paragraphRegex = RegExp(r'<w:p[\s>](.*?)<\/w:p>', dotAll: true);
    final textRegex = RegExp(r'<w:t[\s>](.*?)<\/w:t>', dotAll: true);
    final headingRegex = RegExp(r'<w:pStyle\s+w:val="Heading(\d)"');
    final titleRegex = RegExp(r'<w:pStyle\s+w:val="Title"');
    final boldRegex = RegExp(r'<w:b\/>|<w:b\s+w:val="true"\/>');

    for (final match in paragraphRegex.allMatches(xml)) {
      final pXml = match.group(1) ?? '';

      // Check heading style
      bool isHeading = false;
      int headingLevel = 1;
      final hMatch = headingRegex.firstMatch(pXml);
      if (hMatch != null) {
        isHeading = true;
        headingLevel = int.tryParse(hMatch.group(1) ?? '1') ?? 1;
      } else if (titleRegex.hasMatch(pXml)) {
        isHeading = true;
        headingLevel = 1;
      }

      final isBold = boldRegex.hasMatch(pXml);

      // Extract text content inside <w:t> tags
      final textBuf = StringBuffer();
      for (final tMatch in textRegex.allMatches(pXml)) {
        final rawText = tMatch.group(1) ?? '';
        // Unescape standard XML entities
        final cleanText = rawText
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&apos;', "'");
        textBuf.write(cleanText);
      }

      final fullText = textBuf.toString().trim();
      if (fullText.isNotEmpty) {
        result.add(DocxParagraph(
          text: fullText,
          isHeading: isHeading,
          headingLevel: headingLevel,
          isBold: isBold,
        ));
      }
    }

    return result;
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

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.filePath);

    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_decrease),
            tooltip: 'Smaller text',
            onPressed: () {
              if (_fontSize > 12) {
                setState(() => _fontSize -= 2);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.text_increase),
            tooltip: 'Larger text',
            onPressed: () {
              if (_fontSize < 32) {
                setState(() => _fontSize += 2);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open in Word / Office app',
            onPressed: _openInExternalApp,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () {
              Share.shareXFiles([XFile(widget.filePath)]);
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
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
                label: const Text('Try opening in external app'),
              ),
            ],
          ),
        ),
      );
    }

    if (_paragraphs.isEmpty) {
      return const Center(
        child: Text('Document is empty or contains only images/tables.'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _paragraphs.map((p) {
          if (p.isHeading) {
            final headingSize = switch (p.headingLevel) {
              1 => _fontSize * 1.5,
              2 => _fontSize * 1.3,
              _ => _fontSize * 1.15,
            };
            return Padding(
              padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
              child: SelectableText(
                p.text,
                style: TextStyle(
                  fontSize: headingSize,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: SelectableText(
              p.text,
              style: TextStyle(
                fontSize: _fontSize,
                height: 1.5,
                fontWeight: p.isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
