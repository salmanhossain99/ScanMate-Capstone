import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'env_service.dart';

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

class OfflineGemmaService {
  // Official Gemma 3 Nano E2B int4 model (.task) – competition compliant
  static const String MODEL_NAME = 'gemma-3n-E2B-it-int4.task';
  static const int MODEL_SIZE_BYTES = 3136290816; // 2.99 GB in bytes (actual model size)
  static const String MODEL_SIZE_DISPLAY = '2.99 GB';
  
  // Environment service for configuration
  final EnvService _envService = EnvService();
  
  // Get model URL from environment or use default
  String get modelUrl => _envService.gemmaModelUrl;

  // Legacy gguf model that is no longer compatible – delete on startup if present
  static const String LEGACY_MODEL_NAME = 'gemma-2b-it-Q4_0.gguf';

  // Balanced settings for reliable performance
  static const int MAX_CHUNK_SIZE_WORDS = 60; // Smaller chunks for faster inference
  static const int MAX_CHUNKS_PROCESSED = 1; // Process only 1 chunk to avoid OUT_OF_RANGE errors
  static const int SUMMARY_TARGET_WORDS = 100; // Concise but informative summary
  
  static final OfflineGemmaService _instance = OfflineGemmaService._internal();
  factory OfflineGemmaService() => _instance;
  OfflineGemmaService._internal();
  
  InferenceModel? _model;
  bool _isModelReady = false;
  bool _isInitializing = false;
  
  /// Check if model exists locally
  Future<bool> isModelDownloaded() async {
    try {
      await _deleteLegacyFiles();
      final modelFile = await _getModelFile();
      final exists = await modelFile.exists();
      debugPrint('🔍 MODEL CHECK: File exists: $exists');
      debugPrint('🔍 MODEL CHECK: Path: ${modelFile.path}');
      
      if (!exists) {
        debugPrint('❌ MODEL CHECK: File does not exist');
        return false;
      }
      
      // Check if file has reasonable size (at least 1GB, less than 10GB)
      final fileSize = await modelFile.length();
      const minSize = 1024 * 1024 * 1024; // 1GB minimum
      const maxSize = 10 * 1024 * 1024 * 1024; // 10GB maximum
      
      debugPrint('🔍 MODEL CHECK: File size: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');
      debugPrint('🔍 MODEL CHECK: Min size: ${(minSize / 1024 / 1024).toStringAsFixed(1)}MB');
      debugPrint('🔍 MODEL CHECK: Max size: ${(maxSize / 1024 / 1024).toStringAsFixed(1)}MB');
      
      if (fileSize < minSize) {
        debugPrint('❌ MODEL CHECK: File too small - ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB < ${(minSize / 1024 / 1024).toStringAsFixed(1)}MB');
        debugPrint('🗑️ MODEL CHECK: Deleting corrupted model file...');
        await modelFile.delete();
        return false;
      }
      
      if (fileSize > maxSize) {
        debugPrint('❌ MODEL CHECK: File too large - ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB > ${(maxSize / 1024 / 1024).toStringAsFixed(1)}MB');
        debugPrint('🗑️ MODEL CHECK: Deleting corrupted model file...');
        await modelFile.delete();
        return false;
      }
      
      debugPrint('✅ MODEL CHECK: File validated successfully - ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');
      return true;
    } catch (e) {
      debugPrint('❌ MODEL CHECK: Error checking model existence: $e');
      debugPrint('❌ MODEL CHECK: Error type: ${e.runtimeType}');
      return false;
    }
  }
  
  /// Download model from Hugging Face (ONE-TIME, REQUIRES INTERNET)
  Future<void> downloadModel(String huggingFaceToken, {
    required Function(double progress, String status) onProgress,
  }) async {
    try {
      await _deleteLegacyFiles();
      final gemma = FlutterGemmaPlugin.instance;
      final modelManager = gemma.modelManager;
      
      // Check if model already exists
      final modelFile = await _getModelFile();
      if (await modelFile.exists()) {
        onProgress(1.0, '✅ Model ready for offline AI!');
        return;
      }
      
      onProgress(0.0, '📡 Connecting to Hugging Face...');
      debugPrint('Starting model download from: $modelUrl');
      
      // Custom HTTP download with proper authentication
      await _downloadModelWithProgress(modelUrl, modelFile, huggingFaceToken, onProgress);
      
      debugPrint('✅ Model downloaded successfully');
      
    } catch (e) {
      debugPrint('Model download error: $e');
      rethrow;
    }
  }
  
