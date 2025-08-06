import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  final DefaultCacheManager _cacheManager = DefaultCacheManager();
  final Map<String, String> _memoryCache = {};
  
  // In-memory caching for processed images to avoid duplicate processing
  final Map<String, Uint8List> _processedImagesCache = {};
  
  // Maximum size for the processed images cache (in number of items)
  static const int _maxProcessedCacheSize = 20;

  factory ImageCacheService() {
    print('IMAGE_CACHE: Getting ImageCacheService instance');
    return _instance;
  }

  ImageCacheService._internal() {
    print('IMAGE_CACHE: Created new ImageCacheService instance');
  }
  
  /// Ultra-optimized image processing - processes image at lowest possible settings for speed
  Future<File> ultraFastProcessImage(File imageFile, {
    int targetWidth = 600,
    int quality = 30,
  }) async {
    final stopwatch = Stopwatch()..start();
    print('IMAGE_CACHE: Starting ultraFastProcessImage for ${imageFile.path}');
    
    try {
      final String cacheKey = imageFile.path;
      
      // Check if we've already processed this image
      if (_processedImagesCache.containsKey(cacheKey)) {
        print('IMAGE_CACHE: Found image in memory cache! Reusing...');
        
        // Create a temporary file with the cached bytes
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/fast_${const Uuid().v4()}.jpg');
        await tempFile.writeAsBytes(_processedImagesCache[cacheKey]!);
        
        print('IMAGE_CACHE: Returned cached image in ${stopwatch.elapsedMilliseconds}ms');
        return tempFile;
      }
      
      // Process the image in an isolate for maximum performance
      print('IMAGE_CACHE: Image not in cache, processing in isolate');
      final Uint8List? processedBytes = await compute(_minimalProcessingNew, {
        'bytes': await imageFile.readAsBytes(),
        'targetWidth': targetWidth,
        'quality': quality,
      });
      
      if (processedBytes == null) {
        // If processing failed, return original file
        print('IMAGE_CACHE: Processing failed, returning original');
        return imageFile;
      }
      
      // Cache the processed bytes in memory
      print('IMAGE_CACHE: Caching processed result (${processedBytes.length ~/ 1024}KB)');
      _addToProcessedCache(cacheKey, processedBytes);
      
      // Create a new file with the processed bytes
      final String tempPath = imageFile.path;
      final String extension = path.extension(tempPath).toLowerCase();
      final String newPath = tempPath.replaceFirst(
        extension, 
        '_processed$extension'
      );
      
      final File processedFile = File(newPath);
      await processedFile.writeAsBytes(processedBytes);
      
      print('IMAGE_CACHE: Processed image in ${stopwatch.elapsedMilliseconds}ms');
      stopwatch.stop();
      return processedFile;
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) {
        print('IMAGE_CACHE: Error in ultra-fast image processing: $e');
      }
      // Return original file if processing fails
      return imageFile;
    }
  }

  /// Fast image processing - minimal operations for speed
  Future<File> fastProcessImage(File imageFile, {
    int quality = 85,
  }) async {
    final stopwatch = Stopwatch()..start();
    print('IMAGE_CACHE: Starting fastProcessImage');
    
    try {
      final String tempPath = imageFile.path;
      final String extension = path.extension(tempPath).toLowerCase();
      final String newPath = tempPath.replaceFirst(
        extension, 
        '_processed$extension'
      );
      
      // Simply copy the file for maximum speed
      final File processedFile = await imageFile.copy(newPath);
      
      print('IMAGE_CACHE: Fast processing complete in ${stopwatch.elapsedMilliseconds}ms');
      stopwatch.stop();
      return processedFile;
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) {
        print('IMAGE_CACHE: Error in fast image processing: $e');
      }
      // Return original file if processing fails
      return imageFile;
    }
  }

  /// Caches an image file and returns the cache key
  Future<String> cacheImage(File imageFile) async {
    final String cacheKey = 'scan_${const Uuid().v4()}';
    final String extension = path.extension(imageFile.path).toLowerCase();
    
    // Store the file in cache
    await _cacheManager.putFile(
      cacheKey,
      await imageFile.readAsBytes(),
      key: cacheKey,
      fileExtension: extension.isEmpty ? 'jpg' : extension.substring(1),
    );
    
    // Store the mapping in memory for quick lookup
    _memoryCache[imageFile.path] = cacheKey;
    
    return cacheKey;
  }

  /// Gets an image from cache by original file path
  Future<File?> getImageByOriginalPath(String originalPath) async {
    final cacheKey = _memoryCache[originalPath];
    if (cacheKey == null) return null;
    
    return getImageByCacheKey(cacheKey);
  }

  /// Gets an image from cache by cache key
  Future<File?> getImageByCacheKey(String cacheKey) async {
    try {
      final fileInfo = await _cacheManager.getFileFromCache(cacheKey);
      return fileInfo?.file;
    } catch (e) {
      print('Error retrieving cached image: $e');
      return null;
    }
  }

  /// Gets image bytes from cache by cache key
  Future<Uint8List?> getImageBytesByCacheKey(String cacheKey) async {
    final file = await getImageByCacheKey(cacheKey);
    if (file == null) return null;
    
    try {
      return await file.readAsBytes();
    } catch (e) {
      print('Error reading cached image bytes: $e');
      return null;
    }
  }

  /// Pre-processes and caches an image with specific dimensions and quality - optimized version
  Future<String> processCacheImage(
    File imageFile, {
    int maxWidth = 1200,
    int quality = 80,
  }) async {
    final stopwatch = Stopwatch()..start();
    print('IMAGE_CACHE: Starting processCacheImage for ${imageFile.path}');
    
    try {
      final String cacheKey = 'processed_${imageFile.path}';
      
      // Check if we already have this processed image in memory cache
      if (_processedImagesCache.containsKey(cacheKey)) {
        // Create a temporary file with the cached bytes
        print('IMAGE_CACHE: Found in memory cache');
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/cached_${const Uuid().v4()}.jpg');
        await tempFile.writeAsBytes(_processedImagesCache[cacheKey]!);
        
        print('IMAGE_CACHE: Retrieved from cache in ${stopwatch.elapsedMilliseconds}ms');
        stopwatch.stop();
        return await cacheImage(tempFile);
      }
      
      // Process the image in an isolate for better performance
      print('IMAGE_CACHE: Not in cache, processing in isolate');
      final bytes = await imageFile.readAsBytes();
      print('IMAGE_CACHE: Original image size: ${bytes.length ~/ 1024}KB');
      
      final Uint8List? processedBytes = await compute(_minimalProcessingNew, {
        'bytes': bytes,
        'maxWidth': maxWidth,
        'quality': quality,
      });
      
      if (processedBytes == null) {
        // If processing fails, just cache the original
        print('IMAGE_CACHE: Processing failed, using original');
        stopwatch.stop();
        return await cacheImage(imageFile);
      }
      
      print('IMAGE_CACHE: Processed in ${stopwatch.elapsedMilliseconds}ms, result size: ${processedBytes.length ~/ 1024}KB');
      
      // Cache the processed bytes in memory for faster future access
      _addToProcessedCache(cacheKey, processedBytes);
      
      // Create a temporary file with the processed bytes
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/processed_${const Uuid().v4()}.jpg');
      await tempFile.writeAsBytes(processedBytes);
      
      // Cache the processed file
      print('IMAGE_CACHE: Total processing time: ${stopwatch.elapsedMilliseconds}ms');
      stopwatch.stop();
      return await cacheImage(tempFile);
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) {
        print('IMAGE_CACHE: Error processing image: $e');
      }
      // If processing fails, just cache the original
      return await cacheImage(imageFile);
    }
  }

  /// Clears all cached images
  Future<void> clearCache() async {
    print('IMAGE_CACHE: Clearing cache');
    await _cacheManager.emptyCache();
    _memoryCache.clear();
    _processedImagesCache.clear();
  }
  
  /// Returns cache info
  Future<int> getCacheSize() async {
    // The getStats method is not available in this version of DefaultCacheManager
    // Return an estimate based on memory cache size
    int estimatedSize = 0;
    
    // Calculate size from memory cache
    for (final bytes in _memoryCache.values) {
      estimatedSize += bytes.length;
    }
    
    // Calculate size from processed images cache
    for (final bytes in _processedImagesCache.values) {
      estimatedSize += bytes.length;
    }
    
    return estimatedSize;
  }
  
  /// Add processed image to in-memory cache with size management
  void _addToProcessedCache(String key, Uint8List bytes) {
    // Remove oldest entry if cache is full
    if (_processedImagesCache.length >= _maxProcessedCacheSize) {
      final oldestKey = _processedImagesCache.keys.first;
      _processedImagesCache.remove(oldestKey);
      print('IMAGE_CACHE: Cache full, removed oldest entry');
    }
    
    // Add new entry
    _processedImagesCache[key] = bytes;
    print('IMAGE_CACHE: Added to memory cache: $key, size: ${bytes.length ~/ 1024}KB');
  }
}

