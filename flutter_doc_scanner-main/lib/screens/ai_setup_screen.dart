import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/offline_gemma_service.dart';
import '../services/env_service.dart';

class AISetupScreen extends StatefulWidget {
  @override
  _AISetupScreenState createState() => _AISetupScreenState();
}

class _AISetupScreenState extends State<AISetupScreen> {
  final OfflineGemmaService _gemmaService = OfflineGemmaService();
  final TextEditingController _tokenController = TextEditingController();
  final EnvService _envService = EnvService();
  
  bool _isDownloading = false;
  bool _isModelReady = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';
  String _progressDetails = '';
  
  @override
  void initState() {
    super.initState();
    _initializeWithEnvToken();
    _checkModelStatus();
  }
  
  /// Initialize with token from environment if available
  void _initializeWithEnvToken() {
    final envToken = _envService.huggingFaceToken;
    if (envToken.isNotEmpty) {
      _tokenController.text = envToken;
      debugPrint('🔑 Pre-filled token from environment');
    }
  }
  
  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }
  
  Future<void> _checkModelStatus() async {
    try {
      final isDownloaded = await _gemmaService.isModelDownloaded();
      setState(() {
        _isModelReady = isDownloaded;
        _statusMessage = isDownloaded 
            ? '✅ AI Model Ready - Offline summarization available!'
            : '📥 AI Model needed for offline summarization';
        _progressDetails = isDownloaded 
            ? 'You can now summarize PDFs completely offline!' 
            : 'Download once, use forever - no internet needed after setup';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error checking model status';
        _progressDetails = 'Please try again or check your device storage';
      });
    }
  }
  
  /// Handle corrupted model file by deleting and offering re-download
  Future<void> _handleCorruptedModel() async {
    try {
      await _gemmaService.deleteModel();
      setState(() {
        _isModelReady = false;
        _statusMessage = '🗑️ Corrupted model file deleted';
        _progressDetails = 'Please download the model again';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error handling corrupted model';
        _progressDetails = 'Please restart the app and try again';
      });
    }
  }
  
  Future<void> _downloadModel() async {
    // Use environment token if available, otherwise use user input
    String token = _tokenController.text.trim();
    if (token.isEmpty) {
      token = _envService.huggingFaceToken;
    }
    
    if (token.isEmpty) {
      _showError('Please enter your Hugging Face token or configure .env file');
      return;
    }
    
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });
    
    try {
      debugPrint('🔑 Using token: ${token.substring(0, 10)}...');
      
      await _gemmaService.downloadModel(
        token,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _statusMessage = status;
              
              if (progress < 1.0) {
                _progressDetails = 'This may take 5-15 minutes depending on your connection...';
              } else {
                _progressDetails = 'Setup complete! You can now use AI offline.';
              }
            });
          }
        },
      );
      
      if (mounted) {
        setState(() {
          _isModelReady = true;
        });
        
        // Show success dialog
        _showSuccessDialog();
      }
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '❌ Download failed';
          _progressDetails = e.toString().contains('403') 
              ? 'Invalid token or access denied. Please check your Hugging Face token.' 
              : 'Error: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }
  
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('AI Setup Complete!'),
          ],
        ),
        content: Text(
          'Gemma 3n model is now ready for offline PDF summarization. '
          'You can summarize documents without any internet connection!',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(true); // Return to main app
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF504AF2),
            ),
            child: Text('Start Using AI', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  void _showInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('How to get Hugging Face Token'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Follow these steps:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              _buildInstructionStep('1', 'Go to huggingface.co'),
              _buildInstructionStep('2', 'Sign up or log in to your account'),
              _buildInstructionStep('3', 'Click your profile → Settings'),
              _buildInstructionStep('4', 'Go to "Access Tokens" tab'),
              _buildInstructionStep('5', 'Click "New Token"'),
              _buildInstructionStep('6', 'Select "Read" permission'),
              _buildInstructionStep('7', 'Copy and paste the token here'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(0xFF504AF2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D062C), Color(0xFF282467), Color(0xFF504AF2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.smart_toy, color: Colors.white, size: 32),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'AI Setup',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 32),
                
                // Status Card
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isModelReady ? Icons.check_circle : Icons.download,
                            color: _isModelReady ? Colors.green : Colors.white,
                            size: 24,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Offline AI Status',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _progressDetails,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                      
                      if (_isDownloading) ...[
                        SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF504AF2)),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '${(_downloadProgress * 100).toInt()}% complete',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                if (!_isModelReady && !_isDownloading) ...[
                  SizedBox(height: 32),
                  
                  // Model Info Card
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'About Gemma 2B AI',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Text(
                          '• 2B parameter AI model optimized for mobile\n'
                          '• Size: ~${OfflineGemmaService.MODEL_SIZE_DISPLAY} (one-time download)\n'
                          '• Works completely offline after setup\n'
                          '• Provides intelligent PDF summaries\n'
                          '• Processes documents privately on your device',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  // Instructions Card
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.key, color: Colors.orange),
                            SizedBox(width: 8),
                            Text(
                              'Hugging Face Token Required',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Spacer(),
                            TextButton(
                              onPressed: _showInstructions,
                              child: Text(
                                'Instructions',
                                style: TextStyle(color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          _envService.isConfigured 
                            ? 'Token loaded from environment (.env file). Ready to download!'
                            : 'A free Hugging Face account is needed to download the AI model. The token is only used once for download.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                        if (_envService.isConfigured) ...[
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Environment configured',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  // Token Input
                  Text(
                    'Hugging Face Token',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _tokenController,
                    decoration: InputDecoration(
                      hintText: 'hf_xxxxxxxxxxxxxxxxxx',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      prefixIcon: Icon(Icons.vpn_key, color: Colors.white.withOpacity(0.7)),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.paste, color: Colors.white.withOpacity(0.7)),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _tokenController.text = data!.text!;
                          }
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Color(0xFF504AF2)),
                      ),
                    ),
                    style: TextStyle(color: Colors.white),
                    obscureText: true,
                  ),
                  
                  SizedBox(height: 24),
                  
                  // Download Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isDownloading ? null : _downloadModel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF504AF2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download, color: Colors.white),
                          SizedBox(width: 12),
                          Text(
                            'Download AI Model (${OfflineGemmaService.MODEL_SIZE_DISPLAY})',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                
                if (_isModelReady) ...[
                  SizedBox(height: 32),
                  
                  // Success Card
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 48),
                        SizedBox(height: 16),
                        Text(
                          'AI Ready!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'You can now summarize PDFs completely offline. Look for the robot icon in PDF preview.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Start Using AI',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                SizedBox(height: 32),
                
                // Privacy Info
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security, color: Colors.green),
                          SizedBox(width: 12),
                          Text(
                            'Privacy & Security',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '✓ All processing happens on your device\n'
                        '✓ Documents never leave your phone\n'
                        '✓ Works completely offline after setup\n'
                        '✓ No data sent to external servers',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}