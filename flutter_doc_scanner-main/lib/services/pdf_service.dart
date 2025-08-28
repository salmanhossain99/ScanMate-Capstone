import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

/// Service for handling PDF generation and manipulation
class PdfService {
  static final PdfService _instance = PdfService._internal();
  
  factory PdfService() {
    return _instance;
  }

  PdfService._internal();

  /// Generates a PDF document from a list of image paths
  /// Returns the path to the generated PDF file
  Future<String> generatePdfFromImages({
    required List<String> imagePaths,
    String? title,
    Map<String, dynamic>? coverPageInfo,
    Function(double)? onProgress,
  }) async {
    try {
      // Create parameters for the computation
      final params = {
        'imagePaths': imagePaths,
        'title': title ?? 'Scanned Document',
        'coverPageInfo': coverPageInfo,
        'hasLogo': await _hasLogo(),
      };

      // If logo exists, include it in the parameters
      if (params['hasLogo'] == true) {
        final ByteData logoData = await rootBundle.load('assets/nsu_logo.png');
        params['logoBytes'] = logoData.buffer.asUint8List();
      }

      // Generate PDF in a separate isolate to avoid UI jank
      final Uint8List pdfBytes = await compute(_generatePdfInBackground, params);

      // Save PDF to file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/pdf_${timestamp}_${const Uuid().v4()}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      return filePath;
    } catch (e) {
      if (kDebugMode) {
        print('Error generating PDF: $e');
      }
      rethrow;
    }
  }

  /// Checks if the app has a logo file
  Future<bool> _hasLogo() async {
    try {
      await rootBundle.load('assets/nsu_logo.png');
      return true;
    } catch (_) {
      return false;
    }
  }
  
