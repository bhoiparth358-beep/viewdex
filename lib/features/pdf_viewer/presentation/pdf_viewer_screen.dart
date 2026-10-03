import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as p;

class PdfViewerScreen extends StatefulWidget {
  final String path;

  const PdfViewerScreen({super.key, required this.path});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final _pdfViewerController = PdfViewerController();
  int _currentPage = 0;
  int _pageCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.basename(widget.path), style: const TextStyle(fontSize: 16)),
            if (_pageCount > 0)
              Text(
                '$_currentPage / $_pageCount',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
      ),
      body: PdfViewer.file(
        widget.path,
        controller: _pdfViewerController,
        params: PdfViewerParams(
          onViewerReady: (document, controller) {
            setState(() {
              _pageCount = document.pages.length;
              _currentPage = controller.pageNumber ?? 1;
            });
          },
          onPageChanged: (pageNumber) {
            setState(() {
              _currentPage = pageNumber ?? 1;
            });
          },
          loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => 
              const Center(child: CircularProgressIndicator()),
          errorBannerBuilder: (context, error, stackTrace, documentRef) =>
              Center(child: Text('Error loading PDF: $error')),
        ),
      ),
    );
  }
}
