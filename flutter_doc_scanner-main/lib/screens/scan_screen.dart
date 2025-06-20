import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_doc_scanner/models/document.dart';
import 'package:flutter_doc_scanner/services/drive_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isScanning = false;
  bool _isSaving = false;
  final _scanner = FlutterDocScanner();
  final _driveService = DriveService();
  final List<DocumentPage> _pages = [];
  bool _saveToDrive = false;

  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    try {
      final scannedImages = await _scanner.getScannedDocumentAsImages();
      if (scannedImages != null && scannedImages.isNotEmpty) {
        final appDir = await getApplicationDocumentsDirectory();
        final uuid = const Uuid().v4();
        final now = DateTime.now();

        // Create scans directory if it doesn't exist
        final scanDir = Directory('${appDir.path}/scans');
        if (!await scanDir.exists()) {
          await scanDir.create(recursive: true);
        }

        // Move the scanned image instead of copying
        final pageNumber = _pages.length + 1;
        final imagePath = '${scanDir.path}/${uuid}_$pageNumber.jpg';
        await File(scannedImages.first).rename(imagePath);

        setState(() {
          _pages.add(DocumentPage(
            path: imagePath,
            pageNumber: pageNumber,
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning document: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _saveDocument() async {
    if (_pages.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final document = Document(
        id: const Uuid().v4(),
        title: 'Scan ${DateFormat('yyyy-MM-dd HH:mm').format(now)}',
        pages: List.from(_pages),
        createdAt: now,
      );

      if (_saveToDrive) {
        // Upload pages to Google Drive
        final updatedPages = <DocumentPage>[];
        for (final page in _pages) {
          final driveId = await _driveService.uploadFile(
            File(page.path),
            'Page ${page.pageNumber}.jpg',
          );
          updatedPages.add(DocumentPage(
            path: page.path,
            pageNumber: page.pageNumber,
            driveId: driveId,
          ));
        }

        // Create a folder in Drive and move files there
        final driveFolderId = await _driveService.createFolder(document.title);
        for (final page in updatedPages) {
          await _driveService.moveFile(page.driveId!, driveFolderId);
        }

        document = document.copyWith(
          pages: updatedPages,
          driveId: driveFolderId,
        );
      }

      if (mounted) {
        Navigator.pop(context, document);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving document: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Document'),
        actions: [
          if (_pages.isNotEmpty) ...[
            Switch(
              value: _saveToDrive,
              onChanged: (value) => setState(() => _saveToDrive = value),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isSaving ? null : _saveDocument,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          if (_pages.isEmpty)
            Container(
              color: Colors.black,
              child: const Center(
                child: Text(
                  'Camera Preview',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            )
          else
            GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                final page = _pages[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(page.path),
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          page.pageNumber.toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          if (_isScanning || _isSaving)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _isScanning ? 'Scanning...' : 'Saving to Drive...',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning || _isSaving ? null : _startScan,
        child: Icon(_isScanning ? Icons.hourglass_empty : Icons.camera),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
} 