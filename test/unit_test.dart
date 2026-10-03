import 'package:flutter_test/flutter_test.dart';
import 'package:viewdex/core/file_detection/file_type_detector.dart';
import 'package:viewdex/features/file_manager/domain/universal_file.dart';
import 'package:viewdex/core/errors/result.dart';

void main() {
  group('FileTypeDetector tests', () {
    final detector = DefaultFileTypeDetector();

    test('detects PDF files correctly', () {
      expect(detector.detectType('document.pdf'), FileType.pdf);
      expect(detector.detectType('my_file.PDF'), FileType.pdf);
    });

    test('detects Archive files correctly', () {
      expect(detector.detectType('data.zip'), FileType.archive);
      expect(detector.detectType('backup.tar'), FileType.archive);
      expect(detector.detectType('package.7z'), FileType.archive);
      expect(detector.detectType('archive.tar.gz'), FileType.archive);
    });

    test('detects Images correctly', () {
      expect(detector.detectType('photo.png'), FileType.image);
      expect(detector.detectType('picture.jpg'), FileType.image);
      expect(detector.detectType('graphic.webp'), FileType.image);
    });

    test('detects Videos and Audio correctly', () {
      expect(detector.detectType('movie.mp4'), FileType.video);
      expect(detector.detectType('track.mp3'), FileType.audio);
    });

    test('detects Text and Code correctly', () {
      expect(detector.detectType('main.dart'), FileType.text);
      expect(detector.detectType('config.json'), FileType.text);
      expect(detector.detectType('readme.md'), FileType.text);
    });

    test('detects Office documents correctly', () {
      expect(detector.detectType('doc.docx'), FileType.document);
      expect(detector.detectType('sheet.xlsx'), FileType.spreadsheet);
      expect(detector.detectType('slides.pptx'), FileType.presentation);
    });
  });

  group('Result<T> error handling tests', () {
    test('Success returns data and folds properly', () {
      const result = Success('success_data');
      expect(result.isSuccess, true);
      expect(result.isFailure, false);
      expect(result.data, 'success_data');

      final folded = result.fold(
        (data) => 'got $data',
        (error) => 'failed',
      );
      expect(folded, 'got success_data');
    });

    test('Failure returns error and folds properly', () {
      const result = Failure<String>(FileError('File missing'));
      expect(result.isSuccess, false);
      expect(result.isFailure, true);
      expect(result.error.message, 'File missing');

      final folded = result.fold(
        (data) => 'success',
        (error) => 'got error: ${error.message}',
      );
      expect(folded, 'got error: File missing');
    });
  });
}
