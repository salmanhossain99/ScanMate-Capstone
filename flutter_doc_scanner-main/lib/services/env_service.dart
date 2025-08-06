import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class EnvService {
  static final EnvService _instance = EnvService._internal();
  factory EnvService() => _instance;
  EnvService._internal();

  bool _isInitialized = false;

  /// Initialize environment variables
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await dotenv.load(fileName: ".env");
      _isInitialized = true;
      debugPrint('✅ Environment variables loaded successfully');
    } catch (e) {
      debugPrint('⚠️ Failed to load .env file: $e');
      debugPrint('💡 Using fallback configuration');
      // App will continue to work without .env file
    }
  }

  /// Get Hugging Face token from environment or fallback
  String get huggingFaceToken {
    final token = dotenv.env['HUGGING_FACE_TOKEN'];
    if (token != null && token.isNotEmpty) {
      debugPrint('🔑 Using Hugging Face token from environment');
      return token;
    }
    
    debugPrint('⚠️ No Hugging Face token found in environment');
    return '';
  }

  /// Get Gemma model URL from environment or use default
  String get gemmaModelUrl {
    final url = dotenv.env['GEMMA_MODEL_URL'];
    if (url != null && url.isNotEmpty) {
      return url;
    }
    
    // Default fallback URL
    return 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task';
  }

  /// Check if environment is properly configured
  bool get isConfigured {
    return _isInitialized && huggingFaceToken.isNotEmpty;
  }

  /// Get all environment variables for debugging
  Map<String, String> get allEnvVars {
    if (!_isInitialized) return {};
    return Map<String, String>.from(dotenv.env);
  }
}
