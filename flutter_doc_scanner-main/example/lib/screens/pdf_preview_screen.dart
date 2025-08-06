import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/services/pdf_service.dart';
import 'package:flutter_doc_scanner/widgets/progress_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_doc_scanner/screens/optimized_pdf_preview.dart'; // Import our enhanced PDF preview

class PdfPreviewScreen extends StatefulWidget {
  final List<String> imagePaths;
  final Map<String, dynamic>? coverPageInfo;

  const PdfPreviewScreen({
    Key? key,
    required this.imagePaths,
    this.coverPageInfo,
  }) : super(key: key);

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  final PdfService _pdfService = PdfService();
  String? _pdfPath;
  bool _isLoading = true;
  double _progress = 0.0;
  String _processingStage = "Preparing...";
  final Stopwatch _totalStopwatch = Stopwatch();
  
  @override
  void initState() {
    super.initState();
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    if (widget.imagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No images to generate PDF from')),
      );
      Navigator.pop(context);
      return;
    }

    _totalStopwatch.start();
    print('PDF_PREVIEW: Starting PDF generation, input images: ${widget.imagePaths.length}');
    
    setState(() {
      _isLoading = true;
      _progress = 0.0;
      _processingStage = "Preparing images...";
    });

    try {
      // Convert string paths to File objects and do a quick sanity check
      print('PDF_PREVIEW: Converting paths to file objects');
      final List<File> imageFiles = [];
      for (final imagePath in widget.imagePaths) {
        final file = File(imagePath);
        if (await file.exists()) {
          final size = await file.length();
          print('PDF_PREVIEW: Image file exists: $imagePath, size: ${size ~/ 1024}KB');
          imageFiles.add(file);
        } else {
          print('PDF_PREVIEW: Image file does not exist: $imagePath');
        }
      }
      
      print('PDF_PREVIEW: Converted ${imageFiles.length} valid files out of ${widget.imagePaths.length} paths');
      
      if (imageFiles.isEmpty) {
        throw Exception('No valid image files found');
      }
      
      // First try with the simple method
      print('PDF_PREVIEW: Trying simple PDF generation first');
      final processStartTime = DateTime.now();
      File pdfFile;
      
      try {
        pdfFile = await _pdfService.generateSimplePdf(
        images: imageFiles,
        title: 'Document Scan ${DateTime.now().toString().split('.')[0]}',
        onProgress: (progress) {
          setState(() {
            _progress = progress;
            if (progress < 0.2) {
              _processingStage = "Initializing...";
            } else if (progress < 0.4) {
              _processingStage = "Processing images...";
            } else if (progress < 0.7) {
              _processingStage = "Building PDF...";
            } else if (progress < 0.9) {
              _processingStage = "Finalizing...";
            } else {
              _processingStage = "Saving PDF...";
            }
          });
        },
      );
        print('PDF_PREVIEW: Simple PDF generation succeeded');
      } catch (e) {
        print('PDF_PREVIEW: Simple PDF generation failed: $e, falling back to optimized method');
        // Fall back to optimized method
        pdfFile = await _pdfService.generateOptimizedPdf(
          images: imageFiles,
          title: 'Document Scan ${DateTime.now().toString().split('.')[0]}',
          coverPageInfo: widget.coverPageInfo,
          onProgress: (progress) {
            setState(() {
              _progress = progress;
              if (progress < 0.2) {
                _processingStage = "Initializing fallback...";
              } else if (progress < 0.4) {
                _processingStage = "Processing images (fallback)...";
              } else if (progress < 0.7) {
                _processingStage = "Building PDF (fallback)...";
              } else if (progress < 0.9) {
                _processingStage = "Finalizing (fallback)...";
              } else {
                _processingStage = "Saving PDF (fallback)...";
              }
            });
          },
        );
      }
      
      final processEndTime = DateTime.now();
      final processDuration = processEndTime.difference(processStartTime);
      print('PDF_PREVIEW: PDF generation completed in ${processDuration.inMilliseconds}ms');
      
      setState(() {
        _pdfPath = pdfFile.path;
        _isLoading = false;
      });
      
      _totalStopwatch.stop();
      print('PDF_PREVIEW: Total UI flow completed in ${_totalStopwatch.elapsedMilliseconds}ms');
      
      // Calculate file size
      final pdfSize = await pdfFile.length();
      print('PDF_PREVIEW: Generated PDF size: ${pdfSize ~/ 1024}KB');
      
      // Verify that the file has a proper PDF header before navigating
      final pdfBytes = await pdfFile.readAsBytes();
      if (pdfBytes.length > 4) {
        final header = String.fromCharCodes(pdfBytes.take(4));
        print('PDF_PREVIEW: PDF header: $header');
        
        if (header != '%PDF') {
          throw Exception('Generated file does not have a valid PDF header');
        }
      } else {
        throw Exception('PDF file too small to be valid');
      }
      
      // Now navigate directly to our enhanced PDF preview instead of showing a static success screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OptimizedPdfPreview(
              pdfPath: pdfFile.path,
              documentTitle: 'Document Scan',
            ),
        ),
      );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      print('PDF_PREVIEW: Error generating PDF: $e');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Creating PDF'),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _processingStage,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  if (_progress > 0)
                  Text(
                      '${(_progress * 100).toInt()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Please wait while we optimize your document...',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                      ),
                    ],
                  ),
            )
          : const Center(child: CircularProgressIndicator()), // This should never show as we navigate away
    );
  }
} 