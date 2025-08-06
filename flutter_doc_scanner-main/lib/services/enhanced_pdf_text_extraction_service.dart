import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart' as pdf_lib;
import 'package:pdf/widgets.dart' as pw;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfx/pdfx.dart';
import 'package:image/image.dart' as img;
import 'package:collection/collection.dart';

class EnhancedPdfTextExtractionService {
  static final EnhancedPdfTextExtractionService _instance = EnhancedPdfTextExtractionService._internal();
  factory EnhancedPdfTextExtractionService() => _instance;
  EnhancedPdfTextExtractionService._internal();
  
  final TextRecognizer _textRecognizer = TextRecognizer();
  
  /// Extract text from PDF file for AI summarization with OCR support
  Future<String> extractTextFromPdf(String pdfPath, {bool skipCoverPage = false}) async {
    try {
      debugPrint('📄 ENHANCED TEXT EXTRACTION START: $pdfPath');
      
      final file = File(pdfPath);
      if (!await file.exists()) {
        throw Exception('PDF file not found: $pdfPath');
      }
      
      debugPrint('📄 Reading PDF bytes...');
      final pdfBytes = await file.readAsBytes().timeout(
        Duration(seconds: 30),
        onTimeout: () => throw Exception('Reading PDF file timed out after 30 seconds'),
      );
      debugPrint('📄 PDF bytes read: ${pdfBytes.length} bytes');
      
      // Step 1: Try basic PDF text extraction first (faster for text-based PDFs)
      debugPrint('📄 Step 1: Attempting basic text extraction...');
      String extractedText = await _extractTextFromPdfBytes(pdfBytes, skipCoverPage: skipCoverPage);
      debugPrint('📄 Basic extraction result: ${extractedText.length} characters');
      debugPrint('📄 Basic extraction preview: "${extractedText.length > 200 ? extractedText.substring(0, 200) + "..." : extractedText}"');
      
      // Check if extracted text looks like meaningful content or just metadata
      bool isMeaningfulContent = _isTextMeaningfulContent(extractedText);
      debugPrint('📄 Basic extraction meaningful content check: $isMeaningfulContent');
      
      // Step 2: If basic extraction yields little text, try enhanced patterns
      if (extractedText.trim().length < 200 || !isMeaningfulContent) {
        debugPrint('📄 Step 2: Basic extraction insufficient (${extractedText.length} chars, meaningful: $isMeaningfulContent), trying enhanced patterns...');
        String enhancedText = await _extractTextWithEnhancedPatterns(pdfBytes, skipCoverPage: skipCoverPage);
        debugPrint('📄 Enhanced extraction result: ${enhancedText.length} characters');
        
        // Use enhanced result if it's significantly better
        if (enhancedText.trim().length > extractedText.trim().length) {
          extractedText = enhancedText;
          debugPrint('📄 Using enhanced result as it\'s more comprehensive');
        }
      }
      
      // Check again if we have meaningful content
      bool hasMeaningfulContent = _isTextMeaningfulContent(extractedText);
      debugPrint('📄 After enhanced extraction meaningful content check: $hasMeaningfulContent');
      
      // Step 2.5: If still insufficient or not meaningful content, try OCR on PDF pages
      if (extractedText.trim().length < 200 || !hasMeaningfulContent) {
        debugPrint('📄 Step 2.5: Still insufficient text (${extractedText.length} chars, meaningful: $hasMeaningfulContent), trying OCR...');
        String ocrText = await _extractTextWithOCR(pdfBytes, skipCoverPage: skipCoverPage);
        debugPrint('📄 OCR extraction result: ${ocrText.length} characters');
        
        // Use OCR result if it's significantly better or if we have no meaningful content
        if (ocrText.trim().length > extractedText.trim().length || (!hasMeaningfulContent && ocrText.trim().length > 50)) {
          extractedText = ocrText;
          debugPrint('📄 Using OCR result as it\'s more comprehensive or meaningful');
        }
      }
      
      // Step 3: Final fallback to metadata if both methods fail
      if (extractedText.trim().length < 50) {
        debugPrint('📄 Step 3: Both methods failed, creating descriptive metadata...');
        extractedText = await _createDescriptiveText(pdfBytes, pdfPath);
      }
      
      // Clean and validate the extracted text
      final cleanedText = _cleanExtractedText(extractedText);
      
      debugPrint('📄 ENHANCED TEXT EXTRACTION COMPLETE: ${cleanedText.length} characters extracted');
      debugPrint('📄 FINAL RESULT PREVIEW: "${cleanedText.length > 300 ? cleanedText.substring(0, 300) + "..." : cleanedText}"');
      return cleanedText;
      
    } catch (e) {
      debugPrint('❌ ENHANCED TEXT EXTRACTION ERROR: $e');
      rethrow;
    }
  }
  