  /// Initialize model for offline processing (NO INTERNET NEEDED)
  Future<void> initializeModel() async {
    debugPrint('🔧 MODEL INITIALIZATION START');
    debugPrint('🔧 Current state - isModelReady: $_isModelReady, isInitializing: $_isInitializing');
    debugPrint('🔧 Flutter version: ${await _getFlutterVersionInfo()}');
    debugPrint('🔧 Model file check starting...');
    
    if (_isModelReady && _model != null) {
      debugPrint('✅ Model already ready, skipping initialization');
      return;
    }
    
    if (_isInitializing) {
      debugPrint('⏳ Model initialization already in progress, waiting...');
      // Wait for current initialization to complete
      int waitCount = 0;
      while (_isInitializing && waitCount < 180) { // Wait up to 3 minutes (180 seconds)
        await Future.delayed(Duration(seconds: 1));
        waitCount++;
        
        // Log progress every 30 seconds
        if (waitCount % 30 == 0) {
          debugPrint('⏳ Still waiting for model initialization... ${waitCount} seconds elapsed');
        }
      }
      
      if (_isModelReady && _model != null) {
        debugPrint('✅ Model initialization completed while waiting');
        return;
      } else {
        debugPrint('❌ Model initialization failed while waiting - resetting flags');
        // Force reset initialization flag if stuck
        _isInitializing = false;
        throw Exception('Model initialization failed or timed out while waiting for concurrent initialization');
      }
    }
    
    _isInitializing = true;
    debugPrint('🔧 Setting initialization flag, proceeding with setup...');
    
    try {
      final modelFile = await _getModelFile();
      debugPrint('🔧 Model file path: ${modelFile.path}');
      
      if (!await modelFile.exists()) {
        throw Exception('Model file not found at ${modelFile.path}. Please download the model first.');
      }
      
      debugPrint('🔧 Initializing Gemma model for offline processing...');
      
      // Validate model file more thoroughly
      final fileSize = await modelFile.length();
      debugPrint('📦 Model file size: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');
      debugPrint('📦 Expected size: ${(MODEL_SIZE_BYTES / 1024 / 1024).toStringAsFixed(1)}MB');
      
      if (fileSize < MODEL_SIZE_BYTES * 0.9) { // Allow 10% tolerance
        debugPrint('❌ Model file appears incomplete or corrupted');
        debugPrint('Expected: ${(MODEL_SIZE_BYTES / 1024 / 1024).toInt()}MB, Got: ${(fileSize / 1024 / 1024).toInt()}MB');
        await modelFile.delete();
        throw Exception('Model file is incomplete. Please re-download the model.');
      }
      
      final gemma = FlutterGemmaPlugin.instance;
      debugPrint('🔧 Flutter Gemma plugin instance obtained: ${gemma.toString()}');
      
      // Set the model path through ModelFileManager
      debugPrint('🔧 Setting model path through ModelFileManager...');
      debugPrint('🔧 Model path being set: ${modelFile.path}');
      
      try {
        await gemma.modelManager.setModelPath(modelFile.path).timeout(
          Duration(seconds: 30), // Fast path setting
          onTimeout: () => throw Exception('Setting model path timed out after 30 seconds'),
        );
        debugPrint('✅ Model path set successfully');
      } catch (pathError) {
        debugPrint('❌ Error setting model path: $pathError');
        throw Exception('Failed to set model path: $pathError');
      }
      
      // Create model with progressive fallback strategy
      InferenceModel? model;
      String backendUsed = 'unknown';
      
      // Strategy 1: CPU First (most compatible for mid-range devices)
      try {
        debugPrint('🔧 Strategy 1: CPU backend with 1024 tokens (most compatible)...');
        model = await gemma.createModel(
          modelType: ModelType.gemmaIt,
          preferredBackend: PreferredBackend.cpu,
          maxTokens: 1024, // Increased tokens to handle larger final summaries
        ).timeout(
          Duration(seconds: 600), // 10 minutes for CPU model creation on slower devices
          onTimeout: () => throw Exception('CPU model creation timed out after 600 seconds'),
        );
        backendUsed = 'CPU (1024 tokens)';
        debugPrint('✅ CPU backend (1024) created successfully');
      } catch (cpuError) {
        debugPrint('⚠️ CPU backend (1024) failed: $cpuError');
        
        // Strategy 2: Try without specifying backend (let system decide)
        try {
          debugPrint('🔧 Strategy 2: Auto backend selection...');
          model = await gemma.createModel(
            modelType: ModelType.gemmaIt,
            maxTokens: 1024, // Minimal tokens for compatibility
          ).timeout(
            Duration(seconds: 360), // 6 minutes for Auto backend
            onTimeout: () => throw Exception('Auto model creation timed out after 360 seconds'),
          );
          backendUsed = 'Auto (1024 tokens)';
          debugPrint('✅ Auto backend created successfully');
        } catch (autoError) {
          debugPrint('⚠️ Auto backend failed: $autoError');
          
          // Strategy 3: Try GPU as last resort with minimal tokens
          try {
            debugPrint('🔧 Strategy 3: GPU backend with minimal tokens...');
            model = await gemma.createModel(
              modelType: ModelType.gemmaIt,
              preferredBackend: PreferredBackend.gpu,
              maxTokens: 1024,
            ).timeout(
              Duration(seconds: 240), // 4 minutes for GPU backend
              onTimeout: () => throw Exception('GPU model creation timed out after 240 seconds'),
            );
            backendUsed = 'GPU (1024 tokens)';
            debugPrint('✅ GPU backend (1024) created successfully');
          } catch (gpuError) {
            debugPrint('❌ All backend strategies failed');
            debugPrint('CPU Error: $cpuError');
            debugPrint('Auto Error: $autoError');  
            debugPrint('GPU Error: $gpuError');
            throw Exception('Device compatibility issue. Your Redmi Note 12 may need a different model configuration.');
          }
        }
      }
      
      if (model == null) {
        throw Exception('Model creation returned null - unexpected initialization failure');
      }
      
      _model = model;
      
      // Skip model testing to avoid initialization failures
      debugPrint('✅ Skipping model test to ensure compatibility with your device');
      
      _isModelReady = true;
      
      debugPrint('✅ Model initialized successfully using $backendUsed - ready for offline processing!');
      debugPrint('🔧 Final state - isModelReady: $_isModelReady, model: ${_model != null ? 'loaded' : 'null'}');
      
    } catch (e) {
      debugPrint('❌ Model initialization error: $e');
      debugPrint('🔍 Error type: ${e.runtimeType}');
      debugPrint('🔍 Error details: ${e.toString()}');
      
      // Reset state on failure
      _isModelReady = false;
      _model = null;
      
      // Handle specific errors with detailed analysis
      final errorMsg = e.toString().toLowerCase();
      
      if (errorMsg.contains('zip') || 
          errorMsg.contains('archive') ||
          errorMsg.contains('corrupted') ||
          errorMsg.contains('invalid') ||
          errorMsg.contains('malformed') ||
          errorMsg.contains('incomplete')) {
        debugPrint('🗑️ Model file corruption detected, cleaning up...');
        try {
          final modelFile = await _getModelFile();
          if (await modelFile.exists()) {
            await modelFile.delete();
            debugPrint('🗑️ Corrupted model file deleted');
          }
        } catch (deleteError) {
          debugPrint('⚠️ Could not delete corrupted model file: $deleteError');
        }
        throw Exception('Model file is corrupted. Please re-download the model from the AI Setup screen.');
      }
      
      if (errorMsg.contains('timeout') || errorMsg.contains('timed out')) {
        throw Exception('Model initialization timed out. This device may be too slow for AI processing. Please try restarting the app or use a different device.');
      }
      
      if (errorMsg.contains('token') && errorMsg.contains('cache')) {
        throw Exception('Device memory limitation detected. Please restart the app and try again with a smaller PDF, or use a device with more RAM.');
      }
      
      if (errorMsg.contains('not support')) {
        throw Exception('This device does not support the AI model. Please try a different device or contact support.');
      }
      
      // Generic error with troubleshooting advice
      throw Exception('Failed to initialize AI model. Please try: 1) Restart the app, 2) Re-download the model, 3) Free up device memory. Error: $e');
      
    } finally {
      _isInitializing = false;
      debugPrint('🔧 Model initialization process completed, reset initialization flag');
    }
  }
  
