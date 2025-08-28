import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_doc_scanner/services/pdf_service.dart';
import 'package:flutter_doc_scanner/cover_page.dart';
import 'package:path/path.dart' as path;
import 'package:file_saver/file_saver.dart';
import 'package:mime_type/mime_type.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_doc_scanner/widgets/progress_dialog.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:ui' as ui;
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

// AI Summarization imports
import '../services/offline_gemma_service.dart';
import '../services/pdf_text_extraction_service.dart';
import '../services/enhanced_pdf_text_extraction_service.dart';
import '../widgets/summary_display_widget.dart';
import 'ai_setup_screen.dart';

// We'll add this as a simple dialog for now to avoid import issues
class DocumentCoverPageScreen extends StatelessWidget {
  final List<String> scannedDocuments;
  
  const DocumentCoverPageScreen({Key? key, required this.scannedDocuments}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cover Page'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Cover page editing functionality'),
      ),
    );
  }
}

class OptimizedPdfPreview extends StatefulWidget {
  final String pdfPath;
  final String documentTitle;
  final List<String>? allDocumentPaths;

  const OptimizedPdfPreview({
    Key? key,
    required this.pdfPath,
    required this.documentTitle,
    this.allDocumentPaths,
  }) : super(key: key);

  @override
  State<OptimizedPdfPreview> createState() => _OptimizedPdfPreviewState();
}

class _OptimizedPdfPreviewState extends State<OptimizedPdfPreview> {
  late File pdfFile;
  bool isLoading = true;
  Map<String, String> _coverPageInfo = {};
  List<File> _documentPages = [];
  List<Uint8List> _documentPageImages = [];
  bool _isEditMode = false;
  int _currentPage = 0;
  int _totalPages = 0;
  final PdfService _pdfService = PdfService();
  final _fileNameController = TextEditingController();
  String _lastUsedFileName = '';
  
  // AI Summarization state
  bool _isAiProcessing = false;
  bool _isModelReady = false;
  EnhancedPdfTextExtractionService? _textExtractionService;
  