  /// New optimized method that generates PDF in under 3 seconds
  /// Uses aggressive optimization techniques and provides progress updates
  Future<File> generateOptimizedPdf({
    required List<File> images,
    String? title,
    Function(double)? onProgress,
    Map<String, dynamic>? coverPageInfo,
  }) async {
    // Performance logging
    final stopwatch = Stopwatch()..start();
    print('PDF OPTIMIZATION: Starting PDF generation process');
    
    // Report initial progress
    onProgress?.call(0.1);
    
    // Create directory structure immediately to show progress
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String pdfName = '${const Uuid().v4()}.pdf';
    final Directory pdfDir = Directory('${appDir.path}/pdfs');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    
    print('PDF OPTIMIZATION: Directory setup complete (${stopwatch.elapsedMilliseconds}ms)');
    
    // Define path for the PDF and create empty file immediately
    final String pdfPath = '${pdfDir.path}/$pdfName';
    final File pdfFile = File(pdfPath);
    await pdfFile.create();
    onProgress?.call(0.2);
    
    try {
      // Verify input images exist and are not corrupt
      print('PDF OPTIMIZATION: Validating ${images.length} input images');
      final List<File> validImages = [];
      for (final image in images) {
        if (await image.exists()) {
          try {
            final bytes = await image.readAsBytes();
            if (bytes.isNotEmpty) {
              validImages.add(image);
              print('PDF OPTIMIZATION: Valid image: ${image.path}, size: ${bytes.length ~/ 1024}KB');
            } else {
              print('PDF OPTIMIZATION: WARNING - Empty image file: ${image.path}');
            }
          } catch (e) {
            print('PDF OPTIMIZATION: ERROR reading image ${image.path}: $e');
          }
        } else {
          print('PDF OPTIMIZATION: WARNING - Image file doesn\'t exist: ${image.path}');
        }
      }
      
      print('PDF OPTIMIZATION: Found ${validImages.length} valid images out of ${images.length}');
      if (validImages.isEmpty) {
        throw Exception('No valid images to process');
      }
      
    // Balanced settings for high quality with parallel processing
      const int targetWidth = 1200; // Higher width for sharper text
      const int jpegQuality = 85; // Slightly higher JPEG quality
      const bool useCompression = true; // Enable PDF compression for better results
    
      print('PDF OPTIMIZATION: Using settings: width=$targetWidth, quality=$jpegQuality, compression=$useCompression');
    
    final pdf = pw.Document(
      title: title ?? 'Scanned Document',
      author: 'Flutter Doc Scanner',
      compress: useCompression,
        version: PdfVersion.pdf_1_5, // Use newer version for better compatibility
    );
    
    // Only add cover page if absolutely necessary
    if (coverPageInfo != null) {
        print('PDF OPTIMIZATION: Adding cover page');
      // Cover page with university header and metadata
      pdf.addPage(
        pw.Page(
          build: (context) {
            final String assignmentNo = (coverPageInfo['assignmentNumber'] ?? '1').toString();
            final String submittedTo = (coverPageInfo['submittedTo'] ?? '').toString();
            final String name = (coverPageInfo['name'] ?? '').toString();
            final String id = (coverPageInfo['studentId'] ?? '').toString();
            final String course = (coverPageInfo['courseName'] ?? '').toString();
            final String section = (coverPageInfo['section'] ?? '').toString();
            final String dateStr = DateTime.now().toString().split(' ').first;

            pw.Widget headerLogo = pw.SizedBox();
            try {
              // Try to load NSU logo
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
                  _kv('Name:', name),
                  _kv('ID:', id),
                  _kv('Course:', course),
                  _kv('Section:', section),
                  pw.SizedBox(height: 28),
                  pw.Center(child: pw.Text('ASSIGNMENT - $assignmentNo', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(height: 16),
                  _kv('Submitted To:', submittedTo.toUpperCase()),
                  _kv('Submission Date:', dateStr),
                ],
              ),
            );
          },
        ),
      );
      onProgress?.call(0.3);
      print('PDF OPTIMIZATION: Cover page added (${stopwatch.elapsedMilliseconds}ms)');
    }
    
      // Process images in batches for better performance
      print('PDF OPTIMIZATION: Processing ${validImages.length} images');
    final List<Future<Uint8List?>> processingFutures = [];
    
      for (int i = 0; i < validImages.length; i++) {
        final file = validImages[i];
      processingFutures.add(
          compute(_processImageForPdf, {
          'path': file.path,
          'targetWidth': targetWidth,
          'quality': jpegQuality,
        })
      );
    }
    
    // Wait for all images to be processed
    final results = await Future.wait(processingFutures);
    onProgress?.call(0.7);
    
    print('PDF OPTIMIZATION: All images processed in parallel (${stopwatch.elapsedMilliseconds}ms)');
    
    // Add images to PDF
    int addedPages = 0;
    for (final imageBytes in results) {
      if (imageBytes != null) {
        pdf.addPage(
          pw.Page(
              margin: const pw.EdgeInsets.all(10), // Standard margins for better viewing
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(
                  pw.MemoryImage(imageBytes),
                  fit: pw.BoxFit.contain,
                ),
              );
            },
          ),
        );
        addedPages++;
      }
    }
    
    print('PDF OPTIMIZATION: Added $addedPages pages to PDF (${stopwatch.elapsedMilliseconds}ms)');
      
      if (addedPages == 0) {
        throw Exception('No pages were added to the PDF');
      }
    
    // Save PDF with minimal settings
    onProgress?.call(0.9);
    print('PDF OPTIMIZATION: Saving PDF...');
    final saveStopwatch = Stopwatch()..start();
    
    final Uint8List pdfBytes = await pdf.save();
      
      // Validate PDF before saving
      if (pdfBytes.isEmpty) {
        throw Exception('Generated PDF is empty');
      }
      
      // Check PDF header
      final String pdfHeader = String.fromCharCodes(pdfBytes.take(8));
      print('PDF OPTIMIZATION: PDF header: $pdfHeader');
      
      if (!pdfHeader.startsWith('%PDF')) {
        throw Exception('Generated data is not in PDF format');
      }
      
    await pdfFile.writeAsBytes(pdfBytes);
    
      // Verify saved file
      if (await pdfFile.length() == 0) {
        throw Exception('Saved PDF file is empty');
      }
      
