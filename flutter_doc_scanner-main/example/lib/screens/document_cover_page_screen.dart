import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_doc_scanner/cover_page.dart';
import 'package:flutter_doc_scanner/screens/optimized_pdf_preview.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

class DocumentCoverPageScreen extends StatefulWidget {
  final List<dynamic> scannedDocuments;

  const DocumentCoverPageScreen({
    Key? key,
    required this.scannedDocuments,
  }) : super(key: key);

  @override
  State<DocumentCoverPageScreen> createState() => _DocumentCoverPageScreenState();
}

class _DocumentCoverPageScreenState extends State<DocumentCoverPageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _courseNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    _nameController.text = userProvider.name ?? '';
    _emailController.text = userProvider.email ?? '';
    _studentIdController.text = '20317';
    _courseNameController.text = 'CSE'; // Auto-populate with CSE
    print('Cover page initialized with ${widget.scannedDocuments.length} documents');
    print('Document types: ${widget.scannedDocuments.map((d) => d.runtimeType).toList()}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _studentIdController.dispose();
    _courseNameController.dispose();
    super.dispose();
  }

  Widget _buildDocumentPreview() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Scanned Documents',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.scannedDocuments.length} pages scanned',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            // Preview of first page if available
            if (widget.scannedDocuments.isNotEmpty && widget.scannedDocuments.first is String)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(widget.scannedDocuments.first as String),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print('Error loading preview: $error');
                    return Container(
                      height: 150,
                      width: double.infinity,
                      color: Colors.grey[200],
                      child: const Icon(Icons.image_not_supported, size: 50),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        final shouldDiscard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard Scan?'),
            content: const Text('Are you sure you want to discard this scan?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ?? false;
        
        if (shouldDiscard && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF1E3A8A), // Deep blue start
                Color(0xFF3B82F6), // Deep blue end
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Custom app bar
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () async {
              final shouldDiscard = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Discard Scan?'),
                  content: const Text('Are you sure you want to discard this scan?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              ) ?? false;
              
                          if (shouldDiscard && context.mounted) {
                  Navigator.pop(context);
              }
            },
          ),
                      const Expanded(
                        child: Text(
                          'Add Cover Page',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48), // Balance the close button
                    ],
                  ),
                ),
                
                // Content area
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(top: 20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(25),
                        topRight: Radius.circular(25),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
          key: _formKey,
                          child: Column(
            children: [
                              const SizedBox(height: 20),
                              
                              // Student information form only
                              _buildStudentInfoForm(),
                              
                              const SizedBox(height: 30),
                              
                              // Generate PDF button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _generatePdfWithCoverPage,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E3A8A), // Deep blue
                                    foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                                  ),
                                  child: const Text(
                                    'Create PDF with Cover Page',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentInfoForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Student Information',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
              color: const Color(0xFF1E3A8A),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _studentIdController,
                        decoration: const InputDecoration(
                          labelText: 'Student ID',
                          prefixIcon: Icon(Icons.badge),
              border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your student ID';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _courseNameController,
                        decoration: const InputDecoration(
                          labelText: 'Course Name',
                          prefixIcon: Icon(Icons.school),
              border: OutlineInputBorder(),
              helperText: 'Auto-populated with CSE, you can change it',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the course name';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
    );
  }

  Future<void> _generatePdfWithCoverPage() async {
                  if (_formKey.currentState!.validate()) {
                    print('Form validated, preparing cover page info');
                    final coverPageInfo = {
                      'name': _nameController.text,
                      'email': _emailController.text,
                      'studentId': _studentIdController.text,
                      'courseName': _courseNameController.text,
                    };
                    
                    // Save the entered info
                    await saveCoverPageInfo(coverPageInfo);
                    
                    // Convert dynamic list to List<String> to ensure compatibility
                    final List<String> imagePaths = widget.scannedDocuments
                        .whereType<String>()
                        .toList();
                    
                    print('\n\n');
                    print('======================================================');
                    print('COVER PAGE: Starting PDF generation with OPTIMIZED METHOD');
                    print('COVER PAGE: Using ${imagePaths.length} images');
                    print('======================================================');
                    print('\n\n');
                    
                    print('Navigating to preview screen with cover page info');
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => OptimizedPdfPreview(
                          pdfPath: imagePaths.first, // Pass the first path as the PDF path
                          documentTitle: 'Scanned Document',
                          allDocumentPaths: imagePaths, // Pass all documents
                        ),
                      ),
                    );
                    
      // Navigate back to home screen after saving
      if (result != null) {
                      if (mounted) {
          // Pop back to home screen (pop twice - once for preview, once for cover page)
          Navigator.of(context).pop();
          Navigator.of(context).pop();
                      }
                    }
                  } else {
                    print('Form validation failed');
                  }
  }
} 