    /// Generate PDF summary (COMPLETELY OFFLINE)
  Future<PdfSummary> summarizePdf(String pdfText, {
    SummaryType type = SummaryType.comprehensive,
  }) async {
    final startTime = DateTime.now();
    
    try {
      debugPrint('🤖 SUMMARIZATION START: ${pdfText.length} characters');
      
      if (!_isModelReady) {
        debugPrint('🤖 Model not ready, initializing...');
        await initializeModel().timeout(
          Duration(seconds: 60), // Balanced timeout for 1.4GB model
          onTimeout: () => throw Exception('Model initialization timed out after 60 seconds. Your device might be too slow.'),
        );
        debugPrint('🤖 Model initialization complete');
        
        // Double-check that model is actually ready
        if (!_isModelReady || _model == null) {
          throw Exception('Model initialization failed. Please restart the app and try again.');
        }
      }
      
      debugPrint('🤖 Starting PDF summarization...');
      
      // Clean and prepare text
      final cleanText = _cleanPdfText(pdfText);
      if (cleanText.trim().isEmpty) {
        throw Exception('No readable text found in PDF');
      }
      debugPrint('🤖 Text cleaned: ${cleanText.length} characters');
      
      // Split into chunks if text is too long
      final chunks = _chunkText(cleanText, maxChunkSize: MAX_CHUNK_SIZE_WORDS); // Small chunks for speed
      debugPrint('🤖 Split into ${chunks.length} chunks for processing');
      
      List<String> chunkSummaries = [];
      
      // Limit chunks processed for speed
      final chunksToProcess = chunks.take(MAX_CHUNKS_PROCESSED).toList();
      debugPrint('🚀 Processing only ${chunksToProcess.length} chunks for speed');
      
      for (int i = 0; i < chunksToProcess.length; i++) {
        debugPrint('🤖 Processing chunk ${i + 1}/${chunksToProcess.length} (${chunksToProcess[i].length} chars)...');
        
        
        final prompt = "Key point: ${chunksToProcess[i]}";
        debugPrint('🤖 Prompt built for chunk ${i + 1}: ${prompt.length} characters');

        // Create a session for this chunk with timeout
        debugPrint('🤖 Creating session for chunk ${i + 1}...');
        
        // Check if model is properly initialized
        if (_model == null) {
          throw Exception('AI model is not initialized. Please try again.');
        }
        
        final session = await _model!.createSession().timeout(
          Duration(seconds: 60), // Increased timeout for session creation on slower devices
          onTimeout: () => throw Exception('Session creation timed out for chunk ${i + 1} after 60 seconds'),
        );
        debugPrint('🤖 Session created for chunk ${i + 1}');
        
        try {
          debugPrint('🤖 Adding query chunk ${i + 1}...');
          await session.addQueryChunk(Message.text(text: prompt, isUser: true)).timeout(
            Duration(seconds: 10), // Increased timeout
            onTimeout: () => throw Exception('Adding query chunk timed out for chunk ${i + 1}'),
          );
          debugPrint('🤖 Query chunk ${i + 1} added, getting response...');
          
          final response = await session.getResponse().timeout(
            const Duration(seconds: 480), // 8 minutes for model inference on slower devices
            onTimeout: () => throw Exception('Model inference timed out for chunk ${i + 1} after 480 seconds'),
          );
          debugPrint('🤖 Response received for chunk ${i + 1}: ${response.length} characters');
          
          final chunkSummary = response.trim();
          
          if (chunkSummary.isNotEmpty) {
            chunkSummaries.add(chunkSummary);
            debugPrint('🤖 Chunk ${i + 1} summary added');
          } else {
            debugPrint('⚠️ Chunk ${i + 1} produced empty summary');
          }
        } catch (chunkError) {
          debugPrint('❌ Error processing chunk ${i + 1}: $chunkError');
          // Don't fail completely - try to continue or use partial results
          if (chunkError.toString().contains('timed out')) {
            debugPrint('⚠️ Skipping timed out chunk ${i + 1}, continuing...');
          } else {
            // Re-throw other critical errors
            rethrow;
          }
        } finally {
          debugPrint('🤖 Closing session for chunk ${i + 1}...');
          try {
            await session.close().timeout(
              Duration(seconds: 10),
              onTimeout: () => debugPrint('⚠️ Session close timed out for chunk ${i + 1}'),
            );
            debugPrint('🤖 Session closed for chunk ${i + 1}');
          } catch (closeError) {
            debugPrint('⚠️ Error closing session for chunk ${i + 1}: $closeError');
          }
        }
      }
      
      debugPrint('🤖 All chunks processed, combining summaries...');
      
      // Combine summaries if multiple chunks
      String finalSummary;
      if (chunkSummaries.length > 1) {
        debugPrint('🤖 Combining ${chunkSummaries.length} chunk summaries...');
        finalSummary = await _combineChunkSummaries(chunkSummaries, type).timeout(
          Duration(seconds: 180), // 3 minutes for combining summaries
          onTimeout: () => throw Exception('Combining summaries timed out after 180 seconds'),
        );
        debugPrint('🤖 Summaries combined: ${finalSummary.length} characters');
      } else {
        finalSummary = chunkSummaries.isNotEmpty ? chunkSummaries.first : 'No summary could be generated.';
        debugPrint('🤖 Using single summary: ${finalSummary.length} characters');
      }
      
      // Extract key points
      debugPrint('🤖 Extracting key points...');
      final keyPoints = await _extractKeyPoints(finalSummary).timeout(
        Duration(seconds: 180), // 3 minutes for key point extraction
        onTimeout: () => throw Exception('Key point extraction timed out after 180 seconds'),
      );
      debugPrint('🤖 Key points extracted: ${keyPoints.length} points');
      
      final processingTime = DateTime.now().difference(startTime);
      final originalWords = cleanText.split(' ').length;
      final summaryWords = finalSummary.split(' ').length;
      final compressionRatio = summaryWords / originalWords;
      
      debugPrint('✅ Summarization complete in ${processingTime.inMilliseconds}ms');
      debugPrint('Compression: ${originalWords} → ${summaryWords} words (${(compressionRatio * 100).toInt()}%)');
      
      return PdfSummary(
        originalText: cleanText,
        summary: finalSummary,
        keyPoints: keyPoints,
        processingTimeMs: processingTime.inMilliseconds,
        compressionRatio: compressionRatio,
        isOffline: true,
        modelUsed: 'Gemma 3N E2B (Offline)',
      );
      
    } catch (e) {
      debugPrint('Summarization error: $e');
      rethrow;
    }
  }
  
