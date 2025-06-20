import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../providers/user_provider.dart';
import 'sign_in_screen.dart';
import 'document_cover_page_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  dynamic _scannedDocuments;

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Request basic permissions
      final storage = await Permission.storage.request();
      final camera = await Permission.camera.request();
      
      // For Android 11 (API level 30) and above
      if (await Permission.manageExternalStorage.shouldShowRequestRationale) {
        final manageStorage = await Permission.manageExternalStorage.request();
        if (!manageStorage.isGranted) {
          if (!mounted) return false;
          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Additional Permission Required'),
              content: const Text('ScanMate needs additional storage permission to save documents. Please enable "All Files Access" in Settings.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ) ?? false;
          
          if (shouldOpenSettings) {
            await openAppSettings();
          }
          return false;
        }
      }
      
      // Check if we have all required permissions
      if (storage.isGranted && camera.isGranted) {
        return true;
      }
      
      // Handle permanently denied permissions
      if (storage.isPermanentlyDenied || camera.isPermanentlyDenied) {
        if (!mounted) return false;
        final shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permissions Required'),
            content: const Text('Storage and Camera permissions are required to scan and save documents. Please enable them in settings.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ) ?? false;
        
        if (shouldOpenSettings) {
          await openAppSettings();
        }
      }
      return false;
    }
    return true;
  }

  Future<String> _createAppFolder() async {
    if (Platform.isAndroid) {
      try {
        // First try to use the Downloads directory
        final directory = Directory('/storage/emulated/0/Download/ScanMate');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        return directory.path;
      } catch (e) {
        // If Downloads directory is not accessible, fallback to app's external storage
        final directory = await getExternalStorageDirectory();
        if (directory == null) throw Exception('Could not access external storage');
        
        // Create the ScanMate folder in the root of external storage
        final newPath = directory.path.replaceAll(RegExp(r'/Android/data/.*'), '/ScanMate');
        final dir = Directory(newPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return newPath;
      }
    } else {
      final directory = await getApplicationDocumentsDirectory();
      final scanMatePath = '${directory.path}/ScanMate';
      final dir = Directory(scanMatePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return scanMatePath;
    }
  }

  Future<void> _saveImage(String imagePath) async {
    try {
      final appFolderPath = await _createAppFolder();
      final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedImagePath = '$appFolderPath/$fileName';
      
      // Copy the image to our app's folder
      await File(imagePath).copy(savedImagePath);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Image saved to: $savedImagePath',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.purple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(8),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _savePDF(dynamic documents) async {
    try {
      final appFolderPath = await _createAppFolder();
      print('Saving to folder: $appFolderPath'); // Debug print
      
      final pdf = pw.Document();

      // If documents is a map with cover page info
      if (documents is Map<String, dynamic>) {
        final coverPageInfo = documents['coverPage'] as Map<String, dynamic>;
        final scannedDocs = documents['documents'] as List;

        // Add cover page
        pdf.addPage(
          pw.Page(
            build: (context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text(
                      'Document Cover Page',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 40),
                  pw.Text(
                    'Student Information',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text('Name: ${coverPageInfo['name']}'),
                  pw.SizedBox(height: 10),
                  pw.Text('Email: ${coverPageInfo['email']}'),
                  pw.SizedBox(height: 10),
                  pw.Text('Student ID: ${coverPageInfo['studentId']}'),
                  pw.SizedBox(height: 10),
                  pw.Text('Course: ${coverPageInfo['courseName']}'),
                  pw.SizedBox(height: 40),
                  pw.Text(
                    'Document Information',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text('Total Pages: ${scannedDocs.length}'),
                  pw.SizedBox(height: 10),
                  pw.Text('Date: ${DateTime.now().toString().split('.')[0]}'),
                ],
              );
            },
          ),
        );

        // Add scanned documents
        for (var image in scannedDocs) {
          try {
            final imageFile = File(image);
            if (await imageFile.exists()) {
              final img = pw.MemoryImage(await imageFile.readAsBytes());
              pdf.addPage(
                pw.Page(
                  build: (context) {
                    return pw.Center(
                      child: pw.Image(img),
                    );
                  },
                ),
              );
            }
          } catch (e) {
            print('Error processing image: $e');
            continue;
          }
        }
      } else if (documents is List) {
        // Handle regular document scanning without cover page
        for (var image in documents) {
          try {
            final imageFile = File(image);
            if (await imageFile.exists()) {
              final img = pw.MemoryImage(await imageFile.readAsBytes());
              pdf.addPage(
                pw.Page(
                  build: (context) {
                    return pw.Center(
                      child: pw.Image(img),
                    );
                  },
                ),
              );
            }
          } catch (e) {
            print('Error processing image: $e');
            continue;
          }
        }
      }

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final file = File('$appFolderPath/ScanMate_$timestamp.pdf');
      print('Saving PDF to: ${file.path}'); // Debug print
      
      await file.writeAsBytes(await pdf.save());
      print('PDF saved successfully'); // Debug print

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PDF saved to: ${file.path}',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.purple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(8),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      print('Error saving PDF: $e'); // Debug print
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> scanDocument() async {
    if (!await _requestPermissions()) {
      return;
    }

    try {
      final scannedDocs = await FlutterDocScanner().getScanDocuments(page: 4);
      
      if (scannedDocs != null && scannedDocs is List && scannedDocs.isNotEmpty) {
        if (!mounted) return;
        
        // Show confirmation dialog
        final shouldSave = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('Save Document'),
            content: Text('${scannedDocs.length} pages scanned. Do you want to save them as PDF?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Save'),
              ),
            ],
          ),
        ) ?? false;

        if (shouldSave) {
          await _savePDF(scannedDocs);
          setState(() {
            _scannedDocuments = scannedDocs;
          });
        }
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error scanning document: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> scanDocumentWithCoverPage() async {
    if (!await _requestPermissions()) {
      print('Permission not granted');
      return;
    }

    try {
      print('Starting document scan...');
      final scannedDocs = await FlutterDocScanner().getScanDocuments(page: 4);
      print('Scan result type: ${scannedDocs.runtimeType}');
      print('Scan result: $scannedDocs');
      
      // Convert the scan result to a list if it's not already
      List<dynamic> documentsList;
      if (scannedDocs is List) {
        documentsList = scannedDocs;
      } else if (scannedDocs is Map) {
        documentsList = [scannedDocs];
      } else {
        print('Invalid scan result type');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid scan result. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (documentsList.isNotEmpty) {
        print('Documents scanned successfully: ${documentsList.length} pages');
        if (!mounted) return;
        
        // Show cover page screen
        print('Navigating to cover page screen...');
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DocumentCoverPageScreen(
              scannedDocuments: documentsList,
            ),
          ),
        );
        print('Cover page result: $result');
        
        // Only save if we got a result back (user didn't cancel)
        if (result != null && result is Map) {
          try {
            print('Preparing to save PDF with cover page...');
            // Show saving indicator
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text('Saving document...'),
                  ],
                ),
                duration: Duration(seconds: 2),
              ),
            );
            
            // Save the PDF
            await _savePDF(result);
            
            // Update state
            setState(() {
              _scannedDocuments = result;
            });
          } catch (e) {
            print('Error saving document: $e');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error saving document: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          print('No result from cover page or user cancelled');
        }
      } else {
        print('No documents scanned or invalid scan result');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No documents scanned. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on PlatformException catch (e) {
      print('Platform Exception: ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error scanning document: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      print('Unexpected error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome ${user.name}',
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Scan & Create Documents',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 2,
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      children: [
                        _MenuCard(
                          icon: Icons.qr_code_scanner,
                          title: 'Scan\nDocument',
                          onTap: () => scanDocument(),
                        ),
                        _MenuCard(
                          icon: Icons.picture_as_pdf,
                          title: 'Scan with\nCover Page',
                          onTap: () => scanDocumentWithCoverPage(),
                        ),
                        _MenuCard(
                          icon: Icons.history,
                          title: 'Recent\nScans',
                          onTap: () {
                            // TODO: Implement history
                          },
                        ),
                        _MenuCard(
                          icon: Icons.settings,
                          title: 'Settings',
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (context) => Container(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: Icon(
                                        user.isDarkMode
                                            ? Icons.dark_mode
                                            : Icons.light_mode,
                                      ),
                                      title: Text(
                                        user.isDarkMode
                                            ? 'Dark Mode'
                                            : 'Light Mode',
                                      ),
                                      trailing: Switch(
                                        value: user.isDarkMode,
                                        onChanged: (_) => user.toggleTheme(),
                                      ),
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.logout),
                                      title: const Text('Sign Out'),
                                      onTap: () {
                                        user.signOut();
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const SignInScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 