  Future<void> _incrementUserScanCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email') ?? 'guest';
      final key = 'scan_count_${email.toLowerCase()}';
      final current = prefs.getInt(key) ?? 0;
      await prefs.setInt(key, current + 1);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    pdfFile = File(widget.pdfPath);
    _initializeDocument();
    _loadLastFileName();
  }
  
  Future<void> _loadLastFileName() async {
    final prefs = await SharedPreferences.getInstance();
    final lastName = prefs.getString('last_pdf_filename') ?? '';
    if (lastName.isNotEmpty) {
      _lastUsedFileName = lastName;
      _fileNameController.text = lastName;
    } else {
      _fileNameController.text = 'ScanMate_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<void> _saveLastFileName(String fileName) async {
    if (fileName.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_pdf_filename', fileName);
      _lastUsedFileName = fileName;
    }
  }
  
  Future<void> _initializeDocument() async {
    try {
      // Load cover page info
      _coverPageInfo = await getLastCoverPageInfo();
      
      // Check if we have multiple documents and add a cover page
      if (widget.allDocumentPaths != null && widget.allDocumentPaths!.isNotEmpty && _coverPageInfo.isNotEmpty) {
        print('Adding cover page to ${widget.allDocumentPaths!.length} documents');
        
        // Extract document pages for editing
        _documentPages = widget.allDocumentPaths!.map((path) => File(path)).toList();
        
        final coverPagePdfPath = await generateCoverPageForDocuments(
          widget.allDocumentPaths!,
          _coverPageInfo,
        );
        
        // If cover page was generated, update the file reference
        if (coverPagePdfPath != null) {
          pdfFile = File(coverPagePdfPath);
          print('Cover page PDF created successfully at: ${pdfFile.path}');
        }
      } else {
        // If we only have one document, check if it needs conversion
        if (await pdfFile.exists()) {
          final bytes = await pdfFile.readAsBytes();
          
          if (bytes.isNotEmpty) {
            // Add the single document to our document pages
            _documentPages = [pdfFile];
            
            // Check if file is a JPEG that needs conversion
            if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
              print('File is a JPEG, converting to PDF');
              pdfFile = await _pdfService.convertJpegToPdf(pdfFile, title: widget.documentTitle);
              _documentPages = [pdfFile];
              
              // Add cover page to the single document
              if (_coverPageInfo.isNotEmpty) {
                print('Adding cover page to single document');
                final coverPagePdfPath = await generateCoverPageForDocuments(
                  [pdfFile.path],
                  _coverPageInfo,
                );
                
                if (coverPagePdfPath != null) {
                  pdfFile = File(coverPagePdfPath);
                  print('Cover page added to single document: ${pdfFile.path}');
                }
              }
            }
          }
        }
      }

      // Extract page thumbnails for the edit mode
      await _extractPageImages();
    } catch (e) {
      print('Error initializing document: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _extractPageImages() async {
    try {
      _documentPageImages = [];
      for (final file in _documentPages) {
        if (await file.exists()) {
          final Uint8List fileBytes = await file.readAsBytes();
          print('Processing file: ${file.path}, size: ${fileBytes.length} bytes');
          
          // Check if it's a PDF file or image file
          if (fileBytes.length >= 4 && String.fromCharCodes(fileBytes.take(4)) == '%PDF') {
            print('Detected PDF file: ${file.path}');
            // It's a PDF file - create a thumbnail representation
            try {
              final Uint8List pdfThumbnail = await _createPdfThumbnail(file);
              _documentPageImages.add(pdfThumbnail);
              print('Successfully added PDF thumbnail for: ${file.path}');
            } catch (e) {
              print('Error creating PDF thumbnail for ${file.path}: $e');
              // Use fallback - add original bytes
              _documentPageImages.add(fileBytes);
            }
          } else {
            print('Detected image file: ${file.path}');
            // It's an image file - use directly
            _documentPageImages.add(fileBytes);
            print('Successfully added image: ${file.path}');
          }
        } else {
          print('File does not exist: ${file.path}');
        }
      }
      print('Extracted ${_documentPageImages.length} page images from ${_documentPages.length} files');
    } catch (e) {
      print('Error extracting page images: $e');
    }
  }

    Future<Uint8List> _createPdfThumbnail(File pdfFile) async {
    print('Creating PDF thumbnail for: ${pdfFile.path}');
    
    try {
      
      // Create a clear PDF representation for thumbnail
      final String fileName = path.basename(pdfFile.path);
      final Uint8List pdfBytes = await pdfFile.readAsBytes();
      final int fileSize = (pdfBytes.length / 1024).round();
      
      print('Creating visual PDF representation thumbnail...');
      
      final pw.Document thumbnailDoc = pw.Document();
      thumbnailDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: PdfColors.red300, width: 2),
              ),
              padding: const pw.EdgeInsets.all(20),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  // Large PDF icon
                  pw.Container(
                    width: 120,
                    height: 150,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red50,
                      border: pw.Border.all(color: PdfColors.red400, width: 2),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          '📄',
                          style: pw.TextStyle(fontSize: 40),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.red600,
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                          child: pw.Text(
                            'PDF',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  pw.SizedBox(height: 15),
                  
                  // File name
                  pw.Text(
                    fileName.length > 25 ? '${fileName.substring(0, 22)}...' : fileName,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  
                  pw.SizedBox(height: 5),
                  
                  // File size
                  pw.Text(
                    '${fileSize}KB',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                  
                  pw.SizedBox(height: 10),
                  
                  // Source label
                  pw.Text(
                    'From ScanMate Folder',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey500,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
      
      final result = await thumbnailDoc.save();
      print('Successfully created PDF representation thumbnail: ${result.length} bytes');
      return result;
    } catch (e) {
      print('Error creating PDF thumbnail: $e');
      
      // Ultimate fallback
      final pw.Document simpleDoc = pw.Document();
      simpleDoc.addPage(
        pw.Page(
          build: (context) => pw.Container(
            color: PdfColors.grey200,
            child: pw.Center(
              child: pw.Text(
                'PDF Document',
                style: pw.TextStyle(fontSize: 18, color: PdfColors.black),
              ),
            ),
          ),
        ),
      );
      return await simpleDoc.save();
    }
  }

  /// Extracts PDF pages as individual image files using pdfx for real rendering
  Future<List<File>> _extractPdfPagesAsImages(File pdfFile, Directory tempDir) async {
    final List<File> extractedImages = [];
      print('Starting PDF page extraction for: ${pdfFile.path}');
      
      // Create a unique temporary directory for this PDF
      final String pdfBaseName = path.basenameWithoutExtension(pdfFile.path);
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final Directory pdfTempDir = Directory('${tempDir.path}/pdf_${timestamp}');
      await pdfTempDir.create(recursive: true);
      
    try {
      // Use pdfx to open and render real pages
      final pdfx.PdfDocument document = await pdfx.PdfDocument.openFile(pdfFile.path);
      final int pagesCount = document.pagesCount;
      print('PDF has $pagesCount page(s)');

      for (int i = 1; i <= pagesCount; i++) {
        try {
          print('Extracting page $i/$pagesCount...');
          final pdfx.PdfPage page = await document.getPage(i);
          final pageImage = await page.render(
            width: page.width, // keep natural size
            height: page.height,
            format: pdfx.PdfPageImageFormat.png,
          );
          await page.close();

          if (pageImage != null && pageImage.bytes.isNotEmpty) {
            final String imageFileName = '${pdfBaseName}_page_${i}_$timestamp.png';
            final String imagePath = path.join(pdfTempDir.path, imageFileName);
            final File imageFile = File(imagePath);
            await imageFile.writeAsBytes(pageImage.bytes);
            if (await imageFile.exists()) {
              extractedImages.add(imageFile);
              print('Successfully extracted page $i as: $imagePath');
            }
          } else {
            print('Render returned empty bytes for page $i');
          }
        } catch (e) {
          print('Error rendering page $i: $e');
        }
      }
      
      await document.close();
      print('Successfully extracted ${extractedImages.length} pages from PDF');
      return extractedImages;
    } catch (e) {
      print('pdfx rendering failed, falling back to placeholder images: $e');
      // Fallback to placeholder approach
      try {
        final Uint8List pdfBytes = await pdfFile.readAsBytes();
        final int estimatedPageCount = _estimatePdfPageCount(pdfBytes);
        for (int pageIndex = 0; pageIndex < estimatedPageCount; pageIndex++) {
          final Uint8List? pageImageBytes = await _renderPdfPageAsImage(pdfFile, pageIndex);
          if (pageImageBytes != null && pageImageBytes.isNotEmpty) {
            final String imageFileName = '${pdfBaseName}_page_${pageIndex + 1}_$timestamp.png';
            final String imagePath = path.join(pdfTempDir.path, imageFileName);
            final File imageFile = File(imagePath);
            await imageFile.writeAsBytes(pageImageBytes);
            if (await imageFile.exists()) {
              extractedImages.add(imageFile);
            }
          }
        }
      } catch (e2) {
        print('Fallback placeholder extraction also failed: $e2');
      }
      return extractedImages;
    }
  }

  /// Estimates the number of pages in a PDF based on file size and content analysis
  int _estimatePdfPageCount(Uint8List pdfBytes) {
    try {
      // Convert bytes to string for analysis
      final String pdfContent = String.fromCharCodes(pdfBytes);
      
      // Count page objects in PDF - this is a rough estimation
      final RegExp pageCountRegex = RegExp(r'/Type\s*/Page\b');
      final Iterable<Match> pageMatches = pageCountRegex.allMatches(pdfContent);
      int pageCount = pageMatches.length;
      
      // If we found page objects, use that count
      if (pageCount > 0) {
        print('Found $pageCount page objects in PDF');
        return pageCount.clamp(1, 20); // Cap at 20 pages for safety
      }
      
      // Fallback: estimate based on file size
      final int sizeKB = pdfBytes.length ~/ 1024;
      if (sizeKB < 50) return 1;
      if (sizeKB < 200) return 2;
      if (sizeKB < 500) return 3;
      if (sizeKB < 1000) return 4;
      if (sizeKB < 2000) return 5;
      return (sizeKB / 400).round().clamp(1, 15); // Rough estimate
      
    } catch (e) {
      print('Error estimating page count: $e');
      return 1; // Default to 1 page
    }
  }

  /// Renders a specific PDF page as an image using a programmatic approach
  Future<Uint8List?> _renderPdfPageAsImage(File pdfFile, int pageIndex) async {
    try {
      // Generate a simple PNG placeholder image that represents the PDF page.
      const int width = 600;
      const int height = 800;

      // Create a blank white canvas.
      final img.Image placeholder = img.Image(width: width, height: height);
      img.fill(placeholder, color: img.ColorRgb8(255, 255, 255));

      // Draw a light grey border around the canvas.
      img.fillRect(
        placeholder,
        x1: 0,
        y1: 0,
        x2: width - 1,
        y2: height - 1,
        color: img.ColorRgb8(200, 200, 200),
      );

      // Compose a label (e.g., "PDF Page 3").
      final String label = 'PDF Page ${pageIndex + 1}';

      // Center the text horizontally.
      // Draw label roughly at center
      final img.BitmapFont font = img.arial14;
      // Use simple positioning as BitmapFont doesn't have measureString or fontSize
      final int textX = (width - label.length * 7) ~/ 2; // Approximate text width
      final int textY = height ~/ 2;
      img.drawString(placeholder, label,
          font: font,
          x: textX,
          y: textY,
          color: img.ColorRgb8(0, 0, 0));

      // Encode the image as PNG.
      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(placeholder));
      return pngBytes;
    } catch (e) {
      print('Error rendering PDF page placeholder: $e');
      return null;
    }
  }
    // Legacy placeholder disabled
      /* Legacy PDF render placeholder - disabled
print('Rendering PDF page $pageIndex from: ${pdfFile.path}');
      
      // Create a visual representation of the PDF page
      // Since we don't have a direct PDF-to-image renderer, we'll create a high-quality
      // visual representation that includes the PDF content indication
      
      final String fileName = path.basename(pdfFile.path);
      final Uint8List pdfBytes = await pdfFile.readAsBytes();
      final int fileSize = (pdfBytes.length / 1024).round();
      
      // Create a document page that represents this PDF page
      final pw.Document pageDoc = pw.Document();
      pageDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Container(
            width: double.infinity,
            height: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: PdfColors.grey400, width: 1),
            ),
            child: pw.Stack(
              children: [
                // Main content area with document simulation
                pw.Positioned.fill(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(40),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Header area
                        pw.Container(
                          width: double.infinity,
                          height: 60,
                          decoration: pw.BoxDecoration(
                            color: PdfColors.blue50,
                            border: pw.Border.all(color: PdfColors.blue200),
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Center(
                            child: pw.Text(
                              'PDF Document Page ${pageIndex + 1}',
                              style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blue800,
                              ),
                            ),
                          ),
                        ),
                        
                        pw.SizedBox(height: 30),
                        
                        // Simulated document content lines
                        for (int i = 0; i < 25; i++) ...[
                          pw.Container(
                            width: _getLineWidth(i),
                            height: 12,
                            margin: const pw.EdgeInsets.only(bottom: 8),
                            decoration: pw.BoxDecoration(
                              color: _getLineColor(i),
                              borderRadius: pw.BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // PDF source indicator
                pw.Positioned(
                  top: 15,
                  right: 15,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red600,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          '📄',
                          style: pw.TextStyle(fontSize: 12),
                        ),
                        pw.SizedBox(width: 4),
                        pw.Text(
                          'PDF',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Page info at bottom
                pw.Positioned(
                  bottom: 15,
                  left: 15,
                  right: 15,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          fileName.length > 20 ? '${fileName.substring(0, 17)}...' : fileName,
                          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        ),
                        pw.Text(
                          'Page ${pageIndex + 1} • ${fileSize}KB',
                          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      
      // Convert the document to bytes (this represents our "rendered" page)
      final Uint8List pageBytes = await pageDoc.save();
      print('Generated page representation: ${pageBytes.length} bytes');
      
      return pageBytes;
      
    } catch (e) {
      print('Error rendering PDF page: $e');
      return null;
*/

  /// Helper method to get varying line widths for document simulation
  double _getLineWidth(int index) {
    final List<double> widths = [400, 350, 420, 300, 380, 450, 320, 390];
    return widths[index % widths.length];
  }

  /// Helper method to get varying line colors for document simulation
  PdfColor _getLineColor(int index) {
    if (index % 8 == 0) return PdfColors.blue100; // Occasional blue lines (headings)
    if (index % 5 == 0) return PdfColors.grey300; // Some grey lines (subheadings)
    return PdfColors.grey200; // Regular text lines
  }
  
  Future<void> _regeneratePdfWithNewOrder() async {
    setState(() {
      isLoading = true;
    });
    
    try {
      // Separate image files and PDF files for proper handling
      final List<String> imagePaths = [];
      final List<File> pdfFiles = [];
      
      for (final file in _documentPages) {
        final bytes = await file.readAsBytes();
        if (bytes.length >= 4 && String.fromCharCodes(bytes.take(4)) == '%PDF') {
          pdfFiles.add(file);
        } else {
          imagePaths.add(file.path);
        }
      }
      
      print('Regenerating PDF with ${imagePaths.length} images and ${pdfFiles.length} PDFs');
      
      // If we have mixed content or only images, use the standard approach
      if (pdfFiles.isEmpty) {
      final coverPagePdfPath = await generateCoverPageForDocuments(
          imagePaths,
        _coverPageInfo,
      );
      
      if (coverPagePdfPath != null) {
        pdfFile = File(coverPagePdfPath);
          print('PDF regenerated with images at: ${pdfFile.path}');
        }
      } else {
        // Create a new PDF that combines images and existing PDFs
        final combinedPdfPath = await _createCombinedPdf(imagePaths, pdfFiles);
        if (combinedPdfPath != null) {
          pdfFile = File(combinedPdfPath);
          print('Combined PDF created at: ${pdfFile.path}');
        }
      }
    } catch (e) {
      print('Error regenerating PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error regenerating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          _isEditMode = false;
        });
      }
    }
  }

  Future<String?> _createCombinedPdf(List<String> imagePaths, List<File> pdfFiles) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String combinedPdfPath = '${tempDir.path}/combined_${DateTime.now().millisecondsSinceEpoch}.pdf';
      
      // Create a new PDF document
      final pw.Document combinedDoc = pw.Document();
      
      // Add cover page if available (formatted like the provided sample)
      if (_coverPageInfo.isNotEmpty) {
        combinedDoc.addPage(
          pw.Page(
            build: (context) {
              pw.Widget headerLogo = pw.SizedBox();
              try {
                final ByteData logoData = rootBundle.load('assets/nsu_logo.png') as ByteData;
                headerLogo = pw.Image(pw.MemoryImage(logoData.buffer.asUint8List()), height: 80);
              } catch (_) {}
              return pw.Padding(
                padding: const pw.EdgeInsets.all(40),
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                    pw.Center(child: headerLogo),
                    pw.SizedBox(height: 12),
                    pw.Center(
                      child: pw.Column(children: [
                        pw.Text('North South University', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 6),
                        pw.Text('Department of Electrical and Computer Engineering', style: pw.TextStyle(fontSize: 12)),
                      ]),
                    ),
                    pw.SizedBox(height: 28),
                    pw.Row(children: [pw.Container(width: 80, child: pw.Text('Name:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))), pw.Expanded(child: pw.Text(_coverPageInfo['name'] ?? ''))]),
                    pw.Row(children: [pw.Container(width: 80, child: pw.Text('ID:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))), pw.Expanded(child: pw.Text(_coverPageInfo['studentId'] ?? ''))]),
                    pw.Row(children: [pw.Container(width: 80, child: pw.Text('Course:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))), pw.Expanded(child: pw.Text(_coverPageInfo['courseName'] ?? ''))]),
                    pw.Row(children: [pw.Container(width: 80, child: pw.Text('Section:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))), pw.Expanded(child: pw.Text(_coverPageInfo['section'] ?? ''))]),
                    pw.SizedBox(height: 28),
                    pw.Center(child: pw.Text('ASSIGNMENT - ${_coverPageInfo['assignmentNumber'] ?? '1'}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
                    pw.SizedBox(height: 16),
                    pw.Row(children: [pw.Container(width: 120, child: pw.Text('Submitted To:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))), pw.Expanded(child: pw.Text((_coverPageInfo['submittedTo'] ?? '').toString().toUpperCase()))]),
                    pw.Row(children: [pw.Container(width: 120, child: pw.Text('Submission Date:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))), pw.Expanded(child: pw.Text(DateTime.now().toString().split(' ').first))]),
                  ],
                ),
              );
            },
          ),
        );
      }
      
      // Process all files in order
      for (final file in _documentPages) {
        try {
          final bytes = await file.readAsBytes();
          
                    if (bytes.length >= 4 && String.fromCharCodes(bytes.take(4)) == '%PDF') {
            // This should rarely happen now since we extract PDF pages as images
            // But keep as fallback for any PDFs that couldn't be extracted
            print('Found PDF file in document pages (fallback): ${path.basename(file.path)}');
            
            final String fileName = path.basename(file.path);
            final int fileSize = (bytes.length / 1024).round();
            
            combinedDoc.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4,
                build: (context) => pw.Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: PdfColors.white,
                  padding: const pw.EdgeInsets.all(40),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      // PDF Icon
                      pw.Container(
                        width: 150,
                        height: 200,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.red50,
                          border: pw.Border.all(color: PdfColors.red400, width: 3),
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            pw.Text(
                              '📄',
                              style: pw.TextStyle(fontSize: 64),
                            ),
                            pw.SizedBox(height: 10),
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.red600,
                                borderRadius: pw.BorderRadius.circular(4),
                              ),
                              child: pw.Text(
                                'PDF',
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      pw.SizedBox(height: 30),
                      
                      // File information
                      pw.Container(
                        padding: const pw.EdgeInsets.all(20),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: PdfColors.grey300),
                        ),
                        child: pw.Column(
                          children: [
                            pw.Text(
                              'PDF Document from ScanMate',
                              style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey800,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 10),
                            pw.Text(
                              fileName.length > 40 ? '${fileName.substring(0, 37)}...' : fileName,
                              style: pw.TextStyle(
                                fontSize: 12,
                                color: PdfColors.grey700,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              'Size: ${fileSize}KB',
                              style: pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey600,
                              ),
                            ),
                            pw.SizedBox(height: 10),
                            pw.Text(
                              '(Fallback: Could not extract individual pages)',
                              style: pw.TextStyle(
                                fontSize: 8,
                                color: PdfColors.red600,
                                fontStyle: pw.FontStyle.italic,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            
            print('Successfully added PDF fallback representation for: ${fileName}');
          } else {
            // It's an image - add directly
            combinedDoc.addPage(
              pw.Page(
                build: (context) => pw.Center(
                  child: pw.Image(pw.MemoryImage(bytes)),
                ),
              ),
            );
          }
        } catch (e) {
          print('Error adding file ${file.path} to combined PDF: $e');
        }
      }
      
      // Save the combined PDF
      final combinedPdfBytes = await combinedDoc.save();
      final combinedFile = File(combinedPdfPath);
      await combinedFile.writeAsBytes(combinedPdfBytes);
      
      return combinedPdfPath;
    } catch (e) {
      print('Error creating combined PDF: $e');
      return null;
    }
  }
  
  Future<void> _addNewPage() async {
    // Modern bottom sheet UI with Cancel at the end
    final String? selectedOption = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, -2)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
                mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                const Text('Add Pages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Take more photos'),
                  onTap: () => Navigator.pop(ctx, 'take_photos'),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Select from ScanMate'),
                  onTap: () => Navigator.pop(ctx, 'select_pdf'),
                ),
                const SizedBox(height: 4),
            TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ],
              ),
            ),
        );
      },
    );

    if (selectedOption == null) return;

    switch (selectedOption) {
      case 'take_photos':
        await _takeMorePhotos();
        break;
      case 'select_pdf':
        await _selectFromScanMateFolder();
        break;
    }
  }

  /// Opens the cover page editing screen
  Future<void> _editCoverPage() async {
    try {
      final current = await getLastCoverPageInfo();
      final nameCtl = TextEditingController(text: current['name'] ?? '');
      final emailCtl = TextEditingController(text: current['email'] ?? '');
      final idCtl = TextEditingController(text: current['studentId'] ?? '');
      final courseCtl = TextEditingController(text: current['courseName'] ?? '');
      final assignmentCtl = TextEditingController(text: current['assignmentNumber'] ?? '1');
      final sectionCtl = TextEditingController(text: current['section'] ?? '');
      final submittedToCtl = TextEditingController(text: current['submittedTo'] ?? '');

      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Edit Cover Page Info'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: TextField(controller: assignmentCtl, decoration: const InputDecoration(labelText: 'Assignment No.'))),
                      SizedBox(width: 8),
                      Expanded(child: TextField(controller: sectionCtl, decoration: const InputDecoration(labelText: 'Section'))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: submittedToCtl, decoration: const InputDecoration(labelText: 'Submitted To (Faculty)')),
                  const SizedBox(height: 8),
                  TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 8),
                  TextField(controller: emailCtl, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 8),
                  TextField(controller: idCtl, decoration: const InputDecoration(labelText: 'Student ID')),
                  const SizedBox(height: 8),
                  TextField(controller: courseCtl, decoration: const InputDecoration(labelText: 'Course')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          );
        },
      ) ??
          false;

      if (!saved) return;

      final info = {
        'name': nameCtl.text.trim(),
        'email': emailCtl.text.trim(),
        'studentId': idCtl.text.trim(),
        'courseName': courseCtl.text.trim(),
        'assignmentNumber': assignmentCtl.text.trim().isEmpty ? '1' : assignmentCtl.text.trim(),
        'section': sectionCtl.text.trim(),
        'submittedTo': submittedToCtl.text.trim(),
      };
      await saveCoverPageInfo(info);
      _coverPageInfo = info;

          await _regeneratePdfWithNewOrder();
      
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cover page updated successfully'),
                backgroundColor: Colors.green,
              ),
            );
      }
    } catch (e) {
      print('Error editing cover page: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error editing cover page: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Uses ML Kit scanner to take new photos and add them to the current document
  Future<void> _takeMorePhotos() async {
    try {
        setState(() {
          isLoading = true;
        });
        
      // Use FlutterDocScanner to take new photos
      final result = await FlutterDocScanner().getScannedDocumentAsImages(
        page: 10, // Allow up to 10 new pages
        maxResolution: 1200,
        quality: 80,
      );

      if (result != null && result is List && result.isNotEmpty) {
        print('Scanned ${result.length} new pages');
        
        // Convert scanned images to Files and add to document pages
        int addedCount = 0;
        for (final imagePath in result) {
          if (imagePath is String) {
            final File imageFile = File(imagePath);
            if (await imageFile.exists()) {
              _documentPages.add(imageFile);
              addedCount++;
              print('Added new photo: $imagePath');
            } else {
              print('Image file does not exist: $imagePath');
            }
          } else {
            print('Invalid image path type: ${imagePath.runtimeType}');
          }
        }
        
        print('Added $addedCount images to _documentPages. Total pages: ${_documentPages.length}');
        
        // Extract page thumbnails to update the _documentPageImages list
        await _extractPageImages();
        
        print('After _extractPageImages: ${_documentPageImages.length} images in display list');
        
        // Force UI update to show new pages immediately in edit mode
        if (mounted) {
          setState(() {
            _isEditMode = true; // Ensure we're in edit mode to see the new pages
          });
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added $addedCount new pages. You can now reorder them in edit mode.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('No images returned from ML Kit scanner');
      }
    } catch (e) {
      print('Error taking new photos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error taking new photos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// Allows user to browse and select existing PDFs from the ScanMate folder
  /// Each page of the selected PDF is added individually for reordering
  Future<void> _selectFromScanMateFolder() async {
    try {
      setState(() {
        isLoading = true;
      });

      // Prepare candidate directories to search for PDFs
      final List<File> pdfFiles = [];

      // 1) App cache directory (where freshly scanned PDFs may live)
      final cacheDir = await getTemporaryDirectory();
      pdfFiles.addAll(await _findPdfFilesInDir(cacheDir));

      // 2) App documents/ScanMate (always accessible)
      final appDocs = await getApplicationDocumentsDirectory();
      final appDocsScanMate = Directory('${appDocs.path}/ScanMate');
      if (await appDocsScanMate.exists()) {
        pdfFiles.addAll(await _findPdfFilesInDir(appDocsScanMate));
      }

      // 3) External app-specific dir/ScanMate (Android)
      if (Platform.isAndroid) {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
          final externalScanMate = Directory('${externalDir.path}/ScanMate');
          if (await externalScanMate.exists()) {
            pdfFiles.addAll(await _findPdfFilesInDir(externalScanMate));
          }
        }

        // 4) Public Downloads/ScanMate (may need permission on some OS versions)
        final downloadsScanMate = Directory('/storage/emulated/0/Download/ScanMate');
        if (await downloadsScanMate.exists()) {
          // Best-effort permission for broader access on older Android versions
          await _ensureStoragePermissionIfNeeded();
          pdfFiles.addAll(await _findPdfFilesInDir(downloadsScanMate));
        }
      }

      // Deduplicate by path
      final Map<String, File> unique = {
        for (final f in pdfFiles) f.path: f,
      };
      final List<File> uniquePdfs = unique.values.toList()..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      if (uniquePdfs.isEmpty) {
        throw Exception('No PDF files found in ScanMate locations. Save a PDF first, then try again.');
      }

      // Option A: Directly open system picker at ScanMate, then merge with discovered list
      File? selectedPdf;
      try {
        final dynamic pickedPath = await FlutterDocScanner().pickPdfFromScanMate();
        if (pickedPath is String && pickedPath.toLowerCase().endsWith('.pdf')) {
          selectedPdf = File(pickedPath);
        }
      } catch (_) {
        // Ignore and fall back to in-app selector
      }

      // If system picker didn't return, show in-app list
      selectedPdf ??= await _showPdfSelectionDialog(uniquePdfs);

      if (selectedPdf != null) {
        await _extractPagesFromPdf(selectedPdf);
      }
    } catch (e) {
      print('Error selecting from ScanMate folder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<bool> _ensureStoragePermissionIfNeeded() async {
    if (!Platform.isAndroid) return true;
    final sdkInt = int.tryParse((await _getAndroidSdkInt()) ?? '') ?? 0;
    // On Android 13+ (SDK 33), READ_EXTERNAL_STORAGE is not used for PDFs. We will best-effort request manage/storage
    // only if the plugin exposes it; otherwise rely on accessible dirs.
    // For <= 12, ask for storage permission.
    if (sdkInt <= 32) {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
    return true;
  }

  Future<String?> _getAndroidSdkInt() async {
    try {
      final MethodChannel platform = const MethodChannel('flutter_doc_scanner_internal');
      final String? sdk = await platform.invokeMethod<String>('getAndroidSdkInt');
      return sdk;
    } catch (_) {
      return null;
    }
  }

  Future<List<File>> _findPdfFilesInDir(Directory dir) async {
    try {
      if (!await dir.exists()) return [];
      final entries = await dir.list().toList();
      return entries
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<File?> _showPdfSelectionDialog(List<File> pdfFiles) async {
    return await showDialog<File>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select PDF'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: pdfFiles.length,
              itemBuilder: (context, index) {
                final file = pdfFiles[index];
                final fileName = path.basename(file.path);
                final fileSize = file.lengthSync();
                final fileSizeKB = (fileSize / 1024).round();

                return ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: Text(fileName),
                  subtitle: Text('${fileSizeKB}KB'),
                  onTap: () => Navigator.pop(context, file),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _extractPagesFromPdf(File pdfFile) async {
    try {
      print('Extracting pages from PDF: ${pdfFile.path}');

      // Read the PDF bytes
      final Uint8List pdfBytes = await pdfFile.readAsBytes();
      
      // For this implementation, we'll convert the entire PDF to images
      // and then add each image as a separate page
      // Note: This is a simplified approach. For better PDF page extraction,
      // you might want to use a more specialized PDF library

      final Directory tempDir = await getTemporaryDirectory();
      final String tempPdfPath = '${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final File tempPdfFile = File(tempPdfPath);
      await tempPdfFile.writeAsBytes(pdfBytes);

      // Create a temporary image from the PDF for demonstration
      // In a real implementation, you would extract individual pages
      final String tempImagePath = '${tempDir.path}/temp_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File tempImageFile = File(tempImagePath);
      
      // Since we don't have a PDF-to-image converter, we'll treat the PDF as a single page
      // and add it as an image. For proper implementation, consider using:
      // - native PDF rendering libraries
      // - server-side PDF processing
      // - specialized Flutter packages for PDF page extraction
      
      // For now, we'll create a placeholder approach by copying the PDF data
      // and converting it to an image representation
      await _convertPdfToImages(pdfFile, tempDir);

    } catch (e) {
      print('Error extracting pages from PDF: $e');
      throw Exception('Failed to extract pages from PDF: $e');
    }
  }

  Future<void> _convertPdfToImages(File pdfFile, Directory tempDir) async {
    try {
      // Check if the PDF file exists and is valid
      if (!await pdfFile.exists()) {
        print('ERROR: PDF file does not exist: ${pdfFile.path}');
        return;
      }
      
      final fileBytes = await pdfFile.readAsBytes();
      print('PDF file info: ${pdfFile.path}, size: ${fileBytes.length} bytes');
      
      // Verify it's actually a PDF
      if (fileBytes.length >= 4 && String.fromCharCodes(fileBytes.take(4)) == '%PDF') {
        print('Confirmed: File is a valid PDF');
      } else {
        print('WARNING: File does not appear to be a PDF: ${String.fromCharCodes(fileBytes.take(10))}');
      }
      
      // Instead of adding the PDF file directly, extract its pages as images
      print('Extracting PDF pages as individual images...');
      final List<File> extractedPageImages = await _extractPdfPagesAsImages(pdfFile, tempDir);
      
      if (extractedPageImages.isNotEmpty) {
        // Add the extracted page images to document pages
        for (final imageFile in extractedPageImages) {
          _documentPages.add(imageFile);
          print('Added extracted PDF page image: ${imageFile.path}');
        }
        
        print('Successfully extracted ${extractedPageImages.length} pages from PDF');
        
        // Extract page thumbnails to update the _documentPageImages list
        await _extractPageImages();
        
        print('After _extractPageImages: ${_documentPageImages.length} images in display list');

        // Force UI update to show new PDF page images immediately in edit mode
        if (mounted) {
          setState(() {
            _isEditMode = true; // Ensure we're in edit mode to see the new PDF pages
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added ${extractedPageImages.length} pages from ${path.basename(pdfFile.path)}. You can now reorder them in edit mode.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('No pages could be extracted from PDF, falling back to PDF representation');
        // Fallback: add the PDF file directly
        _documentPages.add(pdfFile);
        await _extractPageImages();
        
        if (mounted) {
          setState(() {
            _isEditMode = true;
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added PDF representation from ${path.basename(pdfFile.path)}. Actual page extraction failed.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      print('Successfully processed PDF');
    } catch (e) {
      print('Error converting PDF to images: $e');
      rethrow;
    }
  }

  Future<List<File>> _extractIndividualPagesFromPdf(File pdfFile, Directory tempDir) async {
    try {
      final List<File> extractedPages = [];
      
      // Read the original PDF
      final Uint8List originalBytes = await pdfFile.readAsBytes();
      
      // Create image representations of the PDF pages
      // Since the existing system works with images, we'll convert PDF to images
      final String baseName = path.basenameWithoutExtension(pdfFile.path);
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // For better integration with the existing system, we'll create image files
      // that represent the PDF content
      final List<File> pdfAsImages = await _convertPdfToImageFiles(
        pdfFile, 
        tempDir, 
        baseName, 
        timestamp
      );
      
      extractedPages.addAll(pdfAsImages);

      print('Extracted ${extractedPages.length} page images from PDF');
      return extractedPages;
      
    } catch (e) {
      print('Error extracting individual pages: $e');
      // Fallback: create a single representation of the PDF
      return await _createPdfFallbackRepresentation(pdfFile, tempDir);
    }
  }

  Future<List<File>> _convertPdfToImageFiles(
    File pdfFile, 
    Directory tempDir, 
    String baseName, 
    int timestamp
  ) async {
    final List<File> imageFiles = [];
    
    try {
      // Read the PDF bytes
      final Uint8List pdfBytes = await pdfFile.readAsBytes();
      
      // Since we don't have a direct PDF-to-image converter in this package,
      // we'll create a practical solution by creating image placeholders
      // that represent the PDF content
      
      // Estimate number of pages based on file size (rough estimation)
      final int estimatedPages = _estimatePdfPageCount(pdfBytes);
      
      // Create image representations for each estimated page
      for (int pageIndex = 0; pageIndex < estimatedPages; pageIndex++) {
        final String imagePath = '${tempDir.path}/${baseName}_page_${pageIndex + 1}_$timestamp.jpg';
        final File imageFile = await _createPdfPageImage(
          pdfBytes, 
          imagePath, 
          pageIndex + 1, 
          estimatedPages
        );
        
        if (await imageFile.exists()) {
          imageFiles.add(imageFile);
        }
      }
      
      return imageFiles;
    } catch (e) {
      print('Error converting PDF to image files: $e');
      return await _createPdfFallbackRepresentation(pdfFile, tempDir);
    }
  }



  Future<File> _createPdfPageImage(
    Uint8List pdfBytes, 
    String imagePath, 
    int pageNumber, 
    int totalPages
  ) async {
    try {
      // Create a visual representation of the PDF page
      // Since we don't have PDF rendering capabilities, we'll create a placeholder image
      // that represents the PDF content
      
      // Create a simple PDF-like image using the pdf package
      final pw.Document imageDoc = pw.Document();
      
      imageDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Container(
              width: double.infinity,
              height: double.infinity,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 2),
                color: PdfColors.white,
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Icon(pw.IconData(0xe873), size: 100, color: PdfColors.grey600), // PDF icon
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'PDF Page $pageNumber',
                    style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'of $totalPages',
                    style: pw.TextStyle(fontSize: 16, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Container(
                    width: 200,
                    height: 100,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        'PDF Content\nPreview',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
      
      // Save as a temporary PDF first, then we'll treat it as an image
      final Uint8List imageBytes = await imageDoc.save();
      final File imageFile = File(imagePath);
      await imageFile.writeAsBytes(imageBytes);
      
      return imageFile;
    } catch (e) {
      print('Error creating PDF page image: $e');
      // Create a minimal file representation
      final File fallbackFile = File(imagePath);
      await fallbackFile.writeAsBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])); // Minimal JPEG header
      return fallbackFile;
    }
  }

  Future<List<File>> _createPdfFallbackRepresentation(File pdfFile, Directory tempDir) async {
    try {
      // Create a single fallback representation
      final String baseName = path.basenameWithoutExtension(pdfFile.path);
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final String fallbackPath = '${tempDir.path}/${baseName}_fallback_$timestamp.pdf';
      final File fallbackFile = File(fallbackPath);
      
      // Copy the original PDF as fallback
      final Uint8List originalBytes = await pdfFile.readAsBytes();
      await fallbackFile.writeAsBytes(originalBytes);
      
      return [fallbackFile];
    } catch (e) {
      print('Error creating fallback representation: $e');
      return [pdfFile]; // Return original file as last resort
    }
    }
  
  /// Handle AI Summarization button press
  Future<void> _handleAiSummarization() async {
    debugPrint('🤖 AI SUMMARIZATION BUTTON PRESSED');
    
    // Set loading state immediately to provide user feedback
    setState(() => _isAiProcessing = true);
    
          // Show a snackbar to inform user about expected wait time
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This apk works only with printed or typed text — handwriting is not supported for this version'),
          duration: Duration(seconds: 6),
          backgroundColor: Colors.blue,
        ),
      );
    
    try {
      // First check if model is downloaded
      debugPrint('🤖 Checking if model is downloaded...');
      final offlineGemmaService = _createOfflineGemmaService();
      final isModelDownloaded = await offlineGemmaService.isModelDownloaded();
      debugPrint('🤖 Model downloaded: $isModelDownloaded');
      
      if (!isModelDownloaded) {
        debugPrint('🤖 Model not downloaded, navigating to setup...');
        
        // Reset loading state before navigation
        setState(() => _isAiProcessing = false);
        
        // Navigate to AI setup screen
        final result = await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => _createAISetupScreen()),
        );
        
        if (result != true) {
          debugPrint('🤖 User cancelled setup');
          return; // User cancelled setup
        }
        
        // Set loading state again after successful setup
        setState(() => _isAiProcessing = true);
      }
      
      debugPrint('🤖 Proceeding with AI summarization...');
      // Proceed with AI summarization
      debugPrint('🤖 Proceeding with AI summarization...');
      await _generateAiSummary();
      
    } catch (e) {
      debugPrint('❌ AI PROCESSING FAILED: $e');
      if (mounted) {
        final errorMsg = e.toString();
        
        // Check if it's a corrupted model error
        if (errorMsg.contains('Model file is corrupted') || 
            errorMsg.contains('zip archive') ||
            errorMsg.contains('Unable to open zip') ||
            errorMsg.contains('incomplete') ||
            errorMsg.contains('malformed')) {
          
          _showCorruptedModelDialog();
        }
        // Check if it's a model initialization failure
        else if (errorMsg.contains('Model initialization failed') ||
                 errorMsg.contains('Failed to initialize') ||
                 errorMsg.contains('not initialized')) {
          
          _showModelInitializationFailedDialog();
        }
        // Check if it's a timeout error
        else if (errorMsg.contains('timed out') || errorMsg.contains('timeout')) {
          _showErrorDialog(
            'AI Processing Timeout', 
            'The AI processing took too long (${errorMsg.contains('30 minutes') ? '30+ minutes' : 'timeout'}).\n\n'
            'This can happen with:\n'
            '• Very large PDFs (100+ pages)\n'
            '• Complex document content\n'
            '• Extremely resource-intensive processing\n'
            '• Device limitations\n\n'
            'Try:\n'
            '• Split large PDFs into smaller parts\n'
            '• Restart the app to free memory\n'
            '• Use a more powerful device\n'
            '• Wait longer - some PDFs need 30+ minutes'
          );
        }
        // Check if it's a memory/token limit error
        else if (errorMsg.contains('token') && errorMsg.contains('cache')) {
          _showErrorDialog(
            'Device Memory Limitation', 
            'Your device doesn\'t have enough memory for this PDF.\n\n'
            'Try:\n'
            '• Use a smaller PDF (fewer pages)\n'
            '• Restart the app to free memory\n'
            '• Close other apps running in background\n'
            '• Split large PDFs into smaller parts'
          );
        }
        // Check for text extraction issues
        else if (errorMsg.contains('No readable text') || errorMsg.contains('too short')) {
          _showErrorDialog(
            'Text Extraction Issue', 
            'Cannot extract readable text from this PDF.\n\n'
            'This may happen if:\n'
            '• PDF contains mainly images/scans\n'
            '• PDF has complex formatting\n'
            '• PDF is password protected\n'
            '• PDF is corrupted\n\n'
            'Try:\n'
            '• Use a text-based PDF (not scanned images)\n'
            '• Check if PDF opens correctly in other apps\n'
            '• Use a different PDF for testing'
          );
        }
        // Generic error handling
        else {
          _showErrorDialog(
            'AI Summarization Failed', 
            'Could not generate AI summary.\n\n'
            'Error details: $errorMsg\n\n'
            'This may happen if:\n'
            '• AI model initialization failed\n'
            '• PDF content is not suitable for summarization\n'
            '• Device ran out of memory\n'
            '• Unexpected system error\n\n'
            'Try:\n'
            '• Restart the app\n'
            '• Use a different PDF\n'
            '• Check device storage space'
          );
        }
      }
    } finally {
      // CRITICAL: Always reset loading state
      if (mounted) {
        debugPrint('🤖 Resetting AI processing state to false');
        setState(() => _isAiProcessing = false);
      }
    }
  }
  
  /// Generate AI summary of the PDF
  Future<void> _generateAiSummary() async {
    debugPrint('🤖 _generateAiSummary() called');
    // NOTE: All try/catch is now handled by _handleAiSummarization
    
    debugPrint('🤖 Starting text extraction from PDF: ${widget.pdfPath}');
    
    // Extract text from PDF (skip cover page for better content focus)
    final textExtractionService = _createPdfTextExtractionService();
    final extractedText = await textExtractionService.extractTextFromPdf(
      widget.pdfPath, 
      skipCoverPage: true, // Skip cover page for AI summarization
    ).timeout(
      Duration(seconds: 30),
      onTimeout: () => throw Exception('PDF text extraction timed out after 30 seconds'),
    );
    
    debugPrint('🤖 Text extraction complete: ${extractedText.length} characters');
    
    if (extractedText.trim().isEmpty) {
      throw Exception('No readable text could be extracted from this PDF for summarization. The PDF may contain only images or be corrupted.');
    }
    
    if (extractedText.length < 50) {
      throw Exception('The extracted text is too short (${extractedText.length} characters) for meaningful summarization. The PDF may contain mainly images.');
    }
    
    debugPrint('🤖 Starting AI model summarization...');
    
    // Generate summary using Gemma
    final offlineGemmaService = _createOfflineGemmaService();
    final PdfSummary summary = await offlineGemmaService.summarizePdf(
      extractedText,
      type: SummaryType.comprehensive,
    ).timeout(
      const Duration(seconds: 900), // 15 minutes total timeout to accommodate slower devices
      onTimeout: () => throw Exception('AI summarization timed out after 900 seconds. The PDF might be too complex for this device.'),
    );
    
    debugPrint('🤖 AI summarization complete, showing results...');
    
    // Show summary
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => _createSummaryDisplayWidget(summary, widget.documentTitle),
        ),
      );
      debugPrint('🤖 Summary display closed');
    }
  }
  
  /// Create OfflineGemmaService instance
  OfflineGemmaService _createOfflineGemmaService() {
    return OfflineGemmaService();
  }
  
  /// Create Enhanced PdfTextExtractionService instance with OCR support
  EnhancedPdfTextExtractionService _createPdfTextExtractionService() {
    _textExtractionService ??= EnhancedPdfTextExtractionService();
    return _textExtractionService!;
  }
  
  @override
  void dispose() {
    _textExtractionService?.dispose();
    _fileNameController.dispose();
    super.dispose();
  }
  
  /// Create AI Setup Screen
  Widget _createAISetupScreen() {
    return AISetupScreen();
  }
  
  /// Create Summary Display Widget
  Widget _createSummaryDisplayWidget(PdfSummary summary, String title) {
    return SummaryDisplayWidget(
      summary: summary,
      documentTitle: title,
    );
  }
  
  /// Show error dialog
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
  
  /// Show corrupted model dialog with solution
  void _showCorruptedModelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_outlined, color: Colors.orange),
            SizedBox(width: 8),
            Text('AI Model Corrupted'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The AI model file appears to be corrupted or incomplete.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('This usually happens when:'),
            SizedBox(height: 8),
            Text('• Download was interrupted'),
            Text('• Storage space ran out during download'),
            Text('• File system corruption'),
            SizedBox(height: 16),
            Text(
              'Solution: Re-download the model (it will be deleted automatically)',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[700]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              // Navigate to AI setup screen to re-download
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => _createAISetupScreen()),
              );
            },
            icon: Icon(Icons.download),
            label: Text('Re-download Model'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Show model initialization failed dialog with solutions
  void _showModelInitializationFailedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('AI Model Failed to Start'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The AI model could not be initialized properly.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('This can happen when:'),
            SizedBox(height: 8),
            Text('• Device is low on memory'),
            Text('• Model file is partially corrupted'),
            Text('• First-time initialization on slow devices'),
            Text('• Background processes interfering'),
            SizedBox(height: 16),
            Text(
              'Try these solutions in order:',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[700]),
            ),
            SizedBox(height: 8),
            Text('1. Restart the app'),
            Text('2. Close other apps to free memory'),
            Text('3. Re-download the model if problem persists'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // Navigate to AI setup screen
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => _createAISetupScreen()),
              );
            },
            child: Text('Re-download Model'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              // Show restart app guidance
              _showRestartAppDialog();
            },
            icon: Icon(Icons.refresh),
            label: Text('Restart App'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Show restart app dialog
  void _showRestartAppDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restart App'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 48, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'Please close and restart the app completely to free up memory and reinitialize the AI model.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              'Steps:\n1. Close the app from recent apps\n2. Wait 5 seconds\n3. Open the app again',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3B82F6), // Blue start
              Color(0xFF1D4ED8), // Blue end
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom app bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
          if (!_isEditMode) IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () => setState(() => _isEditMode = true),
            tooltip: 'Edit PDF',
          ),
          if (_isEditMode) IconButton(
                          icon: const Icon(Icons.check, color: Colors.white),
            onPressed: _regeneratePdfWithNewOrder,
            tooltip: 'Save changes',
          ),
          IconButton(
                          icon: const Icon(Icons.description_outlined, color: Colors.white),
                          onPressed: _editCoverPage,
                          tooltip: 'Edit Cover Page',
                        ),
                        // AI Summarization Robot Icon
                        IconButton(
                          icon: _isAiProcessing 
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.smart_toy, color: Colors.white),
                          onPressed: _isAiProcessing ? null : _handleAiSummarization,
                          tooltip: 'AI Summary',
                        ),
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _sharePdf,
            tooltip: 'Share PDF',
          ),
          IconButton(
                          icon: const Icon(Icons.save, color: Colors.white),
            onPressed: _savePdf,
            tooltip: 'Save PDF',
          ),
        ],
      ),
                  ],
                ),
              ),
              
              // Content area
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(25),
                      topRight: Radius.circular(25),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(25),
                      topRight: Radius.circular(25),
                    ),
                    child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isEditMode
              ? _buildEditModeView()
              : _buildPdfPreviewView(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _isEditMode ? FloatingActionButton(
        onPressed: _addNewPage,
        child: const Icon(Icons.add_photo_alternate),
        tooltip: 'Add pages - Take photos or select from ScanMate',
      ) : null,
    );
  }
  
  Widget _buildPdfPreviewView() {
    return Stack(
      children: [
        // Snowfall effect background
        _buildSnowfallEffect(),
        
        // PDF content
        Column(
      children: [
        Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
          child: PDFView(
            filePath: pdfFile.path,
            enableSwipe: true,
                    swipeHorizontal: false,
            autoSpacing: false,
            pageFling: false,
            pageSnap: true,
            defaultPage: _currentPage,
            fitPolicy: FitPolicy.WIDTH,
            preventLinkNavigation: false,
            onViewCreated: (PDFViewController controller) {
              // PDF view has been created
            },
            onRender: (pages) {
              setState(() {
                _totalPages = pages!;
              });
            },
            onPageChanged: (page, total) {
              setState(() {
                _currentPage = page!;
                _totalPages = total!;
              });
            },
            onError: (error) {
              print('Error loading PDF: $error');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error loading PDF: $error'),
                          backgroundColor: Colors.red,
                ),
              );
            },
            onPageError: (page, error) {
              print('Error loading page $page: $error');
            },
                  ),
                ),
          ),
        ),
        
        // Page indicator
        Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
              ),
            ],
          ),
              margin: const EdgeInsets.only(bottom: 20),
              child: Text(
                'Page ${_currentPage + 1} of $_totalPages',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSnowfallEffect() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.shade50.withOpacity(0.3),
            Colors.white.withOpacity(0.1),
          ],
        ),
      ),
      child: CustomPaint(
        painter: SnowfallPainter(),
        size: Size.infinite,
      ),
    );
  }
  
  Widget _buildEditModeView() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.tips_and_updates, color: Colors.orange, size: 16),
            SizedBox(width: 6),
            Text('Drag to reorder pages. Tap + to add pages',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _documentPageImages.isEmpty
            ? Center(
                  child: Text(
                    'No pages available to edit. Total document pages: ${_documentPages.length}',
                  ),
              )
            : ReorderableGridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.66, // slightly taller
                  ),
                  padding: const EdgeInsets.all(10),
                  dragWidgetBuilder: (index, child) {
                    return Transform.scale(
                      scale: 1.05,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    );
                  },
                itemCount: _documentPageImages.length,
                   itemBuilder: (context, index) {
                    return AnimatedContainer(
                    key: ValueKey(index),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.black.withOpacity(0.05),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(0),
                        child: Stack(
                    children: [
                            Positioned.fill(
                              child: Image.memory(
                                _documentPageImages[index],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[300],
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.error, color: Colors.red),
                                        SizedBox(height: 8),
                                        Text('Image Error', style: TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                  );
                                },
                        ),
                      ),
                      Positioned(
                              top: 6,
                              right: 6,
                        child: Material(
                                color: Colors.black.withOpacity(0.35),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () {
                              setState(() {
                                _documentPages.removeAt(index);
                                _documentPageImages.removeAt(index);
                              });
                            },
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(Icons.close, size: 18, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                            // Replace bottom label with a subtle top-left drag handle overlay
                            Positioned(
                              top: 0,
                              left: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                color: Colors.black.withOpacity(0.18),
                                child: const Icon(Icons.drag_indicator, size: 16, color: Colors.white70),
                        ),
                      ),
                             // Page number badge (bottom-right)
                             Positioned(
                               bottom: 6,
                               right: 6,
                               child: Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                 decoration: BoxDecoration(
                                   color: Colors.black.withOpacity(0.45),
                                   borderRadius: BorderRadius.circular(12),
                                 ),
                                 child: Text(
                                   'Page ${index + 1}',
                                   style: const TextStyle(
                                     color: Colors.white,
                                     fontSize: 12,
                                     fontWeight: FontWeight.w600,
                                   ),
                                 ),
                               ),
                             ),
                    ],
                        ),
                      ),
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final File movedPage = _documentPages.removeAt(oldIndex);
                    _documentPages.insert(newIndex, movedPage);
                    final Uint8List movedImage = _documentPageImages.removeAt(oldIndex);
                    _documentPageImages.insert(newIndex, movedImage);
                  });
                },
              ),
        ),
      ],
    );
  }

  Future<void> _sharePdf() async {
    try {
      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        text: widget.documentTitle,
      );
    } catch (e) {
      print('Error sharing PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share file: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _savePdf() async {
    // Show dialog to let user enter a custom filename
    final String? customFileName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save PDF'),
        content: TextField(
          controller: _fileNameController,
          decoration: const InputDecoration(
            labelText: 'File name',
            hintText: 'Enter file name (without .pdf)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final fileName = _fileNameController.text.trim();
              if (fileName.isNotEmpty) {
                _saveLastFileName(fileName);
                Navigator.pop(context, fileName);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a file name')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (customFileName == null || !mounted) return;

    try {
      final String fileName = '$customFileName.pdf';
      
      try {
        // Get the Downloads directory
        Directory? externalDir;
        if (Platform.isAndroid) {
          externalDir = Directory('/storage/emulated/0/Download');
          if (!await externalDir.exists()) {
            externalDir = await getExternalStorageDirectory();
          }
        } else {
          externalDir = await getApplicationDocumentsDirectory();
        }
      
        if (externalDir != null) {
          // Create ScanMate directory
          final scanMateDir = Directory('${externalDir.path}/ScanMate');
          if (!await scanMateDir.exists()) {
            await scanMateDir.create(recursive: true);
          }
      
          // Save the file
          final file = File('${scanMateDir.path}/$fileName');
          await pdfFile.copy(file.path);
          // After successful save, increment scan count for APK cap
          await _incrementUserScanCount();
          
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PDF saved to ${scanMateDir.path}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.purple,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              margin: const EdgeInsets.all(8),
              duration: const Duration(seconds: 6),
            ),
          );
      // Go back to Home
      Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
      } catch (directSaveError) {
        print('Direct save failed: $directSaveError');
      }

      // Fallback to FileSaver
      await FileSaver.instance.saveFile(
        name: fileName.split('.').first,
        bytes: await pdfFile.readAsBytes(),
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
      await _incrementUserScanCount();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PDF saved to Downloads folder',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.purple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(8),
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class SnowfallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    // Create a simple snowfall effect with dots
    final random = DateTime.now().millisecondsSinceEpoch % 1000;
    
    for (int i = 0; i < 30; i++) {
      final x = (i * 37 + random) % size.width.toInt();
      final y = (i * 23 + random * 2) % size.height.toInt();
      final radius = 1.0 + (i % 3);
      
      canvas.drawCircle(
        Offset(x.toDouble(), y.toDouble()),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
  } 