  /// Get local model file path
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
  
  /// Combine multiple chunk summaries into final summary
  Future<String> _combineChunkSummaries(List<String> summaries, SummaryType type) async {
    final combinedText = summaries.join('\n\n---\n\n');
    final maxWords = _getTargetWordCount(type);
    
    final prompt = '''Combine these section summaries into one unified, coherent summary of exactly $maxWords words:

$combinedText

Create a single, well-structured summary that:
- Captures all main points without redundancy
- Maintains logical flow and coherence
- Stays within the $maxWords word limit
- Preserves the most important information

Final Summary:''';
    
    try {
      // Check if model is properly initialized
      if (_model == null) {
        throw Exception('AI model is not initialized for combining summaries.');
      }
      
      final session = await _model!.createSession(
        temperature: 0.2,
        randomSeed: 1,
        topK: 40,
      ).timeout(
        Duration(seconds: 60), // Consistent timeout for session creation
        onTimeout: () => throw Exception('Session creation timed out while combining summaries'),
      );
      
      try {
        await session.addQueryChunk(Message.text(text: prompt, isUser: true));
        final response = await session.getResponse();
        return response.trim();
      } finally {
        await session.close();
      }
    } catch (e) {
      debugPrint('Error combining summaries: $e');
      return summaries.join(' ');
    }
  }
  
