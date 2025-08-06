import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart' as pdf_lib;
import 'package:pdf/widgets.dart' as pw;

class PdfTextExtractionService {
  static final PdfTextExtractionService _instance = PdfTextExtractionService._internal();
  factory PdfTextExtractionService() => _instance;
  PdfTextExtractionService._internal();
  
  /// Extract text from PDF file for AI summarization
  Future<String> extractTextFromPdf(String pdfPath, {bool skipCoverPage = false}) async {
    try {
      debugPrint('📄 TEXT EXTRACTION START: $pdfPath');
      
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
      
      // Try to extract text using basic PDF parsing
      debugPrint('📄 Attempting text extraction...');
      String extractedText = await _extractTextFromPdfBytes(pdfBytes, skipCoverPage: skipCoverPage).timeout(
        Duration(seconds: 60),
        onTimeout: () => throw Exception('PDF text extraction timed out after 60 seconds'),
      );
      debugPrint('📄 Initial extraction result: ${extractedText.length} characters');
      
      if (extractedText.trim().isEmpty) {
        debugPrint('📄 No text extracted, trying fallback method...');
        // Fallback: Try to extract text from PDF metadata or create placeholder
        extractedText = await _createTextFromPdfStructure(pdfBytes, pdfPath).timeout(
          Duration(seconds: 30),
          onTimeout: () => throw Exception('PDF structure analysis timed out after 30 seconds'),
        );
        debugPrint('📄 Fallback extraction result: ${extractedText.length} characters');
      }
      
      // Clean and validate the extracted text
      debugPrint('📄 Cleaning extracted text...');
      final cleanedText = _cleanExtractedText(extractedText);
      
      debugPrint('📄 TEXT EXTRACTION COMPLETE: ${cleanedText.length} characters extracted');
      return cleanedText;
      
    } catch (e) {
      debugPrint('❌ TEXT EXTRACTION ERROR: $e');
      rethrow;
    }
  }
  