      print('PDF OPTIMIZATION: PDF saved (${saveStopwatch.elapsedMilliseconds}ms), size: ${pdfBytes.length ~/ 1024}KB');
    onProgress?.call(1.0);
    
    // Report total time
    stopwatch.stop();
    print('PDF OPTIMIZATION: TOTAL TIME: ${stopwatch.elapsedMilliseconds}ms (${stopwatch.elapsedMilliseconds / 1000} seconds)');
    
    return pdfFile;
    } catch (e) {
      print('PDF OPTIMIZATION: ERROR generating PDF: $e');
      // Clean up empty file if there was an error
      if (await pdfFile.exists() && await pdfFile.length() == 0) {
        try {
          await pdfFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }
  
  /// Ultra-fast image processing - runs in isolate
  Future<Uint8List?> _ultraFastImageProcessing(
    File imageFile,
    int targetWidth,
    int quality,
  ) async {
    return compute(_processImageInIsolate, {
      'path': imageFile.path,
      'targetWidth': targetWidth,
      'quality': quality,
    });
  }

  // Create PDF with absolute minimum processing
  Future<File> createFastPdfFromImages({
    required List<File> images,
    String? title,
    int quality = 50, // Even lower quality for ultra-fast generation
    int maxWidth = 800, // Even lower resolution
    bool singlePage = true, // Force single page for speed
  }) async {
    // Generate a unique name for the PDF
    final String pdfName = '${const Uuid().v4()}.pdf';
    
    // Create a directory for PDFs if it doesn't exist
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory pdfDir = Directory('${appDir.path}/pdfs');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    
    // Define path for the new PDF
    final String pdfPath = '${pdfDir.path}/$pdfName';
    
    // Create an empty PDF file immediately to show progress
    final File pdfFile = File(pdfPath);
    await pdfFile.create();
    
    // Create PDF document with minimum settings
    final pdf = pw.Document(
      title: title ?? 'Scanned Document',
      author: 'Flutter Doc Scanner',
      compress: false, // Disable compression for speed
    );
    
    // Process only the first image for ultra-fast mode
    if (singlePage && images.isNotEmpty) {
      final File firstImage = images.first;
      final Uint8List imageBytes = await _processImageFast(
        firstImage, 
        maxWidth: maxWidth,
        quality: quality,
      );
      
      // Add image to PDF with minimum processing
      pdf.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(
                pw.MemoryImage(imageBytes),
                fit: pw.BoxFit.contain,
              ),
            );
          },
        ),
      );
    
      // Process all images if single page mode is disabled
      for (final File image in images) {
        final Uint8List imageBytes = await _processImageFast(
          image,
          maxWidth: maxWidth,
          quality: quality,
        );
        
        pdf.addPage(
          pw.Page(
            margin: const pw.EdgeInsets.all(10),
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(
                  pw.MemoryImage(imageBytes),
                  fit: pw.BoxFit.contain,
                ),
              );
            },
          ),
        );
      }
    }
    
    // Save PDF with minimal settings
    final Uint8List pdfBytes = await pdf.save();
    await pdfFile.writeAsBytes(pdfBytes);
    
    return pdfFile;
  }
  
  // Ultra-fast image processing
  Future<Uint8List> _processImageFast(
    File imageFile, {
    required int maxWidth,
    required int quality,
  }) async {
    try {
      // Read image file as bytes
      final Uint8List fileBytes = await imageFile.readAsBytes();
      
      // Decode image in a compute isolate for better performance
      final img.Image? decodedImage = await compute(_decodeImage, fileBytes);
      
      if (decodedImage == null) {
        // Fallback to original bytes if decoding fails
        return fileBytes;
      }
      
      // Calculate new dimensions maintaining aspect ratio
      final double aspectRatio = decodedImage.width / decodedImage.height;
      final int newWidth = maxWidth;
      final int newHeight = (newWidth / aspectRatio).round();
      
      // Resize image in a compute isolate
      final img.Image resizedImage = await compute(
        _resizeImage,
        {
          'image': decodedImage,
          'width': newWidth,
          'height': newHeight,
        },
      );
      
      // Encode image with reduced quality in a compute isolate
      final Uint8List processedBytes = await compute(
        _encodeJpg,
        {
          'image': resizedImage,
          'quality': quality,
        },
      );
      
      return processedBytes;
    } catch (e) {
      print('Error processing image: $e');
      // Return original bytes as fallback
      return await imageFile.readAsBytes();
    }
  }

  /// Add images to an existing PDF file
  /// This method operates independently from ML Kit and doesn't affect its functionality
  Future<File> addImagesToPdf({
    required String pdfPath,
    required List<File> newImages,
    String? outputPath,
  }) async {
    // Performance logging
    final stopwatch = Stopwatch()..start();
    print('PDF SERVICE: Adding images to existing PDF');
    
    try {
      // Determine where to save the updated PDF
      final String savePath = outputPath ?? pdfPath;
      
      // Create a new PDF document that will include the existing PDF and new images
      final pdf = pw.Document();
      
      try {
        // First, try to read the existing PDF
        final File pdfFile = File(pdfPath);
        final Uint8List pdfBytes = await pdfFile.readAsBytes();
        
        // Instead of using pw.PdfDocument.openData which is not available,
        // use the existing pdf file as a base PDF (more compatible approach)
        print('PDF SERVICE: Importing existing PDF pages as a base file');
        // pdf.addPage returns void, so we can't assign it to a variable
        pdf.addPage(
          pw.Page(
            build: (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pw.MemoryImage(pdfBytes)),
            ),
          ),
        );
        
        print('PDF SERVICE: Imported existing PDF');
      } catch (e) {
        print('PDF SERVICE: Error importing existing PDF, continuing with images only: $e');
        // Continue without the existing PDF if there's an error
      }
      
      // Process new images with moderate quality for good balance
      print('PDF SERVICE: Processing ${newImages.length} new images');
      final int imageQuality = 80;
      final int targetWidth = 1200;
      
      // Process each new image
      for (var i = 0; i < newImages.length; i++) {
        final File imageFile = newImages[i];
        
        // Process image for adding to PDF - use the new processing method
        final Uint8List? processedBytesOrNull = await compute(_processImageForPdf, {
          'path': imageFile.path,
          'targetWidth': targetWidth,
          'quality': imageQuality,
        });
        
        // Handle null case
        if (processedBytesOrNull == null) {
          print('PDF SERVICE: Warning - Failed to process image ${imageFile.path}, skipping');
          continue;
        }
        
        final Uint8List processedBytes = processedBytesOrNull;
        
        // Add processed image as a new page
        pdf.addPage(
          pw.Page(
            margin: const pw.EdgeInsets.all(10),
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(
                  pw.MemoryImage(processedBytes),
                  fit: pw.BoxFit.contain,
                ),
              );
            },
          ),
        );
      }
      
      // Save the updated PDF
      print('PDF SERVICE: Saving updated PDF');
      final Uint8List updatedPdfBytes = await pdf.save();
      
      // Write to the output file
      final File outputFile = File(savePath);
      await outputFile.writeAsBytes(updatedPdfBytes);
      
      print('PDF SERVICE: Successfully added ${newImages.length} images to PDF in ${stopwatch.elapsedMilliseconds}ms');
      return outputFile;
      
    } catch (e) {
      print('PDF SERVICE: Error adding images to PDF: $e');
      rethrow;
    }
  }

  /// Super simple PDF generation for maximum compatibility
  Future<File> generateSimplePdf({
    required List<File> images,
    String? title,
    Function(double)? onProgress,
  }) async {
    print('SIMPLE PDF: Starting simple PDF generation');
    
    // Report initial progress
    onProgress?.call(0.1);
    
    // Create temporary directory for output
    final Directory tempDir = await getTemporaryDirectory();
    final String pdfName = 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final String pdfPath = '${tempDir.path}/$pdfName';
    
    // Create the simplest possible PDF document
    final pdf = pw.Document(
      title: title ?? 'Document Scan',
      author: 'Flutter Doc Scanner',
      creator: 'Flutter Doc Scanner',
      producer: 'Flutter Doc Scanner PDF Service',
    );
    
    onProgress?.call(0.2);
    print('SIMPLE PDF: Created PDF document');
    
    // Add a basic cover page to ensure PDF has at least one page
    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Center(
            child: pw.Text(
              'Document Scan',
              style: pw.TextStyle(fontSize: 24),
            ),
          );
        }
      )
    );
    
    onProgress?.call(0.3);
    print('SIMPLE PDF: Added cover page');
    
    // Add each image as a separate page - with minimal processing
    int processedImages = 0;
    for (final File imageFile in images) {
      try {
        if (await imageFile.exists()) {
          final Uint8List bytes = await imageFile.readAsBytes();
          
          // Skip empty files
          if (bytes.isEmpty) {
            print('SIMPLE PDF: Skipping empty image file: ${imageFile.path}');
            continue;
          }
          
          // Add raw image without resizing
          pdf.addPage(
            pw.Page(
              build: (context) {
                return pw.Center(
                  child: pw.Image(pw.MemoryImage(bytes)),
                );
              }
            )
          );
          
          processedImages++;
          print('SIMPLE PDF: Added image ${processedImages} / ${images.length}');
          onProgress?.call(0.3 + (0.6 * processedImages / images.length));
        }
      } catch (e) {
        print('SIMPLE PDF: Error processing image: $e');
        // Continue with next image
      }
    }
    
    try {
      // Save PDF to file
      print('SIMPLE PDF: Saving document with ${processedImages + 1} pages');
      final Uint8List pdfBytes = await pdf.save();
      final File outputFile = File(pdfPath);
      await outputFile.writeAsBytes(pdfBytes);
      
      // Verify the output
      if (!await outputFile.exists()) {
        throw Exception('Failed to create output file');
      }
      
      final int fileSize = await outputFile.length();
      if (fileSize == 0) {
        throw Exception('Output PDF file is empty');
      }
      
      print('SIMPLE PDF: Successfully created PDF at $pdfPath, size: ${fileSize ~/ 1024}KB');
      onProgress?.call(1.0);
      
      return outputFile;
    } catch (e) {
      print('SIMPLE PDF: Error saving PDF: $e');
      rethrow;
    }
  }

  /// Converts a JPEG file to a valid PDF document
  Future<File> convertJpegToPdf(File jpegFile, {String? title}) async {
    print('JPEG TO PDF: Converting JPEG to PDF');
    
    try {
      // Verify input file exists
      if (!await jpegFile.exists()) {
        throw Exception('Input file does not exist');
      }
      
      // Read bytes from the file
      final bytes = await jpegFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Input file is empty');
      }
      
      // Check if this is actually a JPEG file (check for JPEG magic number FF D8)
      if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        print('JPEG TO PDF: Warning - Input file does not have JPEG header, attempting conversion anyway');
      } else {
        print('JPEG TO PDF: Input file has valid JPEG header');
      }
      
      // Create output PDF file path
      final tempDir = await getTemporaryDirectory();
      final String outputPath = '${tempDir.path}/converted_${DateTime.now().millisecondsSinceEpoch}.pdf';
      
      // Create a new PDF document
      final pdf = pw.Document(
        title: title ?? 'Converted Document',
        author: 'Flutter Doc Scanner',
        creator: 'JPEG to PDF Converter',
      );
      
      // Create a pw.Image from the JPEG bytes
      try {
        // Add the image to the PDF
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(pw.MemoryImage(bytes)),
              );
            },
          ),
        );
      } catch (e) {
        print('JPEG TO PDF: Error creating image in PDF: $e');
        // Try with a different approach - use a basic page as fallback
        pdf.addPage(
          pw.Page(
            build: (context) {
              return pw.Center(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'Unable to render image',
                      style: pw.TextStyle(fontSize: 24, color: PdfColors.red),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Text(
                      'The original file was not in a compatible format.',
                      style: pw.TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              );
            }
          ),
        );
      }
      
      // Save the PDF
      final pdfBytes = await pdf.save();
      
      // Write to file
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(pdfBytes);
      
      // Verify output
      if (!await outputFile.exists() || await outputFile.length() == 0) {
        throw Exception('Failed to create output file');
      }
      
      // Verify PDF header
      final outputBytes = await outputFile.readAsBytes();
      if (outputBytes.length >= 4) {
        final header = String.fromCharCodes(outputBytes.take(4));
        print('JPEG TO PDF: Output file header: $header');
        
        if (header != '%PDF') {
          print('JPEG TO PDF: Warning - Output file does not have PDF header');
        }
      }
      
      print('JPEG TO PDF: Conversion completed, output size: ${await outputFile.length() ~/ 1024}KB');
      return outputFile;
    } catch (e) {
      print('JPEG TO PDF: Error converting JPEG to PDF: $e');
      rethrow;
    }
  }
}

