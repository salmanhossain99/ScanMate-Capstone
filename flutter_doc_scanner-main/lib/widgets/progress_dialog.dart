import 'package:flutter/material.dart';

/// A progress dialog widget that shows a loading indicator with optional progress value
class ProgressDialog extends StatelessWidget {
  final String message;
  final double? progress;
  final String? processingStage;
  final bool showPercentage;

  const ProgressDialog({
    Key? key,
    required this.message,
    this.progress,
    this.processingStage,
    this.showPercentage = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
        elevation: 8.0,
      backgroundColor: isDarkMode ? Colors.grey[800] : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            if (progress != null) ...[
              // Show progress bar if progress value is provided
              LinearProgressIndicator(
                value: progress,
                backgroundColor: isDarkMode ? Colors.grey[700] : Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 16.0),
            ] else ...[
              // Show circular progress indicator if no progress value
              CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).primaryColor,
                      ),
                    ),
              const SizedBox(height: 16.0),
            ],
              
            // Main message
            Text(
              message,
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 8.0),
            
            // Show processing stage if provided
            if (processingStage != null) ...[
              Text(
                processingStage!,
                style: TextStyle(
                  fontSize: 14.0,
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
                const SizedBox(height: 8.0),
            ],
            
            // Show percentage if requested and progress is provided
            if (showPercentage && progress != null)
                Text(
                '${(progress! * 100).toInt()}%',
                  style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w500,
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[800],
                ),
                ),
              ],
        ),
      ),
    );
  }
}

/// A widget that shows a transparent overlay with processing feedback
class ProcessingOverlay extends StatelessWidget {
  final double progress;
  final String message;
  final String stage;
  
  const ProcessingOverlay({
    Key? key,
    required this.progress,
    required this.message,
    required this.stage,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dimmed background
        Positioned.fill(
          child: Container(
          color: Colors.black54,
          ),
        ),
        
        // Progress indicator and message
        Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
          ),
              ],
      ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress bar
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                
                const SizedBox(height: 16),
                
                // Message
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8),
                
                // Stage description
                Text(
                  stage,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 8),
                
                // Percentage
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
} 