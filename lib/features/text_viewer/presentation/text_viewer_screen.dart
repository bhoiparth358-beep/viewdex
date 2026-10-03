import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/dracula.dart';

class TextViewerScreen extends StatefulWidget {
  final String filePath;

  const TextViewerScreen({super.key, required this.filePath});

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  String _content = '';
  bool _loading = true;
  bool _error = false;
  int _lineCount = 0;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        throw Exception('File not found');
      }
      final content = await file.readAsString();
      if (mounted) {
        setState(() {
          _content = content;
          _lineCount = '\n'.allMatches(content).length + 1;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = File(widget.filePath).uri.pathSegments.last;
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

    const codeExtensions = {
      'dart', 'json', 'xml', 'html', 'css', 'yaml', 'py', 'js', 'ts', 'java',
      'kt', 'swift', 'c', 'cpp', 'h', 'go', 'rs', 'rb', 'sh'
    };
    final isCode = codeExtensions.contains(ext);
    final language = _getHighlightLanguage(ext);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(fileName),
            if (!_loading && !_error)
              Text(
                '$_lineCount lines',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
      ),
      body: _buildBody(isCode, language),
    );
  }

  Widget _buildBody(bool isCode, String language) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return const Center(child: Text('Error reading file contents or unsupported encoding.'));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = isDark ? draculaTheme : githubTheme;

    if (isCode) {
      return SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: HighlightView(
            _content,
            language: language,
            theme: theme,
            padding: const EdgeInsets.all(12),
            textStyle: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: SelectableText(
        _content,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      ),
    );
  }

  String _getHighlightLanguage(String ext) {
    switch (ext) {
      case 'dart': return 'dart';
      case 'json': return 'json';
      case 'xml': case 'html': return 'xml';
      case 'css': return 'css';
      case 'yaml': case 'yml': return 'yaml';
      case 'py': return 'python';
      case 'js': return 'javascript';
      case 'ts': return 'typescript';
      case 'java': return 'java';
      case 'kt': return 'kotlin';
      case 'swift': return 'swift';
      case 'c': case 'cpp': case 'h': return 'cpp';
      case 'go': return 'go';
      case 'rs': return 'rust';
      case 'rb': return 'ruby';
      case 'sh': return 'bash';
      default: return 'plaintext';
    }
  }
}
