import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
// Gemma imports removed from active use. Keeping file name and API stable
// to avoid broad codebase changes. We implement a lightweight offline
// extractive summarizer below.
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

enum SummaryType { brief, comprehensive, detailed, keyPoints }

class PdfSummary {
  final String originalText;
  final String summary;
  final List<String> keyPoints;
  final int processingTimeMs;
  final double compressionRatio;
  final bool isOffline;
  final String modelUsed;
  
  PdfSummary({
    required this.originalText,
    required this.summary,
    required this.keyPoints,
    required this.processingTimeMs,
    required this.compressionRatio,
    required this.isOffline,
    required this.modelUsed,
  });
}

// Lightweight sentence score container (top-level)
class _ScoredSentence {
  final int index;
  final String text;
  final double score;
  _ScoredSentence({required this.index, required this.text, required this.score});
}

class OfflineGemmaService {
  // Gemma constants retained for backward compatibility but unused.
  static const String MODEL_NAME = '';
  static const String MODEL_URL  = '';
  static const int MODEL_SIZE_BYTES = 0;
  static const String MODEL_SIZE_DISPLAY = '';
  static const String LEGACY_MODEL_NAME = '';

  // Lightweight summarizer targets
  static const int MAX_CHUNK_SIZE_WORDS = 2000; // Not used by extractive summarizer
  static const int MAX_CHUNKS_PROCESSED = 1;
  static const int SUMMARY_TARGET_WORDS = 150;
  
  static final OfflineGemmaService _instance = OfflineGemmaService._internal();
  factory OfflineGemmaService() => _instance;
  OfflineGemmaService._internal();
  
  bool _isModelReady = false;
  bool _isInitializing = false;
  
  /// Check if model exists locally
  Future<bool> isModelDownloaded() async {
    // No model required for lightweight summarizer.
    _isModelReady = true;
      return true;
  }
  
  /// Download model from Hugging Face (ONE-TIME, REQUIRES INTERNET)
  Future<void> downloadModel(String huggingFaceToken, {
    required Function(double progress, String status) onProgress,
  }) async {
    // No model is required for the lightweight summarizer; report ready.
    onProgress(1.0, '✅ Offline summarizer ready!');
  }
  
  /// Initialize model for offline processing (NO INTERNET NEEDED)
  Future<void> initializeModel() async {
    // No heavy model initialization required.
      _isModelReady = true;
  }
  
    /// Generate PDF summary (COMPLETELY OFFLINE)
  Future<PdfSummary> summarizePdf(String pdfText, {
    SummaryType type = SummaryType.comprehensive,
  }) async {
    final start = DateTime.now();
    final text = _cleanPdfText(pdfText);
    if (text.isEmpty) {
      throw Exception('No readable text found in PDF');
    }

    final sentences = _splitIntoSentences(text);
    final stop = _stopWords;
    // Global word frequency
    final Map<String, int> freq = {};
    for (final s in sentences) {
      for (final w in _tokenize(s)) {
        if (stop.contains(w)) continue;
        freq[w] = (freq[w] ?? 0) + 1;
      }
    }

    // Score sentences by sum of word frequencies (normalized)
    final List<_ScoredSentence> scored = [];
    for (int i = 0; i < sentences.length; i++) {
      final s = sentences[i];
      int raw = 0;
      final words = _tokenize(s);
      for (final w in words) {
        if (stop.contains(w)) continue;
        raw += (freq[w] ?? 0);
      }
      final score = words.isEmpty ? 0.0 : raw / (words.length * 1.0);
      scored.add(_ScoredSentence(index: i, text: s, score: score));
    }

    // Determine number of sentences
    int target;
    switch (type) {
      case SummaryType.brief:
        target = math.min(4, sentences.length);
        break;
      case SummaryType.comprehensive:
        target = math.min(8, sentences.length);
        break;
      case SummaryType.detailed:
        target = math.min(12, sentences.length);
        break;
      case SummaryType.keyPoints:
        target = math.min(6, sentences.length);
        break;
    }

    scored.sort((_ScoredSentence a, _ScoredSentence b) => b.score.compareTo(a.score));
    final List<_ScoredSentence> chosen = scored.take(target).toList()
      ..sort((_ScoredSentence a, _ScoredSentence b) => a.index.compareTo(b.index));
    final summary = chosen.map((e) => e.text.trim()).join(' ');

    // Key points: top 5 sentences by score, trimmed to shorter snippets
    final int keyCount = math.min(5, sentences.length);
    final List<String> keyPoints = scored
        .take(keyCount)
        .map<String>((e) => _toBullet(e.text))
        .toList();

    final elapsed = DateTime.now().difference(start);
    final compression = summary.split(' ').length / text.split(' ').length;
      
      return PdfSummary(
      originalText: text,
      summary: summary.isEmpty ? sentences.join(' ') : summary,
        keyPoints: keyPoints,
      processingTimeMs: elapsed.inMilliseconds,
      compressionRatio: compression.isFinite ? compression : 1.0,
        isOffline: true,
      modelUsed: 'TextRank Extractive (Offline)',
    );
  }