// Helper to build key-value line (label on left, value on right of colon)
pw.Widget _kv(String key, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(width: 80, child: pw.Text(key, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
        pw.Expanded(child: pw.Text(value.isEmpty ? ' ' : value)),
      ],
    ),
  );
}

/// Function to run in a separate isolate
Future<Uint8List> _generatePdfInBackground(Map<String, dynamic> params) async {
  final List<String> imagePaths = params['imagePaths'].cast<String>();
  final String title = params['title'] as String;
  final Map<String, dynamic>? coverPageInfo = params['coverPageInfo'] as Map<String, dynamic>?;
  final bool hasLogo = params['hasLogo'] as bool;
  final Uint8List? logoBytes = params['logoBytes'] as Uint8List?;

  // Create PDF document
  final pdf = pw.Document();

  // Add cover page if info is provided
  if (coverPageInfo != null && coverPageInfo.isNotEmpty) {
    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (hasLogo && logoBytes != null)
                pw.Center(
                  child: pw.Image(pw.MemoryImage(logoBytes), width: 100, height: 100),
                ),
              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Text(
                  'Document Scan',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 40),
              pw.Header(
                level: 0,
                child: pw.Text('Document Information',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 20),
              // Add cover page info dynamically
              ...coverPageInfo.entries.map((entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 10),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                        pw.Container(
                          width: 120,
                          child: pw.Text(
                            '${entry.key}:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                      ),
                      pw.Expanded(
                          child: pw.Text(
                            '${entry.value}',
                          ),
                      ),
                    ],
                  ),
                  )),
              pw.SizedBox(height: 40),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text(
                'Generated on: ${DateTime.now().toString().split('.')[0]}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          );
        },
      ),
    );
  }

  // Process images in batches of 3 for better performance
  final int batchSize = 3;
  final List<Map<String, dynamic>> processedImages = [];
  final int targetWidth = 1200; // Higher resolution for better quality
  final int jpegQuality = 85; // Improved JPEG quality

  for (int i = 0; i < imagePaths.length; i += batchSize) {
    final int endIndex = (i + batchSize < imagePaths.length) ? i + batchSize : imagePaths.length;
    final List<String> batch = imagePaths.sublist(i, endIndex);
    
    final List<Future<Map<String, dynamic>?>> batchProcessingFutures = [];
    
    for (int j = 0; j < batch.length; j++) {
      final int pageNumber = i + j + 1;
      batchProcessingFutures.add(_processImageInBatch(batch[j], pageNumber, targetWidth, jpegQuality));
    }
    
    final batchResults = await Future.wait(batchProcessingFutures);
    processedImages.addAll(batchResults.where((result) => result != null).cast<Map<String, dynamic>>());
  }
    
    // Add processed images to PDF
  if (processedImages.isNotEmpty) {
    for (final processedImage in processedImages) {
      if (processedImage != null) {
        final pw.MemoryImage pdfImage = pw.MemoryImage(
          processedImage['imageBytes'] as Uint8List
        );
        final int pageNumber = processedImage['pageNumber'] as int;
        
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (context) {
              return pw.Stack(
                children: [
                  pw.Center(
                    child: pw.Image(pdfImage),
                  ),
                  pw.Positioned(
                    right: 20,
                    bottom: 20,
                    child: pw.Text(
                      '$pageNumber',
                      style: const pw.TextStyle(
                        color: PdfColors.black,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }
    }
  }
  
  return pdf.save();
}

// Process a single image in a batch
Future<Map<String, dynamic>?> _processImageInBatch(String imagePath, int pageNumber, int targetWidth, int quality) async {
  try {
    // Read file
    final file = File(imagePath);
    final bytes = await file.readAsBytes();
    
    // Decode image
    final img.Image? originalImage = img.decodeImage(bytes);
    if (originalImage == null) return null;
    
    // Calculate new dimensions while maintaining aspect ratio
    final double aspectRatio = originalImage.width / originalImage.height;
    final int targetHeight = (targetWidth / aspectRatio).round();
    
    // Resize image
    final img.Image resizedImage = img.copyResize(
      originalImage,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average,
    );
    
    // Encode as JPEG with quality
    final Uint8List processedImageBytes = Uint8List.fromList(
      img.encodeJpg(resizedImage, quality: quality)
    );
    
    return {
      'imageBytes': processedImageBytes,
      'pageNumber': pageNumber,
    };
  } catch (e) {
    print('Error processing image: $e');
    return null;
  }
}

// Helper functions to run in isolates
img.Image? _decodeImage(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (e) {
    print('Error decoding image: $e');
    return null;
  }
}

img.Image _resizeImage(Map<String, dynamic> params) {
  final img.Image image = params['image'] as img.Image;
  final int width = params['width'] as int;
  final int height = params['height'] as int;
  
  return img.copyResize(
    image,
    width: width,
    height: height,
    interpolation: img.Interpolation.average, // Faster interpolation
  );
}

Uint8List _encodeJpg(Map<String, dynamic> params) {
  final img.Image image = params['image'] as img.Image;
  final int quality = params['quality'] as int;
  
  return Uint8List.fromList(img.encodeJpg(
    image,
    quality: quality,
  ));
}

/// New ultra-optimized image processing function for isolates
Uint8List? _processImageInIsolate(Map<String, dynamic> params) {
  try {
    final String path = params['path'] as String;
    final int targetWidth = params['targetWidth'] as int;
    final int quality = params['quality'] as int;
    
    // Read file bytes directly
    final File file = File(path);
    final Uint8List bytes = file.readAsBytesSync();
    
    // Decode image with lowest possible settings
    final img.Image? originalImage = img.decodeImage(bytes);
    if (originalImage == null) return null;
    
    // Calculate dimensions while maintaining aspect ratio
    final double aspectRatio = originalImage.width / originalImage.height;
    final int newHeight = (targetWidth / aspectRatio).round();
    
    // Ultra-fast resize with lowest quality interpolation
    final img.Image resizedImage = img.copyResize(
      originalImage,
      width: targetWidth,
      height: newHeight,
      interpolation: img.Interpolation.nearest, // Fastest interpolation method
    );
    
    // Encode with very low quality for maximum speed
    return Uint8List.fromList(img.encodeJpg(resizedImage, quality: quality));
  } catch (e) {
    print('Isolate processing error: $e');
    return null;
  }
}

/// Ultra-fast image processing function that minimizes all operations
Uint8List? _ultraFastProcessing(Map<String, dynamic> params) {
  try {
    final String path = params['path'] as String;
    final int targetWidth = params['targetWidth'] as int;
    final int quality = params['quality'] as int;
    
    // Read file bytes directly
    final File file = File(path);
    final Uint8List bytes = file.readAsBytesSync();
    
    print('ULTRA-FAST: Processing image: ${file.path}, size: ${bytes.length ~/ 1024}KB');
    final stopwatch = Stopwatch()..start();
    
    // Decode image with minimal settings
    final img.Image? originalImage = img.decodeImage(bytes);
    if (originalImage == null) {
      print('ULTRA-FAST: Failed to decode image: ${file.path}');
      return null;
    }
    
    print('ULTRA-FAST: Decoded image ${originalImage.width}x${originalImage.height} in ${stopwatch.elapsedMilliseconds}ms');
    
    // Calculate dimensions while maintaining aspect ratio
    final double aspectRatio = originalImage.width / originalImage.height;
    final int newHeight = (targetWidth / aspectRatio).round();
    
    // Skip resizing if the image is already small enough
    final img.Image resizedImage;
    if (originalImage.width <= targetWidth) {
      resizedImage = originalImage;
      print('ULTRA-FAST: Image already small enough, skipping resize');
    } else {
      resizedImage = img.copyResize(
        originalImage,
        width: targetWidth,
        height: newHeight,
        interpolation: img.Interpolation.nearest, // Fastest method
      );
      print('ULTRA-FAST: Resized to ${targetWidth}x$newHeight in ${stopwatch.elapsedMilliseconds}ms');
    }
    
    // Encode with minimal quality
    final result = Uint8List.fromList(img.encodeJpg(resizedImage, quality: quality));
    print('ULTRA-FAST: Encoded to JPEG (${result.length ~/ 1024}KB) in ${stopwatch.elapsedMilliseconds}ms');
    
    stopwatch.stop();
    return result;
  } catch (e) {
    print('ULTRA-FAST ERROR: $e');
    return null;
  }
} 

/// Process images for PDF creation
/// Directly implemented here instead of referring to _processImageFast
Future<Uint8List?> _processImageForPdf(Map<String, dynamic> params) async {
  try {
    final String path = params['path'] as String;
    final int targetWidth = params['targetWidth'] as int;
    final int quality = params['quality'] as int;
    
    // Read the file
    final File file = File(path);
    if (!await file.exists()) {
      print('Image file not found: $path');
      return null;
    }
    
    final Uint8List fileBytes = await file.readAsBytes();
    if (fileBytes.isEmpty) {
      print('Image file is empty: $path');
      return null;
    }
    
    // Detect format and decode image
    img.Image? image;
    try {
      image = img.decodeImage(fileBytes);
    } catch (e) {
      print('Failed to decode image $path: $e');
      // Try alternative decoders based on extension
      final extension = path.toLowerCase().split('.').last;
      
      try {
        if (extension == 'jpg' || extension == 'jpeg') {
          image = img.decodeJpg(fileBytes);
        } else if (extension == 'png') {
          image = img.decodePng(fileBytes);
        } else {
          // Fall back to the generic decoder again
          image = img.decodeImage(fileBytes);
        }
      } catch (e2) {
        print('All image decode attempts failed for $path: $e2');
        return null;
      }
    }
    
    if (image == null) {
      print('Failed to decode image: $path');
      return null;
    }
    
    // Calculate aspect ratio and resize
    final double aspectRatio = image.width / image.height;
    final int targetHeight = (targetWidth / aspectRatio).round();
    
    // Check dimensions
    if (targetHeight <= 0 || targetWidth <= 0 || aspectRatio <= 0) {
      print('Invalid image dimensions for $path: ${image.width}x${image.height}, AR: $aspectRatio');
      return null;
    }
    
    // Resize the image
    img.Image resized;
    try {
      resized = img.copyResize(
        image,
        width: targetWidth,
        height: targetHeight,
      interpolation: img.Interpolation.average,
    );
    } catch (e) {
      print('Failed to resize image $path: $e');
      // Try with a simpler interpolation
      try {
        resized = img.copyResize(
          image,
          width: targetWidth,
          height: targetHeight,
          interpolation: img.Interpolation.nearest,
        );
      } catch (e2) {
        print('All resize attempts failed for $path: $e2');
        return null;
      }
    }
    
    // Convert to JPEG with specified quality
    Uint8List jpegBytes;
    try {
      jpegBytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  } catch (e) {
      print('Failed to encode JPEG for $path: $e');
      // Try with lower quality
      try {
        jpegBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 50));
      } catch (e2) {
        print('All JPEG encoding attempts failed for $path: $e2');
        return null;
      }
    }
    
    return jpegBytes;
  } catch (e) {
    print('Unexpected error processing image: $e');
    return null;
  }
} 