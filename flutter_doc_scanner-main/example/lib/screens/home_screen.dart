import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_doc_scanner/models/document.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_doc_scanner/services/pdf_service.dart';
import 'package:flutter_doc_scanner/services/enhanced_pdf_text_extraction_service.dart';
import 'package:flutter_doc_scanner/services/offline_gemma_service.dart';
import 'package:path/path.dart' as path;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'tutorial_screen.dart';
import 'settings_screen.dart';
import 'account_screen.dart';
import 'sign_in_screen.dart' as signin;

import '../providers/user_provider.dart';
// removed direct import; using alias above
import 'document_cover_page_screen.dart';
import '../main.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// AI Setup imports
import 'package:flutter_doc_scanner/screens/ai_setup_screen.dart';

// This needs to be a top-level function to be used with compute
Future<Uint8List> _generatePdfInBackground(Map<String, dynamic> params) async {
  final documents = params['documents'];
  final pdf = pw.Document();

  List<String> imagePaths = [];
  Map<String, dynamic>? coverPageInfo;
  List<dynamic> sourceDocuments = [];

  if (documents is Map<String, dynamic>) {
    // Case: Scan with Cover Page
    sourceDocuments = documents['documents'] as List<dynamic>? ?? [];
    coverPageInfo = documents['coverPage'] as Map<String, dynamic>?;
  } else if (documents is List) {
    // Case: Scan Document
    sourceDocuments = documents;
  }

  // Safely convert sourceDocuments to a list of path strings
  for (final doc in sourceDocuments) {
    if (doc is String) {
      imagePaths.add(doc);
    } else if (doc is Map) {
      // It's a map, let's find the path. The plugin seems to return the path as the only value.
      if (doc.values.isNotEmpty && doc.values.first is String) {
        imagePaths.add(doc.values.first);
      }
    }
  }

  // Add cover page if it exists
  if (coverPageInfo != null) {
    final coverInfo = coverPageInfo; // Create a local non-nullable variable
    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('Document Cover Page', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 40),
              pw.Text('Student Information', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Name: ${coverInfo['name']}'),
              pw.SizedBox(height: 10),
              pw.Text('Email: ${coverInfo['email']}'),
              pw.SizedBox(height: 10),
              pw.Text('Student ID: ${coverInfo['studentId']}'),
              pw.SizedBox(height: 10),
              pw.Text('Course: ${coverInfo['courseName']}'),
              pw.SizedBox(height: 40),
              pw.Text('Document Information', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Total Pages: ${imagePaths.length}'),
              pw.SizedBox(height: 10),
              pw.Text('Date: ${DateTime.now().toString().split('.')[0]}'),
            ],
          );
        },
      ),
    );
  }

  for (var imagePath in imagePaths) {
    try {
      final imageFile = File(imagePath);
      if (await imageFile.exists()) {
        final imageBytes = await imageFile.readAsBytes();
        final image = img.decodeImage(imageBytes);

        if (image != null) {
          // Resize image to a smaller width and lower quality for faster processing
          final resizedImage = img.copyResize(image, width: 600); // Reduced width
          final jpegBytes = img.encodeJpg(resizedImage, quality: 75); // Lowered quality
          final pdfImage = pw.MemoryImage(jpegBytes);

          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (context) {
                return pw.Center(
                  child: pw.Image(pdfImage),
                );
              },
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error processing image: $imagePath, error: $e');
      }
      continue;
    }
  }

  return pdf.save();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  dynamic _scannedDocuments;
  int _bottomNavIndex = 0;
  String? _lastSavedFilePath;
  final TextEditingController _searchController = TextEditingController();
  List<FileSystemEntity> _downloadedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadDownloadedFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDownloadedFiles() async {
    try {
      Directory? scanMateDir;
      if (Platform.isAndroid) {
        scanMateDir = Directory('/storage/emulated/0/Download/ScanMate');
        if (!await scanMateDir.exists()) {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            scanMateDir = Directory('${externalDir.path}/ScanMate');
          }
        }
      } else {
        final documentsDir = await getApplicationDocumentsDirectory();
        scanMateDir = Directory('${documentsDir.path}/ScanMate');
      }

      if (scanMateDir != null && await scanMateDir.exists()) {
        final files = await scanMateDir.list().toList();
        setState(() {
          _downloadedFiles = files.where((file) => 
            file is File && file.path.toLowerCase().endsWith('.pdf')).toList();
        });
      }
    } catch (e) {
      print('Error loading downloaded files: $e');
    }
  }
  
  /// Open AI Setup Screen for Gemma 3n model download and configuration
  Future<void> _openAISetup() async {
    try {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => AISetupScreen()),
      );
      
      if (result == true) {
        // AI setup completed successfully
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI is ready! Look for the robot icon in PDF preview.',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(8),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening AI setup: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _requestPermissions() async {
    // For Android 13+ (API level 33+)
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        // Request the new media permissions
        Map<Permission, PermissionStatus> statuses = await [
          Permission.photos,
          Permission.videos,
        ].request();
        
        return statuses.values.every((status) => status.isGranted);
      } else {
        // For Android 12 and below
        Map<Permission, PermissionStatus> statuses = await [
          Permission.storage,
        ].request();
        
        return statuses.values.every((status) => status.isGranted);
      }
    } else {
      // For iOS
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      return status.isGranted;
    }
  }

  Future<void> _saveImage(String imagePath) async {
    try {
      final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      await FileSaver.instance.saveFile(
        name: fileName,
        file: File(imagePath),
        ext: 'jpg',
        mimeType: MimeType.jpeg,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Image saved to Downloads folder',
                  style: GoogleFonts.poppins(color: Colors.white),
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareLastSavedFile() async {
    if (_lastSavedFilePath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No recently saved file to share'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await Share.shareXFiles(
        [XFile(_lastSavedFilePath!)],
        text: 'ScanMate Document',
        subject: 'Shared from ScanMate',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _savePDF(dynamic documents) async {
    try {
      if (!mounted) return;
      
      // Show an immediate, non-blocking notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(width: 20),
              Text("Creating PDF in the background...", style: GoogleFonts.poppins()),
            ],
          ),
          duration: const Duration(seconds: 5), // Keep it visible for a while
        ),
      );

      // Debug print to trace execution
      print('\n\n');
      print('======================================================');
      print('HOME SCREEN: USING OPTIMIZED PDF GENERATION');
      print('Documents to process: ${documents is List ? documents.length : "unknown"}');
      print('======================================================');
      print('\n\n');

      final stopwatch = Stopwatch()..start();
      
      // Convert string paths to File objects
      final List<File> imageFiles = [];
      if (documents is List) {
        for (final imagePath in documents) {
          if (imagePath is String) {
            final file = File(imagePath);
            if (await file.exists()) {
              imageFiles.add(file);
            }
          }
        }
      }
      
      // Use our optimized PDF service instead of compute
      final pdfService = PdfService();
      final File pdfFile = await pdfService.generateOptimizedPdf(
        images: imageFiles,
        title: 'Document Scan ${DateTime.now().toString().split('.')[0]}',
        onProgress: (progress) {
          print('HOME: PDF Progress: ${(progress * 100).toStringAsFixed(1)}%');
        },
      );
      
      final pdfBytes = await pdfFile.readAsBytes();
      
      print('\n\n');
      print('======================================================');
      print('HOME SCREEN: OPTIMIZED PDF GENERATION COMPLETED IN ${stopwatch.elapsedMilliseconds}ms');
      print('PDF SIZE: ${pdfBytes.length ~/ 1024}KB');
      print('======================================================');
      print('\n\n');

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'ScanMate_$timestamp.pdf';
      
      // Try the direct file saving approach first
      try {
        // Get the Downloads directory
        Directory? externalDir;
        if (Platform.isAndroid) {
          externalDir = Directory('/storage/emulated/0/Download');
          if (!await externalDir.exists()) {
            // Fallback to external storage directory
            externalDir = await getExternalStorageDirectory();
          }
        } else {
          externalDir = await getApplicationDocumentsDirectory();
        }
        
        if (externalDir != null) {
          // Create ScanMate directory if it doesn't exist
          final scanMateDir = Directory('${externalDir.path}/ScanMate');
          if (!await scanMateDir.exists()) {
            await scanMateDir.create(recursive: true);
          }
          
          // Save the file
          final file = File('${scanMateDir.path}/$fileName');
          await file.writeAsBytes(pdfBytes);
          
          // Store the file path for sharing later
          _lastSavedFilePath = file.path;
          
          if (!mounted) return;
          
          // Show success message with share option
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PDF saved to ${scanMateDir.path}',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'SHARE',
                textColor: Colors.white,
                onPressed: _shareLastSavedFile,
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
          
          setState(() {
            _scannedDocuments = documents;
          });
          return;
        }
      } catch (directSaveError) {
        print('Direct save failed: $directSaveError');
        // Fall back to FileSaver if direct save fails
      }

      // Fallback to FileSaver
      await FileSaver.instance.saveFile(
        name: fileName.split('.').first,
        bytes: pdfBytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );

      // Can't reliably get the file path when using FileSaver
      _lastSavedFilePath = null;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PDF saved to Downloads folder',
                  style: GoogleFonts.poppins(color: Colors.white),
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
      
      setState(() {
        _scannedDocuments = documents;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> scanDocument() async {
    // Enforce APK photo cap per email
    final user = Provider.of<UserProvider>(context, listen: false);
    final current = await user.getScanCount();
    final remaining = UserProvider.apkScanLimit - current;
    if (remaining <= 0) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Limit Reached'),
          content: Text('For this APK, your account has reached the ${UserProvider.apkScanLimit} photo limit. Please wait for the final product.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    if (!await _requestPermissions()) {
      return;
    }

    try {
      // Use ML Kit to return PDF directly for instant conversion
      final result = await FlutterDocScanner().getScannedDocumentAsPdf(page: remaining);
      if (result is Map && result['pdfUri'] is String) {
        final pdfPath = result['pdfUri'] as String;
        // Count pages and enforce remaining allowance BEFORE saving
        final tempPdf = File(pdfPath);
        int captured = 0;
        try {
          final doc = await pdfx.PdfDocument.openFile(tempPdf.path);
          captured = doc.pagesCount;
          await doc.close();
        } catch (_) {
          final bytesTmp = await tempPdf.readAsBytes();
          final content = String.fromCharCodes(bytesTmp);
          captured = RegExp(r'/Type\s*/Page\b').allMatches(content).length;
          if (captured <= 0) captured = 1;
        }
        if (captured > remaining) {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Limit Exceeded'),
              content: Text('Only $remaining more photo(s) allowed in this APK. Please rescan with fewer pages.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
            ),
          );
          return;
        }
        // Save the returned PDF directly to ScanMate folder
        final bytes = await tempPdf.readAsBytes();
        final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        final String fileName = 'ScanMate_$timestamp.pdf';

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
          final scanMateDir = Directory('${externalDir.path}/ScanMate');
          if (!await scanMateDir.exists()) {
            await scanMateDir.create(recursive: true);
          }
          final outFile = File('${scanMateDir.path}/$fileName');
          await outFile.writeAsBytes(bytes);
          _lastSavedFilePath = outFile.path;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('PDF saved to ${scanMateDir.path}')),
            );
          }
          await _loadDownloadedFiles();
          // Increment by number of pages captured (bounded by remaining)
          await user.incrementScanCountBy(captured);
        }
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error scanning document: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> scanWithCoverPage() async {
    // Enforce APK photo cap per email
    final user = Provider.of<UserProvider>(context, listen: false);
    final current = await user.getScanCount();
    int remaining = UserProvider.apkScanLimit - current;
    if (remaining <= 0) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Limit Reached'),
          content: Text('For this APK, your account has reached the ${UserProvider.apkScanLimit} photo limit. Please wait for the final product.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    if (!await _requestPermissions()) return;

    try {
      // Directly call getScanDocuments with remaining allowance
      final documentsList =
          await FlutterDocScanner().getScanDocuments(page: remaining);

      if (documentsList != null &&
          documentsList is List &&
          documentsList.isNotEmpty) {
        print('Documents scanned successfully: ${documentsList.length} pages');
        // Increment photo count now
        final toAdd = documentsList.length;
        await user.incrementScanCountBy(toAdd > remaining ? remaining : toAdd);
        if (!mounted) return;
        
        // Show cover page screen
        print('Navigating to cover page screen...');
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DocumentCoverPageScreen(
              scannedDocuments: documentsList,
            ),
          ),
        );
        print('Cover page result: $result');
        
        // The result is now returned from the preview screen after saving.
        if (result != null && result is Map) {
          // Update state to show the new document in the list
          setState(() {
            _scannedDocuments = result;
          });
        }
      } else {
        print('No documents were scanned or returned.');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No documents scanned. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on PlatformException catch (e) {
      print('Platform Exception: ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error scanning document: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      print('Unexpected error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Add this function to test PDF generation with our optimized method
  Future<void> _testOptimizedPdf() async {
    print('\n\n');
    print('======================================================');
    print('TEST: Starting optimized PDF generation test');
    print('======================================================');
    print('\n\n');
    
    try {
      // Show progress dialog first to give immediate feedback
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          title: Text('Testing PDF Generation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Processing files with optimized method...'),
            ],
          ),
        ),
      );

      // Use the sample image from assets - copy it multiple times to temp directory
      final ByteData data = await rootBundle.load('assets/nsu_logo.png');
      final List<File> imageFiles = [];
      final tempDir = await getTemporaryDirectory();
      
      // Create multiple copies of the image to simulate multiple page document
      final int numPages = 5;
      for (int i = 0; i < numPages; i++) {
        final String tempImagePath = '${tempDir.path}/test_image_$i.png';
        final File tempFile = File(tempImagePath);
        await tempFile.writeAsBytes(data.buffer.asUint8List());
        imageFiles.add(tempFile);
      }
      
      print('TEST: Created $numPages test image files');
      
      // Use the optimized PDF service
      final stopwatch = Stopwatch()..start();
      final pdfService = PdfService();
      
      final File pdfFile = await pdfService.generateOptimizedPdf(
        images: imageFiles,
        title: 'Test PDF',
        onProgress: (progress) {
          print('TEST: Progress: ${(progress * 100).toStringAsFixed(1)}%');
        },
      );
      
      // Close the dialog
      if (mounted) Navigator.of(context).pop();
      
      stopwatch.stop();
      final fileSize = await pdfFile.length();
      
      print('\n\n');
      print('======================================================');
      print('TEST: Optimized PDF generation completed in ${stopwatch.elapsedMilliseconds}ms');
      print('TEST: PDF file size: ${fileSize ~/ 1024}KB');
      print('TEST: PDF saved at: ${pdfFile.path}');
      print('======================================================');
      print('\n\n');
      
      // Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF generated in ${stopwatch.elapsedMilliseconds}ms'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'SHARE',
            textColor: Colors.white,
            onPressed: () {
              if (pdfFile.existsSync()) {
                _lastSavedFilePath = pdfFile.path;
                _shareLastSavedFile();
              }
            },
          ),
        ),
      );
      
      // Store the file path for sharing later
      _lastSavedFilePath = pdfFile.path;
      
    } catch (e) {
      print('TEST ERROR: $e');
      
      // Close dialog if showing
      if (mounted) Navigator.of(context).pop();
      
      // Show error message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openAISummarizeFromFile() async {
    try {
      if (!await _requestPermissions()) return;
      // Let user pick a PDF from ScanMate or any location
      dynamic picked = await FlutterDocScanner().pickPdfFromScanMate();
      String? pdfPath;
      if (picked is String && picked.toLowerCase().endsWith('.pdf')) {
        pdfPath = picked;
      } else if (picked is Map && picked['pdfUri'] is String) {
        pdfPath = picked['pdfUri'] as String;
      }
      if (pdfPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PDF selected')),
        );
        return;
      }
      // Extract text with OCR
      final extractor = EnhancedPdfTextExtractionService();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Extracting text...')),
      );
      final text = await extractor.extractTextFromPdf(pdfPath, skipCoverPage: true);
      // Summarize offline
      final summarizer = OfflineGemmaService();
      final summary = await summarizer.summarizePdf(text);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('AI Summary'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary.summary),
                const SizedBox(height: 12),
                const Text('Key Points', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...summary.keyPoints.map((e) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(e)),
                      ],
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI summarize failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildAppDrawer(context),
      body: Stack(
        children: [
          // Background
          _buildBackground(),

          // Main content
          SafeArea(
            child: Column(
              children: [
                // Header
                _buildHeader(),

                // Body
                Expanded(
                  child: _buildBody(),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingFooter(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildAppDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(radius: 24, child: Icon(Icons.person)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('ScanMate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('Your smart document assistant', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Account'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                _openSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Tutorial'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TutorialScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

 

  Widget _buildBackground() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) {
      return Column(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.27, 1.0],
                  colors: [
                    AppColors.gradientStart,
                    AppColors.gradientMiddle,
                    AppColors.gradientEnd,
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Container(color: Theme.of(context).scaffoldBackgroundColor),
          ),
        ],
      );
    }
    // Dark mode background plain
    return Container(color: const Color(0xFF0B0B0F));
  }

  Widget _buildBody() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 160),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.center,
                  child: _buildSearchBar(),
                ),
              ),

              const SizedBox(height: 20),

              // Recent files
              _buildRecentFilesSection(),

              const SizedBox(height: 100), // Space for footer
            ],
          ),
        ),
        // Positioned action buttons
        Positioned(
          top: 20,
          left: 12,
          right: 12,
          child: _buildMainActionButtons(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.logout, color: Colors.white, size: 24),
                onPressed: () async {
                  // Implement logout functionality
                  final userProvider = Provider.of<UserProvider>(context, listen: false);
                  await userProvider.signOut();
                  if (!mounted) return;
                  
                  // Navigate to sign in screen
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const signin.SignInScreen()),
                  );
                },
              ),
            ],
          ),
          Center(
            child: Image.asset(
              'assets/Scanmatelogo.png',
              height: 70,
              width: 70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainActionButtons() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 130,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0xFF6D28D9).withOpacity(0.35) : Colors.black.withOpacity(0.1),
            blurRadius: isDark ? 36 : 10,
            spreadRadius: isDark ? 1 : 0,
            offset: const Offset(0, 8),
          ),
        ],
        border: isDark ? Border.all(color: const Color(0xFF6D28D9).withOpacity(0.6), width: 1.2) : null,
        gradient: isDark
            ? LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.10),
                  Colors.white.withOpacity(0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Scan button
          _buildActionButton(
            label: 'Scan',
            color: const Color(0xFFFF6B47), // Orange
            icon: Icons.crop_free_outlined,
            onTap: scanDocument,
          ),
          
          // Cover button
          _buildActionButton(
            label: 'Cover',
            color: const Color(0xFFFF1744), // Pink/Red
            icon: Icons.shield_outlined,
            onTap: scanWithCoverPage,
          ),
          
          // AI button
          _buildActionButton(
            label: 'AI',
            color: isDark ? const Color(0xFF6D28D9) : const Color(0xFF2196F3),
            icon: Icons.smart_toy_outlined,
            onTap: _openAISummarizeFromFile,
          ),
          
          // Settings button
          _buildActionButton(
            label: 'Settings',
            color: isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFFF9800),
            icon: Icons.settings,
            onTap: () {
              _openSettings();
            },
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
                height: 1.2,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.2)),
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[50],
        boxShadow: [
          if (isDark)
            BoxShadow(
              color: const Color(0xFF6D28D9).withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          // Filter downloaded files based on search
          setState(() {
            // Implement search filtering
          });
        },
        decoration: InputDecoration(
          hintText: 'Search your documents',
          hintStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 20, color: isDark ? Colors.white70 : Colors.grey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          suffixIcon: const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildRecentFilesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Builder(builder: (context) {
                final bool isDark = Theme.of(context).brightness == Brightness.dark;
                return Text(
                  'Recent Files',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF6D28D9) : Colors.black87,
                  ),
                );
              }),
              Icon(Icons.arrow_forward, color: Colors.grey[600]),
            ],
          ),
        ),
        const SizedBox(height: 15),
        _downloadedFiles.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Text(
                    'No files found',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _downloadedFiles.length > 3 ? 3 : _downloadedFiles.length, // Limit to 3 items
                itemBuilder: (context, index) {
                  final file = _downloadedFiles[index] as File;
                  return _buildFileListItem(file);
                },
              ),
      ],
    );
  }
  
  Widget _buildFileListItem(File file) {
    final fileName = path.basename(file.path);
    final lastModified = file.lastModifiedSync();
    
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0xFF6D28D9).withOpacity(0.25) : Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.08)) : null,
        gradient: isDark
            ? LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.10),
                  Colors.white.withOpacity(0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 52,
            height: 68,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
          ),
          const SizedBox(width: 12),
          // Title and date in two lines max like reference
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName.replaceAll('.pdf', '').replaceAll('_', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black),
                ),
                const SizedBox(height: 6),
                Text(
                  '${lastModified.day.toString().padLeft(2, '0')}/${lastModified.month.toString().padLeft(2, '0')}/${lastModified.year}  ${lastModified.hour.toString().padLeft(2, '0')}:${lastModified.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share, size: 20),
            onPressed: () => _shareFile(file),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, size: 20),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) => _buildFileActionsSheet(file),
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildFileActionsSheet(File file) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Share'),
            onTap: () {
              Navigator.pop(context);
              _shareFile(file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _deleteFile(file);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(File file) {
    final fileName = path.basename(file.path);
    final fileSize = file.lengthSync();
    final fileSizeKB = (fileSize / 1024).round();
    final lastModified = file.lastModifiedSync();
    
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.picture_as_pdf,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              const Spacer(),
              PopupMenuButton(
                icon: const Icon(Icons.more_horiz, size: 18),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: const Text('Share'),
                    onTap: () => _shareFile(file),
                  ),
                  PopupMenuItem(
                    child: const Text('Delete'),
                    onTap: () => _deleteFile(file),
                      ),
                    ],
                  ),
            ],
                ),
          const SizedBox(height: 10),
                Text(
            fileName.length > 20 ? '${fileName.substring(0, 17)}...' : fileName,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
                ),
          const SizedBox(height: 5),
                Text(
            '${lastModified.day}/${lastModified.month}/${lastModified.year}  ${lastModified.hour.toString().padLeft(2, '0')}:${lastModified.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingFooter() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Bottom navigation bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left side toggle buttons
              Expanded(
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.06)
                        : const Color(0xFF0D062C),
                    borderRadius: BorderRadius.circular(16),
                    border: Theme.of(context).brightness == Brightness.dark
                        ? Border.all(color: Colors.white.withOpacity(0.08))
                        : null,
                    boxShadow: [
                      if (Theme.of(context).brightness == Brightness.dark)
                        BoxShadow(
                          color: const Color(0xFF6D28D9).withOpacity(0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildToggleButton(Icons.layers, 0, isSelected: _bottomNavIndex == 0),
                      _buildToggleButton(Icons.folder, 1, isSelected: _bottomNavIndex == 1),
                      _buildToggleButton(Icons.person, 2, isSelected: _bottomNavIndex == 2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Center scan button
        Container(
          height: 60,
          width: 60,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF6D28D9) : const Color(0xFF504AF2),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF6D28D9) : const Color(0xFF504AF2)).withOpacity(0.35),
                blurRadius: 10,
                spreadRadius: 2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 30),
            onPressed: scanDocument,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton(IconData icon, int index, {required bool isSelected}) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _bottomNavIndex = index;
        });
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isSelected
              ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF6D28D9) : const Color(0xFF504AF2))
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Future<void> _shareFile(File file) async {
    try {
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      print('Error sharing file: $e');
    }
  }

  Future<void> _deleteFile(File file) async {
    try {
      await file.delete();
      _loadDownloadedFiles(); // Refresh the list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File deleted successfully')),
        );
      }
    } catch (e) {
      print('Error deleting file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error deleting file')),
        );
      }
    }
  }

  Widget _buildIconButton({
    required BuildContext context,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required IconData fallbackIcon,
  }) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                fallbackIcon,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentFilesList() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    if (_scannedDocuments == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[850] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Center(
          child: Text(
            'No recent files',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.grey,
            ),
          ),
        ),
      );
    }
    
    // Mock data for recent files
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.picture_as_pdf, color: Colors.blue),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document_${index + 1}.pdf',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Modified: ${DateTime.now().toString().split('.')[0]}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert, color: isDarkMode ? Colors.white70 : Colors.grey),
                onPressed: () {},
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDownloadedFilesList() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Mock data for downloaded files
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 2,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.download_done, color: Colors.green),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Downloaded_${index + 1}.pdf',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Downloaded: ${DateTime.now().toString().split('.')[0]}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.share, color: isDarkMode ? Colors.white70 : Colors.grey),
                onPressed: () {},
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildBottomNavToggle(),
          FloatingActionButton(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            onPressed: scanDocument,
            child: const Icon(Icons.add),
          )
        ],
      ),
    );
  }

  Widget _buildBottomNavToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          _buildToggleItem(Icons.layers_outlined, 0),
          _buildToggleItem(Icons.person_outline, 1),
        ],
      ),
    );
  }

  Widget _buildToggleItem(IconData icon, int index) {
    final bool isSelected = _bottomNavIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _bottomNavIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.black : Colors.white,
        ),
      ),
    );
  }

}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const double gap = 28;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 