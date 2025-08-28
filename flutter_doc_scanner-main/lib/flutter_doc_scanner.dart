import 'package:flutter/foundation.dart';
import 'flutter_doc_scanner_platform_interface.dart';
export 'cover_page.dart';

/// Main plugin interface with optimized settings for better performance
class FlutterDocScanner {
  Future<String?> getPlatformVersion() {
    return FlutterDocScannerPlatform.instance.getPlatformVersion();
  }

  /// Get scan documents with default optimized settings
  Future<dynamic> getScanDocuments({int page = 4}) {
    return FlutterDocScannerPlatform.instance.getScanDocuments(page);
  }

  /// Get scanned documents as images with optimized parameters
  ///
  /// Uses lower resolution (600) and quality (60) by default for better performance
  Future<dynamic> getScannedDocumentAsImages({
    int page = 4,
    int maxResolution = 600, // Lower default resolution
    int quality = 60, // Lower default quality
  }) {
    print('FLUTTER_DOC_SCANNER: Starting optimized image scanning with maxResolution=$maxResolution, quality=$quality');
    return FlutterDocScannerPlatform.instance.getScannedDocumentAsImages(
      page,
      maxResolution: maxResolution,
      quality: quality,
    );
  }

  /// Get scanned documents as PDF with optimized parameters
  ///
  /// Uses lower resolution (600) and quality (60) by default for better performance
  Future<dynamic> getScannedDocumentAsPdf({
    int page = 4,
    int maxResolution = 600, // Lower default resolution
    int quality = 60, // Lower default quality
  }) {
    print('FLUTTER_DOC_SCANNER: Starting optimized PDF scanning with maxResolution=$maxResolution, quality=$quality');
    return FlutterDocScannerPlatform.instance.getScannedDocumentAsPdf(
      page,
      maxResolution: maxResolution,
      quality: quality,
    );
  }

  /// Get scan documents URI with optimized processing
  ///
  /// This is the recommended method for Android devices
  Future<dynamic> getScanDocumentsUri({
    int page = 4,
    int maxResolution = 600, // Lower default resolution
    int quality = 60, // Lower default quality
  }) {
    print('FLUTTER_DOC_SCANNER: Starting optimized URI scanning with maxResolution=$maxResolution, quality=$quality');
    if (defaultTargetPlatform == TargetPlatform.android) {
      return FlutterDocScannerPlatform.instance.getScanDocumentsUri(
        page,
        maxResolution: maxResolution,
        quality: quality,
      );
    } else {
      return Future.error(
          "Currently, this feature is supported only on Android Platform");
    }
  }

  /// Open system file picker at ScanMate folder for PDF selection
  Future<dynamic> pickPdfFromScanMate() {
    return FlutterDocScannerPlatform.instance.pickPdfFromScanMate();
  }
}