/// Process image in background isolate with minimum settings for maximum speed
Uint8List? _minimalProcessing(Map<String, dynamic> params) {
  try {
    final Uint8List bytes = params['bytes'] as Uint8List;
    final int targetWidth = params['targetWidth'] as int;
    final int quality = params['quality'] as int;
    
    // Decode with fastest settings
    final img.Image? original = img.decodeImage(bytes);
    if (original == null) return null;
    
    // Resize with fastest interpolation
    final img.Image resized = img.copyResize(
      original,
      width: targetWidth,
      height: (targetWidth * original.height / original.width).round(),
      interpolation: img.Interpolation.nearest, // Fastest interpolation
    );
    
    // Encode with low quality for speed
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  } catch (e) {
    print('Error in minimal image processing: $e');
    return null;
  }
}

/// Extremely optimized image processing function
Uint8List? _minimalProcessingNew(Map<String, dynamic> params) {
  final stopwatch = Stopwatch()..start();
  print('ISOLATE: Starting image processing');
  
  try {
    final Uint8List bytes = params['bytes'] as Uint8List;
    final int targetWidth = params['targetWidth'] ?? 600; // Default to ultra-low resolution
    final int quality = params['quality'] ?? 30; // Default to very low quality
    
    print('ISOLATE: Input image size: ${bytes.length ~/ 1024}KB');
    
    // Decode with fastest settings
    final decodeStart = stopwatch.elapsedMilliseconds;
    final img.Image? original = img.decodeImage(bytes);
    if (original == null) {
      print('ISOLATE: Failed to decode image');
      return null;
    }
    
    print('ISOLATE: Decoded ${original.width}x${original.height} in ${stopwatch.elapsedMilliseconds - decodeStart}ms');
    
    // Skip resize if already small enough
    final img.Image resizedImage;
    if (original.width <= targetWidth) {
      resizedImage = original;
      print('ISOLATE: Image already small enough, skipping resize');
    } else {
      final resizeStart = stopwatch.elapsedMilliseconds;
      // Calculate dimensions while maintaining aspect ratio
      final double aspectRatio = original.width / original.height;
      final int newHeight = (targetWidth / aspectRatio).round();
      
      // Ultra-fast resize with lowest quality interpolation
      resizedImage = img.copyResize(
        original,
        width: targetWidth,
        height: newHeight,
        interpolation: img.Interpolation.nearest, // Fastest possible
      );
      
      print('ISOLATE: Resized to ${targetWidth}x$newHeight in ${stopwatch.elapsedMilliseconds - resizeStart}ms');
    }
    
    // Encode with very low quality
    final encodeStart = stopwatch.elapsedMilliseconds;
    final result = Uint8List.fromList(img.encodeJpg(
      resizedImage,
      quality: quality, // Very low quality for max speed
    ));
    
    print('ISOLATE: Encoded in ${stopwatch.elapsedMilliseconds - encodeStart}ms, result size: ${result.length ~/ 1024}KB');
    print('ISOLATE: Total processing time: ${stopwatch.elapsedMilliseconds}ms');
    
    return result;
  } catch (e) {
    print('ISOLATE: Error in image processing: $e');
    return null;
  }
}

/// Process image in background isolate
Uint8List? _processImageInBackground(Map<String, dynamic> params) {
  try {
    final Uint8List bytes = params['bytes'] as Uint8List;
    final int maxWidth = params['maxWidth'] as int;
    final int quality = params['quality'] as int;
    
    // Decode image
    final img.Image? original = img.decodeImage(bytes);
    if (original == null) return null;
    
    // Check if we need to resize
    img.Image processed = original;
    if (original.width > maxWidth) {
      processed = img.copyResize(
        original,
        width: maxWidth,
        height: (maxWidth * original.height / original.width).round(),
        interpolation: img.Interpolation.average,
      );
    }
    
    // Optimize brightness and contrast for better scan quality
    processed = img.adjustColor(
      processed,
      brightness: 0.05, // Slightly increase brightness
      contrast: 1.1, // Slightly increase contrast
      saturation: 0.9, // Slightly reduce saturation for document-like appearance
    );
    
    // Encode with specified quality
    return Uint8List.fromList(img.encodeJpg(processed, quality: quality));
  } catch (e) {
    print('Error in image processing: $e');
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