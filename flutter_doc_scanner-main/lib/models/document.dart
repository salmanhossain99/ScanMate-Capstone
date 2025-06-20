import 'package:flutter/material.dart';

class Document {
  final String id;
  final String title;
  final List<DocumentPage> pages;
  final DateTime createdAt;
  final List<String> tags;
  final DocumentType type;
  final String? driveId;  // Google Drive file ID

  Document({
    required this.id,
    required this.title,
    required this.pages,
    required this.createdAt,
    this.tags = const [],
    this.type = DocumentType.other,
    this.driveId,
  });

  String get firstPagePath => pages.isNotEmpty ? pages.first.path : '';

  Document copyWith({
    String? id,
    String? title,
    List<DocumentPage>? pages,
    DateTime? createdAt,
    List<String>? tags,
    DocumentType? type,
    String? driveId,
  }) {
    return Document(
      id: id ?? this.id,
      title: title ?? this.title,
      pages: pages ?? this.pages,
      createdAt: createdAt ?? this.createdAt,
      tags: tags ?? this.tags,
      type: type ?? this.type,
      driveId: driveId ?? this.driveId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'pages': pages.map((page) => page.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'tags': tags,
      'type': type.toString(),
      'driveId': driveId,
    };
  }

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String,
      title: json['title'] as String,
      pages: (json['pages'] as List).map((page) => DocumentPage.fromJson(page)).toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      tags: List<String>.from(json['tags'] as List),
      type: DocumentType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => DocumentType.other,
      ),
      driveId: json['driveId'] as String?,
    );
  }
}

class DocumentPage {
  final String path;
  final int pageNumber;
  final String? driveId;

  DocumentPage({
    required this.path,
    required this.pageNumber,
    this.driveId,
  });

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'pageNumber': pageNumber,
      'driveId': driveId,
    };
  }

  factory DocumentPage.fromJson(Map<String, dynamic> json) {
    return DocumentPage(
      path: json['path'] as String,
      pageNumber: json['pageNumber'] as int,
      driveId: json['driveId'] as String?,
    );
  }
}

enum DocumentType {
  receipt,
  invoice,
  id,
  passport,
  other,
}

extension DocumentTypeExtension on DocumentType {
  String get displayName {
    switch (this) {
      case DocumentType.receipt:
        return 'Receipt';
      case DocumentType.invoice:
        return 'Invoice';
      case DocumentType.id:
        return 'ID Card';
      case DocumentType.passport:
        return 'Passport';
      case DocumentType.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case DocumentType.receipt:
        return Icons.receipt_long;
      case DocumentType.invoice:
        return Icons.description;
      case DocumentType.id:
        return Icons.badge;
      case DocumentType.passport:
        return Icons.book;
      case DocumentType.other:
        return Icons.article;
    }
  }
} 