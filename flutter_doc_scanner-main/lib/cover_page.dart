import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoverPageData {
  String name;
  String id;
  String course;
  String section;
  String facultyInitial;
  String submittedTo;
  DateTime submissionDate;

  CoverPageData({
    this.name = '',
    this.id = '',
    this.course = '',
    this.section = '',
    this.facultyInitial = '',
    this.submittedTo = '',
    DateTime? submissionDate,
  }) : submissionDate = submissionDate ?? DateTime.now();

  // Convert to Map for storage
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'id': id,
      'course': course,
      'section': section,
      'facultyInitial': facultyInitial,
      'submittedTo': submittedTo,
      'submissionDate': submissionDate.toIso8601String(),
    };
  }

  // Create from Map for retrieval
  factory CoverPageData.fromMap(Map<String, dynamic> map) {
    return CoverPageData(
      name: map['name'] ?? '',
      id: map['id'] ?? '',
      course: map['course'] ?? '',
      section: map['section'] ?? '',
      facultyInitial: map['facultyInitial'] ?? '',
      submittedTo: map['submittedTo'] ?? '',
      submissionDate: map['submissionDate'] != null 
          ? DateTime.parse(map['submissionDate']) 
          : DateTime.now(),
    );
  }

  // Save to SharedPreferences
  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', name);
    await prefs.setString('id', id);
    await prefs.setString('course', course);
    await prefs.setString('section', section);
    await prefs.setString('facultyInitial', facultyInitial);
    await prefs.setString('submittedTo', submittedTo);
    await prefs.setString('submissionDate', submissionDate.toIso8601String());
  }

  // Load from SharedPreferences
  static Future<CoverPageData> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return CoverPageData(
      name: prefs.getString('name') ?? '',
      id: prefs.getString('id') ?? '',
      course: prefs.getString('course') ?? '',
      section: prefs.getString('section') ?? '',
      facultyInitial: prefs.getString('facultyInitial') ?? '',
      submittedTo: prefs.getString('submittedTo') ?? '',
      submissionDate: prefs.getString('submissionDate') != null 
          ? DateTime.parse(prefs.getString('submissionDate')!) 
          : DateTime.now(),
    );
  }
}

class CoverPageScreen extends StatefulWidget {
  final List<dynamic> scannedDocuments;
  final VoidCallback? onComplete;

  const CoverPageScreen({
    Key? key, 
    required this.scannedDocuments,
    this.onComplete,
  }) : super(key: key);

  @override
  _CoverPageScreenState createState() => _CoverPageScreenState();
}

class _CoverPageScreenState extends State<CoverPageScreen> {
  late CoverPageData coverPageData;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    coverPageData = await CoverPageData.loadFromPrefs();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _generatePDFWithCoverPage() async {
    // Save the form data
    await coverPageData.saveToPrefs();

    // Create a PDF document
    final pdf = pw.Document();
    
    // Load logo image
    final ByteData logoData = await rootBundle.load('assets/nsu_logo.png');
    final Uint8List logoBytes = logoData.buffer.asUint8List();
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes);

    // Add cover page
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: [
                pw.SizedBox(height: 50),
                pw.Image(logoImage, width: 100, height: 100),
                pw.SizedBox(height: 20),
                pw.Text('North South University', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text('Department of Electrical and Computer Engineering', style: pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 40),
                pw.Row(
                  children: [
                    pw.Text('Name: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(coverPageData.name),
                  ],
                ),
                pw.Row(
                  children: [
                    pw.Text('ID: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(coverPageData.id),
                  ],
                ),
                pw.Row(
                  children: [
                    pw.Text('Course: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(coverPageData.course),
                  ],
                ),
                pw.Row(
                  children: [
                    pw.Text('Section: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(coverPageData.section),
                  ],
                ),
                pw.SizedBox(height: 40),
                pw.Text('ASSIGNMENT', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                pw.Row(
                  children: [
                    pw.Text('Submitted To: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(coverPageData.submittedTo),
                  ],
                ),
                pw.Row(
                  children: [
                    pw.Text('Submission Date: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('${coverPageData.submissionDate.day}/${coverPageData.submissionDate.month}/${coverPageData.submissionDate.year}'),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    // Add scanned document pages
    // This will need to be implemented based on how documents are returned
    if (widget.scannedDocuments is List) {
      for (var document in widget.scannedDocuments) {
        if (document is String && document.startsWith('/')) {
          // Assume it's a file path
          final File file = File(document);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final image = pw.MemoryImage(bytes);
            pdf.addPage(
              pw.Page(
                build: (pw.Context context) {
                  return pw.Center(
                    child: pw.Image(image),
                  );
                },
              ),
            );
          }
        }
      }
    }
    
    // Save the document
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/document_with_cover.pdf');
    await file.writeAsBytes(await pdf.save());
    
    // Notify completion
    if (widget.onComplete != null) {
      widget.onComplete!();
    }

    // Navigate back or to preview page
    Navigator.pop(context, file.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Cover Page')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Create Cover Page'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // NSU Logo
              Image.asset('assets/nsu_logo.png', height: 100),
              SizedBox(height: 16),
              
              // Title
              Text(
                'North South University',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              Text(
                'Department of Electrical and Computer Engineering',
                style: TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              
              // Student Information
              TextFormField(
                initialValue: coverPageData.name,
                decoration: InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => coverPageData.name = value,
                validator: (value) => value!.isEmpty ? 'Please enter your name' : null,
              ),
              SizedBox(height: 16),
              
              TextFormField(
                initialValue: coverPageData.id,
                decoration: InputDecoration(
                  labelText: 'ID',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => coverPageData.id = value,
                validator: (value) => value!.isEmpty ? 'Please enter your ID' : null,
              ),
              SizedBox(height: 16),
              
              TextFormField(
                initialValue: coverPageData.course,
                decoration: InputDecoration(
                  labelText: 'Course',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => coverPageData.course = value,
              ),
              SizedBox(height: 16),
              
              TextFormField(
                initialValue: coverPageData.section,
                decoration: InputDecoration(
                  labelText: 'Section',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => coverPageData.section = value,
              ),
              SizedBox(height: 16),
              
              TextFormField(
                initialValue: coverPageData.facultyInitial,
                decoration: InputDecoration(
                  labelText: 'Faculty Initial (up to 5 digits)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => coverPageData.facultyInitial = value,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(5),
                ],
              ),
              SizedBox(height: 32),
              
              Text(
                'ASSIGNMENT',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              
              TextFormField(
                initialValue: coverPageData.submittedTo,
                decoration: InputDecoration(
                  labelText: 'Submitted To',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => coverPageData.submittedTo = value,
              ),
              SizedBox(height: 16),
              
              // Submission Date (with date picker)
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: coverPageData.submissionDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      coverPageData.submissionDate = picked;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Submission Date',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    '${coverPageData.submissionDate.day}/${coverPageData.submissionDate.month}/${coverPageData.submissionDate.year}',
                  ),
                ),
              ),
              SizedBox(height: 32),
              
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _generatePDFWithCoverPage();
                  }
                },
                child: Text('Generate PDF with Cover Page'),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 