  /// Extract text using OCR from PDF pages
  Future<String> _extractTextWithOCR(Uint8List pdfBytes, {bool skipCoverPage = false}) async {
    try {
      debugPrint('🔍 Starting OCR text extraction...');
      
      // Convert PDF pages to images
      final pageImages = await _convertPdfToImages(pdfBytes);
      debugPrint('🔍 Converted PDF to ${pageImages.length} page images');
      
      if (pageImages.isEmpty) {
        debugPrint('🔍 No images extracted from PDF');
        return '';
      }
      
      List<String> pageTexts = [];
      // Determine starting page: skip cover only if there are at least 2 pages
      int startPage = (skipCoverPage && pageImages.length > 1) ? 1 : 0;
      
      // Process each page with OCR (limit to first 10 pages for performance)
      final pagesToProcess = pageImages.skip(startPage).take(10).toList();
      debugPrint('🔍 Processing ${pagesToProcess.length} pages with OCR...');
      
      for (int i = 0; i < pagesToProcess.length; i++) {
        try {
          final pageImageBytes = pagesToProcess[i];
          debugPrint('🔍 Processing page ${i + startPage + 1} with OCR...');
          
          // Create temporary file for the image
          final tempDir = await Directory.systemTemp.createTemp('pdf_ocr_');
          final imageFile = File('${tempDir.path}/page_${i}.png');
          await imageFile.writeAsBytes(pageImageBytes);
          
          // Perform OCR
          final inputImage = InputImage.fromFilePath(imageFile.path);
          final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
          
          final pageText = recognizedText.text.trim();
          if (pageText.isNotEmpty) {
            pageTexts.add(pageText);
            debugPrint('🔍 Page ${i + startPage + 1} OCR result: ${pageText.length} characters');
          }
          
          // Cleanup
          await tempDir.delete(recursive: true);
          
        } catch (pageError) {
          debugPrint('⚠️ OCR failed for page ${i + startPage + 1}: $pageError');
          continue;
        }
      }
      
      final combinedText = pageTexts.join('\n\n--- PAGE BREAK ---\n\n');
      debugPrint('🔍 OCR extraction complete: ${combinedText.length} total characters');
      
      return combinedText;
      
    } catch (e) {
      debugPrint('❌ OCR extraction failed: $e');
      return '';
    }
  }
  