  /// Extract text from PDF bytes using enhanced parsing
  Future<String> _extractTextFromPdfBytes(Uint8List pdfBytes, {bool skipCoverPage = false}) async {
    try {
      debugPrint('📄 Starting enhanced PDF text extraction...');
      
      // Convert PDF bytes to string for text extraction
        final pdfString = String.fromCharCodes(pdfBytes, 0, (pdfBytes.length / 4).round()); // Process only first quarter for performance
        final extractedParts = <String>[];
        
        if (skipCoverPage) {
          debugPrint('📄 Skipping cover page for summarization...');
        }
      
      // Method 1: Look for text streams (more reliable)
      debugPrint('📄 Method 1: Extracting from text streams...');
      final streamMatches = RegExp(r'stream\s*(.*?)\s*endstream', dotAll: true).allMatches(pdfString);
      int streamCount = 0;
      
      for (final match in streamMatches.take(10)) { // Limit to first 10 streams for performance
        streamCount++;
        final streamContent = match.group(1) ?? '';
        
        // Look for text operators in streams
        final textOperators = [
          RegExp(r'\((.*?)\)\s*Tj'),              // Simple text showing
          RegExp(r'\((.*?)\)\s*TJ'),              // Text with adjustments
          RegExp(r'"([^"]*?)"\s*Tj'),             // Quoted text
          RegExp(r"'([^']*?)'\s*Tj"),             // Single quoted text
        ];
        
        for (final regex in textOperators) {
          final matches = regex.allMatches(streamContent);
          for (final textMatch in matches.take(20)) { // Limit matches per stream
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
      debugPrint('📄 Method 1: Found ${extractedParts.length} text parts from $streamCount streams');
      
      // Method 2: Look for text objects (fallback)
      if (extractedParts.isEmpty) {
        debugPrint('📄 Method 2: Extracting from text objects...');
        final textMatches = RegExp(r'BT\s+(.*?)\s+ET', dotAll: true).allMatches(pdfString);
        
        for (final match in textMatches.take(20)) { // Limit for performance
          final textBlock = match.group(1) ?? '';
          
          // Extract text from Tj operators
          final tjMatches = RegExp(r'\((.*?)\)\s*Tj').allMatches(textBlock);
          for (final tjMatch in tjMatches.take(10)) {
            final text = tjMatch.group(1) ?? '';
            if (text.isNotEmpty && text.length > 1) {
              final decodedText = _decodePdfText(text);
              if (decodedText.trim().isNotEmpty) {
                extractedParts.add(decodedText);
              }
            }
          }
          
          // Extract text from TJ arrays
          final tjArrayMatches = RegExp(r'\[(.*?)\]\s*TJ').allMatches(textBlock);
          for (final tjArrayMatch in tjArrayMatches.take(5)) {
            final arrayContent = tjArrayMatch.group(1) ?? '';
            final stringMatches = RegExp(r'\((.*?)\)').allMatches(arrayContent);
            for (final stringMatch in stringMatches.take(10)) {
              final text = stringMatch.group(1) ?? '';
              if (text.isNotEmpty && text.length > 1) {
                final decodedText = _decodePdfText(text);
                if (decodedText.trim().isNotEmpty) {
                  extractedParts.add(decodedText);
                }
              }
            }
          }
        }
        debugPrint('📄 Method 2: Found additional ${extractedParts.length} text parts');
      }
      
      // Method 3: Look for common text patterns (last resort)
      if (extractedParts.isEmpty) {
        debugPrint('📄 Method 3: Searching for readable text patterns...');
        
        // Look for readable text patterns in the PDF
        final readableMatches = RegExp(r'[A-Za-z][A-Za-z\s]{10,100}[.!?]').allMatches(pdfString);
        for (final readableMatch in readableMatches.take(20)) {
          final text = readableMatch.group(0) ?? '';
          if (text.length > 10) {
            extractedParts.add(text.trim());
          }
        }
        debugPrint('📄 Method 3: Found ${extractedParts.length} readable patterns');
      }
      
      String result = extractedParts.join(' ').trim();
        
        // Skip cover page content if requested
        if (skipCoverPage && result.isNotEmpty) {
          result = _skipCoverPageContent(result);
          debugPrint('📄 Cover page skipped, remaining: ${result.length} characters');
        }
        
        debugPrint('📄 Enhanced extraction complete: ${result.length} characters');
        return result;
      
    } catch (e) {
      debugPrint('❌ Error in enhanced PDF text extraction: $e');
      return '';
    }
  }
  
  /// Skip cover page content from extracted text
  String _skipCoverPageContent(String text) {
    try {
      final lines = text.split('\n');
      if (lines.length <= 10) {
        // If text is very short, assume it's all cover page
        return '';
      }
      
      // Heuristic: Skip first 20% of lines as likely cover page content
      final linesToSkip = (lines.length * 0.2).round();
      final remainingLines = lines.skip(linesToSkip).toList();
      
      // Also try to find content indicators (like "Chapter", "Introduction", "Abstract", etc.)
      for (int i = 0; i < remainingLines.length; i++) {
        final line = remainingLines[i].toLowerCase();
        if (line.contains('chapter') || 
            line.contains('introduction') ||
            line.contains('abstract') ||
            line.contains('summary') ||
            line.contains('contents') ||
            line.contains('overview') ||
            line.length > 100) { // Long lines likely contain content
          // Found content start, return from here
          return remainingLines.skip(i).join('\n').trim();
        }
      }
      
      // Fallback: return text after skipping first 20% of lines
      return remainingLines.join('\n').trim();
      
    } catch (e) {
      debugPrint('📄 Error skipping cover page: $e');
      return text; // Return original if skipping fails
    }
  }
  
  /// Create meaningful text from PDF when direct extraction fails
  Future<String> _createTextFromPdfStructure(Uint8List pdfBytes, String pdfPath) async {
    try {
      debugPrint('📄 Creating fallback text representation...');
      
      // Get PDF metadata and structure info
      final fileName = pdfPath.split('/').last.replaceAll('.pdf', '');
      final fileSize = (pdfBytes.length / 1024).round();
      final pageCount = _estimatePageCount(pdfBytes);
      final creationTime = DateTime.now();
      
      // Try to extract any readable metadata
      final pdfString = String.fromCharCodes(pdfBytes, 0, (pdfBytes.length / 10).round());
      String documentType = 'scanned document';
      String possibleContent = 'mixed content including text and images';
      
      // Look for hints about document type
      if (pdfString.contains('scan') || pdfString.contains('image')) {
        documentType = 'scanned document or image-based PDF';
        possibleContent = 'scanned pages converted to PDF format';
      } else if (pdfString.contains('text') || pdfString.contains('font')) {
        documentType = 'text-based PDF document';
        possibleContent = 'formatted text content with potential graphics';
      }
      
      // Extract any title or metadata if available
      String titleInfo = '';
      final titleMatch = RegExp(r'/Title\s*\(([^)]+)\)').firstMatch(pdfString);
      if (titleMatch != null) {
        final title = titleMatch.group(1) ?? '';
        if (title.isNotEmpty && title != fileName) {
          titleInfo = '\n- Document title: "$title"';
        }
      }
      
      // Create detailed but realistic descriptive text
      final fallbackText = '''
Document Analysis Summary for "$fileName"

Basic Information:
- File name: $fileName
- File size: ${fileSize} KB (${(fileSize / 1024).toStringAsFixed(1)} MB)
- Estimated pages: $pageCount
- Document type: $documentType$titleInfo
- Processing date: ${creationTime.toString().split('.')[0]}

Content Assessment:
This PDF appears to contain $possibleContent. The document was likely created through a scanning or document processing application, possibly ScanMate or similar document management software.

Technical Details:
- Format: Portable Document Format (PDF)
- Content structure: ${pageCount > 1 ? 'Multi-page document' : 'Single-page document'}
- Text extraction: Limited due to document encoding or image-based content
- Recommended viewing: Use PDF viewer for full content access

Document Context:
Based on the file structure and metadata, this document may contain:
• Important textual information that requires OCR for extraction
• Formatted content with specific layout requirements
• Scanned images or photographs converted to PDF format
• Business documents, forms, or official paperwork
• Educational or reference materials

Summary Limitation Notice:
This summary is generated from document metadata and structure analysis because direct text extraction was not successful. The actual document content may contain significantly more detailed information that would be visible when viewing the PDF directly in a compatible reader application.

For complete content analysis, please:
1. Open the PDF in a dedicated PDF viewer
2. Use OCR software if the document contains scanned images
3. Check if the document requires special fonts or viewing software
4. Verify that the PDF is not password-protected or corrupted

This analysis provides a general overview based on available document properties and technical characteristics.
''';
      
      debugPrint('📄 Fallback text created: ${fallbackText.length} characters');
      return fallbackText;
      
    } catch (e) {
      debugPrint('❌ Error creating text from PDF structure: $e');
      return '''
PDF Document Summary

This PDF document could not be processed for text extraction due to technical limitations. The document may contain:
- Scanned images requiring OCR processing
- Complex formatting or encoding
- Password protection or security restrictions
- Corrupted or incomplete file data

Please use a dedicated PDF viewer to access the full content of this document.

File details: ${pdfPath.split('/').last}
Processing error: ${e.toString().split('.')[0]}
''';
    }
  }
  
  /// Decode PDF text strings (handle basic PDF encoding)
  String _decodePdfText(String pdfText) {
    return pdfText
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\\', '\\')
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\ ', ' ')
        .trim();
  }
  
  /// Estimate number of pages in PDF
  int _estimatePageCount(Uint8List pdfBytes) {
    try {
      final pdfString = String.fromCharCodes(pdfBytes);
      
      // Count page objects
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(pdfString);
      if (pageMatches.isNotEmpty) {
        return pageMatches.length;
      }
      
      // Fallback: estimate based on file size
      final sizeKB = pdfBytes.length ~/ 1024;
      if (sizeKB < 100) return 1;
      if (sizeKB < 300) return 2;
      if (sizeKB < 600) return 3;
      if (sizeKB < 1000) return 4;
      return (sizeKB / 250).round().clamp(1, 20);
      
    } catch (e) {
      return 1;
    }
  }
  
  /// Clean and validate extracted text
  String _cleanExtractedText(String text) {
    if (text.trim().isEmpty) {
      return 'No readable text content found in this PDF document.';
    }
    
    return text
        // Normalize whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        // Remove control characters except newlines and tabs
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        // Clean up multiple spaces
        .replaceAll(RegExp(r' {2,}'), ' ')
        // Ensure paragraph breaks
        .replaceAll(RegExp(r'\.([A-Z])'), '. \$1')
        .trim();
  }
  
  /// Validate if extracted text is meaningful for summarization
  bool isTextSuitableForSummarization(String text) {
    if (text.length < 100) return false;
    
    // Check for reasonable word count
    final words = text.split(' ').where((word) => word.trim().isNotEmpty).toList();
    if (words.length < 20) return false;
    
    // Check for reasonable character-to-word ratio (avoid gibberish)
    final averageWordLength = text.length / words.length;
    if (averageWordLength > 20 || averageWordLength < 2) return false;
    
    return true;
  }
  
  /// Get text extraction statistics
  Map<String, dynamic> getTextStats(String text) {
    final words = text.split(' ').where((word) => word.trim().isNotEmpty).toList();
    final sentences = text.split(RegExp(r'[.!?]+(?:\s|$)')).where((s) => s.trim().isNotEmpty).toList();
    final paragraphs = text.split('\n\n').where((p) => p.trim().isNotEmpty).toList();
    
    return {
      'characters': text.length,
      'words': words.length,
      'sentences': sentences.length,
      'paragraphs': paragraphs.length,
      'averageWordsPerSentence': sentences.isNotEmpty ? (words.length / sentences.length).round() : 0,
      'readabilityScore': _calculateSimpleReadabilityScore(words, sentences),
    };
  }
  
  /// Calculate a simple readability score
  double _calculateSimpleReadabilityScore(List<String> words, List<String> sentences) {
    if (words.isEmpty || sentences.isEmpty) return 0.0;
    
    final averageWordsPerSentence = words.length / sentences.length;
    final averageLettersPerWord = words.map((w) => w.length).reduce((a, b) => a + b) / words.length;
    
    // Simplified Flesch Reading Ease approximation
    final score = 206.835 - (1.015 * averageWordsPerSentence) - (84.6 * (averageLettersPerWord / 4.7));
    return score.clamp(0.0, 100.0);
  }
}