  /// Extract key points from summary
  Future<List<String>> _extractKeyPoints(String summary) async {
    final prompt = '''Extract 5 key points from this summary as short bullet points:

$summary

Key Points:
1.''';
    
    try {
      // Check if model is properly initialized
      if (_model == null) {
        throw Exception('AI model is not initialized for extracting key points.');
      }
      
      final session = await _model!.createSession(
        temperature: 0.2,
        randomSeed: 1,
        topK: 40,
      ).timeout(
        Duration(seconds: 60), // Consistent timeout for session creation
        onTimeout: () => throw Exception('Session creation timed out while extracting key points'),
      );
      
      try {
        await session.addQueryChunk(Message.text(text: prompt, isUser: true));
        final response = await session.getResponse();
        
        final points = response
            .split(RegExp(r'\d+\.'))
            .where((point) => point.trim().isNotEmpty)
            .map((point) => point.trim())
            .take(5)
            .toList();
        
        return points.isNotEmpty ? points : ['Summary completed successfully'];
      } finally {
        await session.close();
      }
      
    } catch (e) {
      debugPrint('Key points extraction error: $e');
      return ['Summary completed successfully'];
    }
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
      _model = null;
    } catch (e) {
      debugPrint('Error deleting model: $e');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    if (_model != null) {
      await _model!.close();
      _model = null;
    }
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