  List<String> _splitIntoSentences(String text) {
    final parts = text.split(RegExp(r'(?<=[.!?])\s+'));
    return parts.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  Iterable<String> _tokenize(String s) sync* {
    final lower = s.toLowerCase();
    for (final m in RegExp(r'[a-zA-Z]+').allMatches(lower)) {
      yield m.group(0)!;
    }
  }

  String _toBullet(String s) {
    final trimmed = s.trim();
    return trimmed.length > 180 ? '${trimmed.substring(0, 177)}…' : trimmed;
  }

  static const Set<String> _stopWords = {
    'the','and','is','in','it','of','to','a','for','on','that','with','as','are','was','were','by','this','an','be','or','from','at','which','but','not','have','has','had','can','will','would','there','their','its','if','than','then','so','such','these','those','into','we','you','your','our','they','he','she','his','her','them','about','over','more','most','other','also','may','one','two','three'
  };

  // (moved _ScoredSentence to top-level)
  
  // Legacy helpers retained but unused
  Future<File> _getModelFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/gemma_models');
    await modelDir.create(recursive: true);
    return File('${modelDir.path}/$MODEL_NAME');
  }

  /// Custom HTTP download with proper progress tracking and authentication
  Future<void> _downloadModelWithProgress(
    String url,
    File destinationFile,
    String huggingFaceToken,
    Function(double, String) onProgress,
  ) async {
    try {
      // Start the HTTP request with proper headers
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll({
        'Authorization': 'Bearer $huggingFaceToken',
        'User-Agent': 'flutter_doc_scanner/1.0',
        'Accept': '*/*',
        'Connection': 'keep-alive',
      });

      final response = await http.Client().send(request);
      
      if (response.statusCode != 200) {
        throw Exception('Download failed: ${response.statusCode} ${response.reasonPhrase}');
      }

      final contentLength = response.contentLength ?? MODEL_SIZE_BYTES; // 4.1GB in bytes
      debugPrint('📦 Content-Length: ${(contentLength / 1024 / 1024).toStringAsFixed(1)}MB');
      
      int downloadedBytes = 0;
      final sink = destinationFile.openWrite();
      
      onProgress(0.0, '🚀 Starting download...');
      
      await for (final chunk in response.stream) {
        downloadedBytes += chunk.length;
        sink.add(chunk);
        
        final progress = downloadedBytes / contentLength;
        final downloadedMB = (downloadedBytes / 1024 / 1024).toInt();
        final totalMB = (contentLength / 1024 / 1024).toInt();
        
        onProgress(
          progress.clamp(0.0, 1.0),
          progress < 1.0 
            ? '⬇️ Downloading: ${downloadedMB}MB / ${totalMB}MB (${(progress * 100).toInt()}%)'
            : '🎉 Gemma 3n ready for offline summarization!'
        );
        
        // Log progress every 100MB
        if (downloadedMB % 100 == 0 && downloadedMB > 0) {
          debugPrint('📥 Downloaded: ${downloadedMB}MB / ${totalMB}MB');
        }
      }
      
      await sink.close();
      
      // Verify file size
      final fileSize = await destinationFile.length();
      debugPrint('✅ Download complete! File size: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');
      
      if (fileSize < contentLength * 0.95) { // Allow 5% tolerance
        throw Exception('Download incomplete. Expected: ${(contentLength / 1024 / 1024).toInt()}MB, Got: ${(fileSize / 1024 / 1024).toInt()}MB');
      }
      
    } catch (e) {
      // Clean up partial download
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      debugPrint('❌ Download failed: $e');
      rethrow;
    }
  }
  
