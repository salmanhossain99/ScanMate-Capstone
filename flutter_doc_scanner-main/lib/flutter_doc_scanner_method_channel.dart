import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_doc_scanner_platform_interface.dart';

/// An implementation of [FlutterDocScannerPlatform] that uses method channels.
class MethodChannelFlutterDocScanner extends FlutterDocScannerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_doc_scanner');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<dynamic> getScanDocuments([int page = 1]) async {
    final data = await methodChannel.invokeMethod<dynamic>(
      'getScanDocuments',
      {'page': page},
    );
    return data;
  }

  @override
  Future<dynamic> getScannedDocumentAsImages(
    int page, {
    int maxResolution = 1200,
    int quality = 80,
  }) async {
    final data = await methodChannel.invokeMethod<dynamic>(
      'getScannedDocumentAsImages',
      {
        'page': page,
        'maxResolution': maxResolution,
        'quality': quality,
      },
    );
    return data;
  }

  @override
  Future<dynamic> getScannedDocumentAsPdf(
    int page, {
    int maxResolution = 1200,
    int quality = 80,
  }) async {
    final data = await methodChannel.invokeMethod<dynamic>(
      'getScannedDocumentAsPdf',
      {
        'page': page,
        'maxResolution': maxResolution,
        'quality': quality,
      },
    );
    return data;
  }

  @override
  Future<dynamic> getScanDocumentsUri(
    int page, {
    int maxResolution = 600,
    int quality = 60,
  }) async {
    final data = await methodChannel.invokeMethod<dynamic>(
      'getScanDocumentsUri',
      {
        'page': page,
        'maxResolution': maxResolution,
        'quality': quality,
      },
    );
    return data;
  }

  @override
  Future<dynamic> pickPdfFromScanMate() async {
    final data = await methodChannel.invokeMethod<dynamic>('pickPdfFromScanMate');
    return data;
  }
}
