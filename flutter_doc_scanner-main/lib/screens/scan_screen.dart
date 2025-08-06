import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_doc_scanner/models/document.dart';
import 'package:flutter_doc_scanner/screens/optimized_pdf_preview.dart';
import 'package:flutter_doc_scanner/services/drive_service.dart';
import 'package:flutter_doc_scanner/services/pdf_service.dart';
import 'package:flutter_doc_scanner/widgets/progress_dialog.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isScanning = false;
  bool _isSaving = false;
  final _driveService = DriveService();
  final _pdfService = PdfService();
  final _docScanner = FlutterDocScanner();
  final List<DocumentPage> _pages = [];
  bool _saveToDrive = false;
  String? _lastScannedPdfPath;

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    
    try {
      // Use ML Kit for DIRECT PDF generation only
      final result = await _docScanner.getScannedDocumentAsPdf(
        page: 10, // Allow up to 10 pages
        maxResolution: 1800, // High resolution
        quality: 95, // High quality
      );
      
      if (result != null && result is Map<String, dynamic> && result.containsKey("pdfUri")) {
        // ML Kit returns a direct PDF - use it immediately with no extra processing
        final pdfUri = result["pdfUri"] as String;
        final pageCount = result["pageCount"] as int? ?? 1;
        
        print("Direct ML Kit PDF generated: $pdfUri (pages: $pageCount)");
        
        // Verify the PDF file exists
        final originalFile = File(pdfUri);
        if (!await originalFile.exists()) {
          throw Exception("Generated file not found at $pdfUri");
        }
        
        final fileSize = await originalFile.length();
        print("Generated file size: ${fileSize ~/ 1024}KB");
        
        if (fileSize == 0) {
          throw Exception("Generated file is empty");
        }
        
        // Read first few bytes to determine file type
        File pdfFile;
        bool isValidPdf = false;
        
        try {
          final bytes = await originalFile.openRead(0, 8).first;
          final header = bytes.length >= 4 ? String.fromCharCodes(bytes.take(4)) : "";
          print("File header: $header");
          
          if (header == "%PDF") {
            // File is already a valid PDF - use it directly
            print("File has valid PDF header - using directly");
            pdfFile = originalFile;
            isValidPdf = true;
          } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
            // File is a JPEG - convert it to PDF
            print("File has JPEG header - converting to PDF");
            
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const AlertDialog(
                title: Text('Processing Scan'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Converting scanned image to PDF...'),
                  ],
                ),
              ),
            );
            
            // Convert the JPEG to a valid PDF
            pdfFile = await _pdfService.convertJpegToPdf(
              originalFile, 
              title: 'Scanned Document',
            );
            
            // Close the dialog
            if (mounted) Navigator.of(context).pop();
            
            isValidPdf = true;
            print("Successfully converted JPEG to PDF: ${pdfFile.path}");
          } else {
            // Unknown format - try conversion anyway as last resort
            print("Unknown file format - attempting conversion anyway");
            pdfFile = await _pdfService.convertJpegToPdf(
              originalFile, 
              title: 'Scanned Document',
            );
            
            isValidPdf = true;
          }
        } catch (e) {
          print("Error analyzing or converting file: $e");
          // Just use the original file as fallback
          pdfFile = originalFile;
        }
        
        _lastScannedPdfPath = pdfFile.path;
        
        // Navigate directly to PDF preview
        if (mounted) {
    Navigator.of(context).push(
      MaterialPageRoute(
              builder: (context) => OptimizedPdfPreview(
                pdfPath: _lastScannedPdfPath!,
                documentTitle: 'Scanned Document',
        ),
      ),
    );
  }
      } else {
        throw Exception("ML Kit did not return a PDF. Please check your ML Kit configuration.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning document: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  // Process images from the native scanner - Simplified to avoid extra processing
  Future<void> _processScannedImage(File imageFile) async {
    try {
        final appDir = await getApplicationDocumentsDirectory();
        final uuid = const Uuid().v4();
      final pageNumber = _pages.length + 1;

        // Create scans directory if it doesn't exist
        final scanDir = Directory('${appDir.path}/scans');
        if (!await scanDir.exists()) {
          await scanDir.create(recursive: true);
        }

      // Save path for the image
        final imagePath = '${scanDir.path}/${uuid}_$pageNumber.jpg';

      // Just copy the file directly without any processing
      await imageFile.copy(imagePath);

      // Add to pages immediately
        setState(() {
          _pages.add(DocumentPage(
            path: imagePath,
            pageNumber: pageNumber,
          ));
        });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // Remove background processing since we're using ML Kit's PDF directly

  Future<void> _saveDocument() async {
    // If we have a directly scanned PDF from ML Kit, save that
    if (_lastScannedPdfPath != null) {
      setState(() => _isSaving = true);
      
      ProgressDialogUtils.showProgressDialog(
        context: context,
        title: 'Saving Document',
        message: _saveToDrive 
            ? 'Uploading to Google Drive...'
            : 'Saving document...',
      );

      try {
        final now = DateTime.now();
        final pdfFile = File(_lastScannedPdfPath!);
        
        Document document = Document(
          id: const Uuid().v4(),
          title: 'Scan ${DateFormat('yyyy-MM-dd HH:mm').format(now)}',
          pages: [], // PDF already contains all pages
          createdAt: now,
          pdfPath: _lastScannedPdfPath,
        );

        if (_saveToDrive) {
          // Upload PDF to Google Drive
          ProgressDialogUtils.updateProgress(
            progress: 0.5,
            message: 'Uploading PDF to Google Drive...',
          );
          
          final driveId = await _driveService.uploadFile(
            pdfFile,
            'Document_${DateFormat('yyyy-MM-dd_HHmm').format(now)}.pdf',
          );
          
          document = document.copyWith(
            driveId: driveId,
          );
        }
        
        ProgressDialogUtils.hideProgressDialog();

      if (mounted) {
          Navigator.pop(context, document);
      }
    } catch (e) {
        ProgressDialogUtils.hideProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving document: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
          setState(() => _isSaving = false);
        }
      }
      return;
  }

    // Original save method for legacy approach
    if (_pages.isEmpty) return;

    setState(() => _isSaving = true);
    
    ProgressDialogUtils.showProgressDialog(
      context: context,
      title: 'Saving Document',
      message: _saveToDrive 
          ? 'Uploading to Google Drive...'
          : 'Saving document...',
    );

    try {
      final now = DateTime.now();
      Document document = Document(
        id: const Uuid().v4(),
        title: 'Scan ${DateFormat('yyyy-MM-dd HH:mm').format(now)}',
        pages: List.from(_pages),
        createdAt: now,
      );

      if (_saveToDrive) {
        // Upload pages to Google Drive
        final updatedPages = <DocumentPage>[];
        for (int i = 0; i < _pages.length; i++) {
          final page = _pages[i];
          ProgressDialogUtils.updateProgress(
            progress: i / _pages.length,
            message: 'Uploading page ${i + 1} of ${_pages.length}',
          );
          
          final driveId = await _driveService.uploadFile(
            File(page.path),
            'Page ${page.pageNumber}.jpg',
          );
          updatedPages.add(DocumentPage(
            path: page.path,
            pageNumber: page.pageNumber,
            driveId: driveId,
          ));
        }

        // Create a folder in Drive and move files there
        ProgressDialogUtils.updateProgress(
          progress: 0.9,
          message: 'Creating folder in Google Drive...',
        );
        
        final driveFolderId = await _driveService.createFolder(document.title);
        for (int i = 0; i < updatedPages.length; i++) {
          final page = updatedPages[i];
          await _driveService.moveFile(page.driveId!, driveFolderId);
        }

        document = document.copyWith(
          pages: updatedPages,
          driveId: driveFolderId,
        );
      }
      
      ProgressDialogUtils.hideProgressDialog();

      if (mounted) {
        Navigator.pop(context, document);
      }
    } catch (e) {
      ProgressDialogUtils.hideProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving document: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Document'),
        actions: [
          if (_pages.isNotEmpty) ...[
            Switch(
              value: _saveToDrive,
              onChanged: (value) => setState(() => _saveToDrive = value),
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: () {
                // Show message that PDF is already generated when using ML Kit directly
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PDF is already generated with ML Kit scanner'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              tooltip: 'PDF Already Generated',
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isSaving ? null : _saveDocument,
              tooltip: 'Save Document',
            ),
          ],
        ],
      ),
      body: _pages.isEmpty
          ? _buildEmptyState()
          : _buildPageGrid(),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning || _isSaving ? null : _startScan,
        child: Icon(_isScanning ? Icons.hourglass_empty : Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.document_scanner,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No scanned pages yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the camera button below to start scanning',
            style: TextStyle(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
                ),
        ],
              ),
    );
  }

  Widget _buildPageGrid() {
    return GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                final page = _pages[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                      File(page.path),
                      fit: BoxFit.cover,
              ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                radius: 16,
                        child: Text(
                          page.pageNumber.toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
            Positioned(
              bottom: 8,
              right: 8,
              child: CircleAvatar(
                backgroundColor: Colors.black.withOpacity(0.6),
                radius: 16,
                child: IconButton(
                  icon: const Icon(Icons.delete, size: 16),
                  color: Colors.white,
                  onPressed: () => _deletePage(index),
                  tooltip: 'Delete page',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
        ],
        );
      },
    );
  }

  void _deletePage(int index) {
    setState(() {
      final deletedPage = _pages.removeAt(index);
      
      // Delete the file
      File(deletedPage.path).delete().catchError((error) {
        print('Error deleting file: $error');
      });
      
      // Renumber pages
      for (int i = 0; i < _pages.length; i++) {
        final page = _pages[i];
        if (page.pageNumber > deletedPage.pageNumber) {
          _pages[i] = DocumentPage(
            path: page.path,
            pageNumber: page.pageNumber - 1,
            driveId: page.driveId,
    );
        }
      }
    });
  }
} 