  /// Clean and prepare PDF text for processing
  String _cleanPdfText(String rawText) {
    return rawText
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .replaceAll(RegExp(r'[^\w\s\.\,\!\?\;\:\-\(\)]'), '') // Remove special chars
        .trim();
  }
  
  /// Split text into manageable chunks
  List<String> _chunkText(String text, {int maxChunkSize = 1500}) {
    final words = text.split(' ');
    final chunks = <String>[];
    
    for (int i = 0; i < words.length; i += maxChunkSize) {
      final end = (i + maxChunkSize < words.length) ? i + maxChunkSize : words.length;
      chunks.add(words.sublist(i, end).join(' '));
    }
    
    return chunks.where((chunk) => chunk.trim().isNotEmpty).toList();
  }
  
  /// Build optimized prompt for summarization
  String _buildSummaryPrompt(String text, SummaryType type, int chunkNum, int totalChunks) {
    final contextInfo = totalChunks > 1 ? ' (Part $chunkNum of $totalChunks)' : '';
    
    switch (type) {
      case SummaryType.brief:
        return '''Summarize this document$contextInfo in exactly 100-150 words. Focus on the most important points and key findings:

$text

Brief Summary:''';
        
      case SummaryType.comprehensive:
        return '''Create a comprehensive summary of this document$contextInfo in 300-400 words. Include main ideas, important details, and key conclusions:

$text

Comprehensive Summary:''';
        
      case SummaryType.detailed:
        return '''Provide a detailed summary of this document$contextInfo in 500-600 words. Preserve important context, methodology, and detailed findings:

$text

Detailed Summary:''';
        
      case SummaryType.keyPoints:
        return '''Extract 5-8 key bullet points from this document$contextInfo. Each point should be concise and capture essential information:

$text

Key Points:
•''';
    }
  }
  
  Future<String> _combineChunkSummaries(List<String> summaries, SummaryType type) async {
    // Simple concatenation fallback for extractive method
      return summaries.join(' ');
  }
  
  /// Extract key points from summary
  Future<List<String>> _extractKeyPoints(String summary) async {
    // Split summary into sentences and take top 5 shortest as key points
    final sents = _splitIntoSentences(summary);
    sents.sort((a, b) => a.length.compareTo(b.length));
    return sents.take(5).map((e) => _toBullet(e)).toList();
  }
  
  /// Get target word count for summary type
  int _getTargetWordCount(SummaryType type) {
    switch (type) {
      case SummaryType.brief: return 125;
      case SummaryType.comprehensive: return 350;
      case SummaryType.detailed: return 550;
      case SummaryType.keyPoints: return 100;
    }
  }
  
  /// Delete obsolete gguf model if it exists to prevent incompatible initialisation errors
  Future<void> _deleteLegacyFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${appDir.path}/gemma_models');
      final legacyFile = File('${modelDir.path}/$LEGACY_MODEL_NAME');
      if (await legacyFile.exists()) {
        debugPrint('🗑️ Removing legacy model file: ${legacyFile.path}');
        await legacyFile.delete();
      }
    } catch (e) {
      debugPrint('⚠️ Could not delete legacy model file: $e');
    }
  }

  /// Force delete corrupted model file (for re-download)
  Future<void> deleteModel() async {
    try {
      final modelFile = await _getModelFile();
      if (await modelFile.exists()) {
        await modelFile.delete();
        debugPrint('🗑️ Model file deleted successfully');
      }
      _isModelReady = false;
    } catch (e) {
      debugPrint('Error deleting model: $e');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    _isModelReady = false;
  }
  
  /// Get Flutter version info for debugging
  Future<String> _getFlutterVersionInfo() async {
    try {
      // This is just for debugging, don't worry if it fails
      return 'Available';
    } catch (e) {
      return 'Unknown';
    }
  }
}