  /// Convert PDF to images for OCR processing
  Future<List<Uint8List>> _convertPdfToImages(Uint8List pdfBytes) async {
    try {
      debugPrint('🖼️ Converting PDF pages to images...');
      debugPrint('🖼️ PDF byte size: ${pdfBytes.length} bytes');
      
      List<Uint8List> images = [];
      
      // Validate PDF bytes first
      if (pdfBytes.length < 100) {
        debugPrint('❌ PDF bytes too small (${pdfBytes.length} bytes), likely corrupted');
        return _extractEmbeddedImages(pdfBytes);
      }
      
      // Check for PDF header
      final pdfHeader = String.fromCharCodes(pdfBytes.take(10));
      debugPrint('🖼️ PDF header: "$pdfHeader"');
      if (!pdfHeader.startsWith('%PDF-')) {
        debugPrint('❌ Invalid PDF header, attempting fallback extraction');
        return _extractEmbeddedImages(pdfBytes);
      }
      
      // Use pdfx to convert PDF pages to images
      debugPrint('🖼️ Opening PDF document with pdfx...');
      PdfDocument? document;
      try {
        document = await PdfDocument.openData(pdfBytes);
        debugPrint('🖼️ PDF document opened successfully with pdfx');
      } catch (openError) {
        debugPrint('❌ Failed to open PDF with pdfx: $openError');
        debugPrint('🖼️ Attempting fallback extraction...');
        return _extractEmbeddedImages(pdfBytes);
      }
      
      final pageCount = document.pagesCount;
      debugPrint('🖼️ PDF has $pageCount pages');
      
      if (pageCount == 0) {
        debugPrint('❌ PDF reports 0 pages - possible pdfx compatibility issue');
        debugPrint('🔧 Attempting to force-render page 1 anyway...');
        
        // Try to access page 1 even if pageCount is 0 (some PDFs have this issue)
        try {
          final page = await document.getPage(1);
          debugPrint('✅ Successfully accessed page 1 despite 0 page count!');
          debugPrint('🖼️ Page dimensions: ${page.width}x${page.height}');
          
          // Render the page
          final pageImage = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: PdfPageImageFormat.png,
          );
          
          page.close();
          
          if (pageImage != null && pageImage.bytes.isNotEmpty) {
            images.add(pageImage.bytes);
            debugPrint('🖼️ Successfully extracted image from forced page 1: ${pageImage.bytes.length} bytes');
            document.close();
            return images;
          }
        } catch (forcedPageError) {
          debugPrint('❌ Could not force-access page 1: $forcedPageError');
        }
        
        debugPrint('🖼️ All page access attempts failed, trying fallback extraction');
        document.close();
        return _extractEmbeddedImages(pdfBytes);
      }
      
      // Convert each page to image (limit to 10 pages for performance)
      final pagesToProcess = pageCount > 10 ? 10 : pageCount;
      debugPrint('🖼️ Processing $pagesToProcess pages...');
      
      for (int pageIndex = 1; pageIndex <= pagesToProcess; pageIndex++) {
        try {
          debugPrint('🖼️ Converting page $pageIndex to image...');
          
          final page = await document.getPage(pageIndex);
          debugPrint('🖼️ Page $pageIndex opened, dimensions: ${page.width}x${page.height}');
          
          // Render page to image with good quality for OCR
          final pageImage = await page.render(
            width: page.width * 2, // 2x resolution for better OCR
            height: page.height * 2,
            format: PdfPageImageFormat.png,
          );
          
          page.close();
          
          if (pageImage != null && pageImage.bytes.isNotEmpty) {
            images.add(pageImage.bytes);
            debugPrint('🖼️ Page $pageIndex converted: ${pageImage.bytes.length} bytes');
          } else {
            debugPrint('⚠️ Page $pageIndex rendered but no image data received');
          }
          
        } catch (pageError) {
          debugPrint('⚠️ Failed to convert page $pageIndex: $pageError');
          continue;
        }
      }
      
      document.close();
      
      debugPrint('🖼️ Successfully converted ${images.length} pages to images');
      
      // If no images were extracted, try fallback method
      if (images.isEmpty) {
        debugPrint('🖼️ No images extracted via pdfx, trying fallback method...');
        return _extractEmbeddedImages(pdfBytes);
      }
      
      return images;
      
    } catch (e) {
      debugPrint('❌ PDF to image conversion failed: $e');
      debugPrint('📱 Stack trace: ${StackTrace.current}');
      
      // Fallback: Try to extract embedded images from PDF
      return _extractEmbeddedImages(pdfBytes);
    }
  }
  

  /// Fallback method to extract embedded images from PDF (binary scanning as well)
  Future<List<Uint8List>> _extractEmbeddedImages(Uint8List pdfBytes) async {
    try {
      debugPrint('🖼️ Fallback: Extracting embedded images from PDF...');
      debugPrint('🖼️ Analyzing PDF structure for embedded images...');
      
      List<Uint8List> images = [];
      
      // Try multiple approaches to find images in PDF
      
      // Approach 0: Binary scan for common image formats (JPEG/PNG) inside the PDF bytes
      await _extractImagesByBinaryScan(pdfBytes, images);
      
      // Approach 1: Look for JPEG/DCT encoded images using regex on string representation
      await _extractDCTImages(pdfBytes, images);
      
      // Approach 2: Look for PNG/FlateDecode images using regex  
      await _extractFlateDecodeImages(pdfBytes, images);
      
      // Approach 3: Look for direct image objects (XObject) via regex
      await _extractDirectImageObjects(pdfBytes, images);
      
      // Approach 4: Try to extract raw image streams with better header detection via regex + heuristics
      await _extractRawImageStreams(pdfBytes, images);
      
      debugPrint('🖼️ Extracted ${images.length} embedded images from PDF');
      
      // If still no images found, create a placeholder image for OCR testing
      if (images.isEmpty) {
        debugPrint('🖼️ No embedded images found, creating placeholder for testing...');
        final placeholderImage = await _createPlaceholderImage();
        if (placeholderImage != null) {
          images.add(placeholderImage);
          debugPrint('🖼️ Created placeholder image: ${placeholderImage.length} bytes');
        }
      }
      
      return images;
      
    } catch (e) {
      debugPrint('❌ Embedded image extraction failed: $e');
      return [];
    }
  }
  
  /// Extract images by scanning for common binary signatures (JPEG, PNG) directly in the byte array
  Future<void> _extractImagesByBinaryScan(Uint8List pdfBytes, List<Uint8List> images) async {
    try {
      debugPrint('🖼️ Binary scan: looking for embedded JPEG/PNG signatures');
      const jpegStart = [0xFF, 0xD8];
      const jpegEnd = [0xFF, 0xD9];
      const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      const pngIend = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82];

      int index = 0;
      while (index < pdfBytes.length - 2) {
        // JPEG detection
        if (pdfBytes[index] == jpegStart[0] && pdfBytes[index + 1] == jpegStart[1]) {
          int start = index;
          // search for end marker
          int end = start + 2;
          while (end < pdfBytes.length - 1) {
            if (pdfBytes[end] == jpegEnd[0] && pdfBytes[end + 1] == jpegEnd[1]) {
              end += 2; // include end marker
              break;
            }
            end++;
          }
          if (end - start > 100) {
            final imgBytes = pdfBytes.sublist(start, end);
            images.add(Uint8List.fromList(imgBytes));
            debugPrint('🖼️ Binary scan extracted JPEG (${imgBytes.length} bytes)');
          }
          index = end;
          continue;
        }

        // PNG detection
        if (index < pdfBytes.length - 8 && ListEquality().equals(pdfBytes.sublist(index, index + 8), pngSignature)) {
          int start = index;
          // search for IEND chunk ( we look for bytes pattern )
          int end = start + 8;
          while (end < pdfBytes.length - 8) {
            if (ListEquality().equals(pdfBytes.sublist(end, end + 8), pngIend)) {
              end += 8; // include IEND
              break;
            }
            end++;
          }
          if (end - start > 100) {
            final imgBytes = pdfBytes.sublist(start, end);
            images.add(Uint8List.fromList(imgBytes));
            debugPrint('🖼️ Binary scan extracted PNG (${imgBytes.length} bytes)');
          }
          index = end;
          continue;
        }
        index++;
      }
    } catch (e) {
      debugPrint('⚠️ Binary scan image extraction failed: $e');
    }
  }

  /// Extract DCT/JPEG encoded images from PDF
  Future<void> _extractDCTImages(Uint8List pdfBytes, List<Uint8List> images) async {
    try {
      final pdfString = String.fromCharCodes(pdfBytes);
      
      // Look for JPEG images in PDF streams
      final jpegMatches = RegExp(r'/Filter\s*/DCTDecode.*?stream\s*(.*?)\s*endstream', dotAll: true).allMatches(pdfString);
      
      debugPrint('🖼️ Found ${jpegMatches.length} potential DCT/JPEG images');
      
      for (final match in jpegMatches.take(10)) {
        try {
          final imageData = match.group(1) ?? '';
          if (imageData.isNotEmpty && imageData.length > 100) {
            // Try to extract JPEG data more carefully
            final cleanImageData = imageData.trim();
            final bytes = cleanImageData.codeUnits.where((byte) => byte <= 255).toList();
            
            if (bytes.length > 100) { // Reasonable minimum for an image
              final imageBytes = Uint8List.fromList(bytes);
              
              // Basic validation: check for JPEG markers
              if (bytes.length > 10 && 
                  ((bytes[0] == 0xFF && bytes[1] == 0xD8) || // JPEG start
                   cleanImageData.contains('JFIF') || 
                   cleanImageData.contains('Exif'))) {
                images.add(imageBytes);
                debugPrint('🖼️ Extracted DCT image: ${imageBytes.length} bytes');
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ Failed to extract DCT image: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ DCT image extraction failed: $e');
    }
  }
  
  /// Extract FlateDecode/PNG images from PDF
  Future<void> _extractFlateDecodeImages(Uint8List pdfBytes, List<Uint8List> images) async {
    try {
      final pdfString = String.fromCharCodes(pdfBytes);
      
      // Look for FlateDecode images (PNG-like)
      final flateMatches = RegExp(r'/Filter\s*/FlateDecode.*?/Width\s*(\d+).*?/Height\s*(\d+).*?stream\s*(.*?)\s*endstream', dotAll: true).allMatches(pdfString);
      
      debugPrint('🖼️ Found ${flateMatches.length} potential FlateDecode images');
      
      for (final match in flateMatches.take(5)) {
        try {
          final widthStr = match.group(1) ?? '';
          final heightStr = match.group(2) ?? '';
          final imageData = match.group(3) ?? '';
          
          final width = int.tryParse(widthStr);
          final height = int.tryParse(heightStr);
          
          if (width != null && height != null && imageData.isNotEmpty && width > 50 && height > 50) {
            debugPrint('🖼️ Found FlateDecode image: ${width}x${height}');
            // For now, skip complex decompression but log the find
            // In a full implementation, you'd decompress the FlateDecode stream
          }
        } catch (e) {
          debugPrint('⚠️ Failed to process FlateDecode image: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ FlateDecode image extraction failed: $e');
    }
  }
  
  /// Extract direct image objects from PDF
  Future<void> _extractDirectImageObjects(Uint8List pdfBytes, List<Uint8List> images) async {
    try {
      final pdfString = String.fromCharCodes(pdfBytes);
      
      // Look for XObject Images
      final imageObjMatches = RegExp(r'/Type\s*/XObject\s*/Subtype\s*/Image.*?stream\s*(.*?)\s*endstream', dotAll: true).allMatches(pdfString);
      
      debugPrint('🖼️ Found ${imageObjMatches.length} potential XObject images');
      
      for (final match in imageObjMatches.take(5)) {
        try {
          final imageData = match.group(1) ?? '';
          if (imageData.isNotEmpty && imageData.length > 100) {
            final bytes = imageData.codeUnits.where((byte) => byte <= 255).toList();
            if (bytes.length > 100) {
              images.add(Uint8List.fromList(bytes));
              debugPrint('🖼️ Extracted XObject image: ${bytes.length} bytes');
            }
          }
        } catch (e) {
          debugPrint('⚠️ Failed to extract XObject image: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ XObject image extraction failed: $e');
    }
  }
  
  /// Create a placeholder image for testing OCR when no images are found
  Future<Uint8List?> _createPlaceholderImage() async {
    try {
      // Create a simple PNG image with text indicating it's a placeholder
      final image = img.Image(width: 800, height: 600);
      img.fill(image, color: img.ColorRgb8(255, 255, 255)); // White background
      
      // Add a border
      img.drawRect(image, 
        x1: 10, y1: 10, x2: 790, y2: 590,
        color: img.ColorRgb8(200, 200, 200),
        thickness: 2);
      
      // Add text indicating this is a placeholder for testing
      final font = img.arial14;
      img.drawString(image, 'PDF Content Could Not Be Rendered',
        font: font,
        x: 50,
        y: 50,
        color: img.ColorRgb8(100, 100, 100));
        
      img.drawString(image, 'This is a placeholder for OCR testing.',
        font: font,
        x: 50,
        y: 80,
        color: img.ColorRgb8(100, 100, 100));
        
      img.drawString(image, 'The original PDF may contain scanned content',
        font: font,
        x: 50,
        y: 110,
        color: img.ColorRgb8(100, 100, 100));
        
      img.drawString(image, 'that requires alternative processing methods.',
        font: font,
        x: 50,
        y: 140,
        color: img.ColorRgb8(100, 100, 100));
      
      return img.encodePng(image);
    } catch (e) {
      debugPrint('⚠️ Failed to create placeholder image: $e');
      return null;
    }
  }
  
  /// Extract text using enhanced pattern matching
  Future<String> _extractTextWithEnhancedPatterns(Uint8List pdfBytes, {bool skipCoverPage = false}) async {
    try {
      debugPrint('🔍 Starting enhanced pattern text extraction...');
      
      final pdfString = String.fromCharCodes(pdfBytes);
      final extractedParts = <String>[];
      
      // Enhanced Method 1: Look for more text patterns in PDF structure
      debugPrint('🔍 Method 1: Looking for additional text patterns...');
      
      // Pattern 1: Text in form fields
      final formFieldMatches = RegExp(r'/V\s*\(([^)]+)\)').allMatches(pdfString);
      for (final match in formFieldMatches.take(50)) {
        final text = match.group(1) ?? '';
        if (text.isNotEmpty && text.length > 2) {
          final decodedText = _decodePdfText(text);
          if (decodedText.trim().isNotEmpty) {
            extractedParts.add(decodedText);
          }
        }
      }
      
      // Pattern 2: Content in XObject forms
      final xObjectMatches = RegExp(r'/Subtype\s*/Form.*?stream\s*(.*?)\s*endstream', dotAll: true).allMatches(pdfString);
      for (final match in xObjectMatches.take(20)) {
        final content = match.group(1) ?? '';
        final textMatches = RegExp(r'\(([^)]+)\)\s*Tj').allMatches(content);
        for (final textMatch in textMatches.take(30)) {
          final text = textMatch.group(1) ?? '';
          if (text.isNotEmpty && text.length > 1) {
            final decodedText = _decodePdfText(text);
            if (decodedText.trim().isNotEmpty) {
              extractedParts.add(decodedText);
            }
          }
        }
      }
      
      // Pattern 3: Annotations and comments
      final annotMatches = RegExp(r'/Contents\s*\(([^)]+)\)').allMatches(pdfString);
      for (final match in annotMatches.take(30)) {
        final text = match.group(1) ?? '';
        if (text.isNotEmpty && text.length > 3) {
          final decodedText = _decodePdfText(text);
          if (decodedText.trim().isNotEmpty) {
            extractedParts.add(decodedText);
          }
        }
      }
      
      // Pattern 4: Metadata text fields
      final metadataMatches = RegExp(r'/(Title|Subject|Author|Keywords)\s*\(([^)]+)\)').allMatches(pdfString);
      for (final match in metadataMatches) {
        final field = match.group(1) ?? '';
        final text = match.group(2) ?? '';
        if (text.isNotEmpty && text.length > 2) {
          final decodedText = _decodePdfText(text);
          if (decodedText.trim().isNotEmpty) {
            extractedParts.add('$field: $decodedText');
          }
        }
      }
      
      // Pattern 5: Look for text between BT/ET blocks more thoroughly
      final btEtMatches = RegExp(r'BT\s+(.*?)\s+ET', dotAll: true).allMatches(pdfString);
      for (final match in btEtMatches.take(50)) {
        final textBlock = match.group(1) ?? '';
        
        // Look for all text showing operations
        final allTextOps = [
          RegExp(r'\(([^)]*)\)\s*Tj'),
          RegExp(r'\(([^)]*)\)\s*TJ'),
          RegExp(r'"([^"]*?)"\s*Tj'),
          RegExp(r"'([^']*?)'\s*Tj"),
          RegExp(r'\[([^\]]*)\]\s*TJ'),
        ];
        
        for (final regex in allTextOps) {
          final matches = regex.allMatches(textBlock);
          for (final textMatch in matches.take(20)) {
            final text = textMatch.group(1) ?? '';
            if (text.isNotEmpty) {
              // Handle array notation for TJ
              if (text.contains('(') && text.contains(')')) {
                final stringMatches = RegExp(r'\(([^)]*)\)').allMatches(text);
                for (final stringMatch in stringMatches) {
                  final stringText = stringMatch.group(1) ?? '';
                  if (stringText.isNotEmpty && stringText.length > 1) {
                    final decodedText = _decodePdfText(stringText);
                    if (decodedText.trim().isNotEmpty) {
                      extractedParts.add(decodedText);
                    }
                  }
                }
              } else {
                final decodedText = _decodePdfText(text);
                if (decodedText.trim().isNotEmpty && decodedText.length > 1) {
                  extractedParts.add(decodedText);
                }
              }
            }
          }
        }
      }
      
      final result = extractedParts.join(' ').trim();
      debugPrint('🔍 Enhanced pattern extraction: ${result.length} characters');
      return result;
      
    } catch (e) {
      debugPrint('❌ Enhanced pattern extraction failed: $e');
      return '';
    }
  }
  

  
  /// Enhanced basic PDF text extraction (from original service)
  Future<String> _extractTextFromPdfBytes(Uint8List pdfBytes, {bool skipCoverPage = false}) async {
    try {
      debugPrint('📄 Starting enhanced PDF text extraction...');
      
      final pdfString = String.fromCharCodes(pdfBytes, 0, (pdfBytes.length / 4).round());
      final extractedParts = <String>[];
      
      // Look for text streams
      final streamMatches = RegExp(r'stream\s*(.*?)\s*endstream', dotAll: true).allMatches(pdfString);
      
      for (final match in streamMatches.take(20)) {
        final streamContent = match.group(1) ?? '';
        
        // Look for text operators in streams
        final textOperators = [
          RegExp(r'\((.*?)\)\s*Tj'),
          RegExp(r'\((.*?)\)\s*TJ'),
          RegExp(r'"([^"]*?)"\s*Tj'),
          RegExp(r"'([^']*?)'\s*Tj"),
        ];
        
        for (final regex in textOperators) {
          final matches = regex.allMatches(streamContent);
          for (final textMatch in matches.take(50)) {
            final text = textMatch.group(1) ?? '';
            if (text.isNotEmpty && text.length > 1) {
              final decodedText = _decodePdfText(text);
              if (decodedText.trim().isNotEmpty && decodedText.length > 1) {
                extractedParts.add(decodedText);
              }
            }
          }
        }
      }
      
      final result = extractedParts.join(' ').trim();
      debugPrint('📄 Basic PDF extraction: ${result.length} characters');
      return result;
      
    } catch (e) {
      debugPrint('❌ Basic PDF extraction failed: $e');
      return '';
    }
  }
  
  /// Check if extracted text contains meaningful content vs just metadata
  bool _isTextMeaningfulContent(String text) {
    if (text.trim().isEmpty) return false;
    
    // Convert to lowercase for analysis
    final lowerText = text.toLowerCase().trim();
    
    // Count metadata-like patterns
    int metadataPatterns = 0;
    final metadataKeywords = [
      'pdf', 'document', 'file', 'size', 'page', 'created', 'modified',
      'author', 'title', 'subject', 'producer', 'creator', 'version',
      'jpeg', 'kb', 'mb', 'bytes', 'format', 'scan', 'analysis'
    ];
    
    for (final keyword in metadataKeywords) {
      if (lowerText.contains(keyword)) {
        metadataPatterns++;
      }
    }
    
    // Count word-like patterns (sequences of letters)
    final wordCount = RegExp(r'\b[a-zA-Z]{3,}\b').allMatches(text).length;
    
    // If more than 40% of keywords are metadata-related and word count is low, it's likely metadata
    final metadataRatio = metadataPatterns / wordCount.clamp(1, double.infinity);
    final isLikelyMetadata = metadataRatio > 0.4 || wordCount < 10;
    
    debugPrint('📄 Content analysis: words=$wordCount, metadata_patterns=$metadataPatterns, ratio=$metadataRatio, likely_metadata=$isLikelyMetadata');
    
    return !isLikelyMetadata;
  }
  
  /// Decode PDF text strings
  String _decodePdfText(String text) {
    try {
      // Handle basic PDF text encoding
      String decoded = text
          .replaceAll(r'\\', r'\')
          .replaceAll(r'\(', '(')
          .replaceAll(r'\)', ')')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\r')
          .replaceAll(r'\t', '\t');
      
      // Remove PDF control characters
      decoded = decoded.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
      
      return decoded.trim();
    } catch (e) {
      return text;
    }
  }
  
  /// Create descriptive text when all extraction methods fail
  Future<String> _createDescriptiveText(Uint8List pdfBytes, String pdfPath) async {
    final fileName = pdfPath.split('/').last.replaceAll('.pdf', '');
    final fileSize = (pdfBytes.length / 1024).round();
    final pageCount = _estimatePageCount(pdfBytes);
    
    // Enhanced analysis to provide better context
    final pdfString = String.fromCharCodes(pdfBytes, 0, (pdfBytes.length / 10).round());
    
    // Try to determine document type and content hints
    String documentType = 'scanned document';
    List<String> contentHints = [];
    List<String> structuralInfo = [];
    
    // Analyze PDF structure for better insights
    if (pdfString.contains('scan') || pdfString.contains('image')) {
      documentType = 'scanned document created from physical pages';
      contentHints.add('Contains scanned images of text and graphics');
    } else if (pdfString.contains('text') || pdfString.contains('font')) {
      documentType = 'text-based document with embedded fonts';
      contentHints.add('Contains formatted text that may be encrypted or encoded');
    }
    
    // Look for form indicators
    if (pdfString.contains('/AcroForm') || pdfString.contains('/Widget')) {
      contentHints.add('Contains interactive form fields or fillable areas');
      structuralInfo.add('PDF form with input fields');
    }
    
    // Look for image indicators
    if (pdfString.contains('/Image') || pdfString.contains('/DCTDecode')) {
      contentHints.add('Contains embedded images or photographs');
      structuralInfo.add('Document with visual content');
    }
    
    // Look for annotation indicators
    if (pdfString.contains('/Annot')) {
      contentHints.add('Contains annotations, comments, or markup');
      structuralInfo.add('Annotated document');
    }
    
    // Enhanced fallback that provides context for AI summarization
    return '''
Document Analysis Report: "$fileName"

DOCUMENT OVERVIEW:
This is a ${pageCount}-page PDF document (${fileSize} KB) identified as a $documentType. While direct text extraction was not successful, structural analysis reveals important characteristics about the document's content and format.

DETECTED CONTENT CHARACTERISTICS:
${contentHints.isNotEmpty ? contentHints.map((hint) => '• $hint').join('\n') : '• Document contains non-extractable content, likely scanned or image-based'}

STRUCTURAL ANALYSIS:
• File format: PDF (Portable Document Format)
• Page count: $pageCount ${pageCount == 1 ? 'page' : 'pages'}
• File size: ${fileSize} KB (${(fileSize / 1024).toStringAsFixed(1)} MB)
${structuralInfo.isNotEmpty ? structuralInfo.map((info) => '• $info').join('\n') : '• Standard PDF structure with embedded content'}

DOCUMENT CLASSIFICATION:
Based on the structural analysis, this document likely belongs to one of these categories:
• Business documentation (reports, invoices, contracts)
• Educational materials (worksheets, assignments, reference documents)
• Official paperwork (forms, certificates, legal documents)
• Personal documents (letters, receipts, records)
• Technical documentation (manuals, specifications, guides)

CONTENT ACCESSIBILITY:
The document appears to contain meaningful content that would be visible when opened in a PDF viewer. The inability to extract text programmatically suggests:
• Content may be stored as images rather than selectable text
• Text may be using non-standard encoding or fonts
• Document may have security restrictions on text extraction
• Content could require optical character recognition (OCR) for full text access

USAGE CONTEXT:
This PDF was likely created through document scanning or image-to-PDF conversion, common in mobile document scanning applications like ScanMate. The document preserves the visual layout and formatting of the original source material.

For comprehensive content analysis, the document should be opened in a PDF viewer where all visual elements, text, and formatting will be properly displayed and accessible to users.
''';
  }
  
  /// Extract raw image streams using more sophisticated pattern matching
  Future<void> _extractRawImageStreams(Uint8List pdfBytes, List<Uint8List> images) async {
    try {
      debugPrint('🖼️ Attempting raw image stream extraction...');
      
      // Convert to string for pattern matching
      final pdfString = String.fromCharCodes(pdfBytes);
      
      // Look for image objects with various filters
      final imageObjectPattern = RegExp(r'(\d+\s+\d+\s+obj.*?/Type\s*/XObject.*?/Subtype\s*/Image.*?stream\s*(.*?)\s*endstream)', dotAll: true);
      final matches = imageObjectPattern.allMatches(pdfString);
      
      debugPrint('🖼️ Found ${matches.length} potential raw image streams');
      
      for (final match in matches.take(5)) {
        try {
          final fullMatch = match.group(0) ?? '';
          final streamData = match.group(2) ?? '';
          
          // Extract filter information
          final filterMatch = RegExp(r'/Filter\s*/(\w+)').firstMatch(fullMatch);
          final filter = filterMatch?.group(1);
          
          debugPrint('🖼️ Processing image with filter: $filter');
          
          if (streamData.isNotEmpty && streamData.length > 50) {
            
            // For different filters, try different extraction approaches
            if (filter == 'DCTDecode' || filter == 'DCT') {
              // JPEG data - look for JPEG markers
              await _extractJPEGFromStream(streamData, images);
            } else if (filter == 'FlateDecode' || filter == 'Fl') {
              // Compressed data - might be PNG or other
              await _extractCompressedImageFromStream(streamData, images);
            } else {
              // Unknown filter - try binary extraction
              await _extractBinaryImageFromStream(streamData, images);
            }
          }
        } catch (e) {
          debugPrint('⚠️ Failed to process raw image stream: $e');
        }
      }
      
    } catch (e) {
      debugPrint('❌ Raw image stream extraction failed: $e');
    }
  }
  
  /// Extract JPEG data from stream
  Future<void> _extractJPEGFromStream(String streamData, List<Uint8List> images) async {
    try {
      // Convert stream to bytes
      List<int> bytes = [];
      for (int i = 0; i < streamData.length; i++) {
        int charCode = streamData.codeUnitAt(i);
        if (charCode <= 255) {
          bytes.add(charCode);
        }
      }
      
      if (bytes.length > 10) {
        // Look for JPEG start/end markers
        bool hasJPEGStart = false;
        bool hasJPEGEnd = false;
        
        for (int i = 0; i < bytes.length - 1; i++) {
          if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
            hasJPEGStart = true;
          }
          if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
            hasJPEGEnd = true;
          }
        }
        
        if (hasJPEGStart || bytes.length > 1000) { // Accept if has JPEG marker or is large enough
          final imageBytes = Uint8List.fromList(bytes);
          images.add(imageBytes);
          debugPrint('🖼️ Extracted JPEG from stream: ${imageBytes.length} bytes');
        }
      }
    } catch (e) {
      debugPrint('⚠️ JPEG stream extraction failed: $e');
    }
  }
  
  /// Extract compressed image from stream
  Future<void> _extractCompressedImageFromStream(String streamData, List<Uint8List> images) async {
    try {
      // This is for FlateDecode - typically requires decompression
      // For now, just try to extract raw bytes and see if they form a valid image
      List<int> bytes = streamData.codeUnits.where((byte) => byte <= 255).toList();
      
      if (bytes.length > 100) {
        final imageBytes = Uint8List.fromList(bytes);
        
        // Basic check for PNG signature
        if (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && 
            bytes[2] == 0x4E && bytes[3] == 0x47) {
          images.add(imageBytes);
          debugPrint('🖼️ Extracted PNG from compressed stream: ${imageBytes.length} bytes');
        } else if (bytes.length > 1000) {
          // Accept large streams that might be valid images
          images.add(imageBytes);
          debugPrint('🖼️ Extracted large compressed stream: ${imageBytes.length} bytes');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Compressed stream extraction failed: $e');
    }
  }
  
  /// Extract binary image from stream
  Future<void> _extractBinaryImageFromStream(String streamData, List<Uint8List> images) async {
    try {
      List<int> bytes = streamData.codeUnits.where((byte) => byte <= 255).toList();
      
      if (bytes.length > 500) { // Only accept reasonably sized streams
        final imageBytes = Uint8List.fromList(bytes);
        images.add(imageBytes);
        debugPrint('🖼️ Extracted binary stream: ${imageBytes.length} bytes');
      }
    } catch (e) {
      debugPrint('⚠️ Binary stream extraction failed: $e');
    }
  }

  /// Estimate page count from PDF structure
  int _estimatePageCount(Uint8List pdfBytes) {
    try {
      final pdfString = String.fromCharCodes(pdfBytes, 0, (pdfBytes.length / 10).round());
      final pageMatches = RegExp(r'/Type\s*/Page[^s]').allMatches(pdfString);
      int pageCount = pageMatches.length;
      
      if (pageCount == 0) {
        // Fallback: look for page objects
        final pageObjMatches = RegExp(r'obj.*?/Type\s*/Page', dotAll: true).allMatches(pdfString);
        pageCount = pageObjMatches.length;
      }
      
      return pageCount > 0 ? pageCount : 1;
    } catch (e) {
      return 1;
    }
  }
  
  /// Clean extracted text
  String _cleanExtractedText(String text) {
    if (text.trim().isEmpty) return text;
    
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
        .trim();
  }
  
  /// Dispose OCR resources
  void dispose() {
    _textRecognizer.close();
  }
}