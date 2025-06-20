import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class DriveService {
  final _googleSignIn = GoogleSignIn.standard(scopes: [
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveScope,
  ]);

  Future<drive.DriveApi?> _getDriveApi() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;

    final auth = await account.authHeaders;
    final client = GoogleAuthClient(auth);
    return drive.DriveApi(client);
  }

  Future<String?> uploadFile(File file, String filename) async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;

      final media = drive.Media(
        file.openRead(),
        await file.length(),
        contentType: 'image/jpeg',
      );

      final driveFile = drive.File()
        ..name = filename
        ..mimeType = 'image/jpeg';

      final result = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
        $fields: 'id',
      );

      return result.id;
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  Future<String?> createFolder(String name) async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;

      final folder = drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder';

      final result = await driveApi.files.create(folder, $fields: 'id');
      return result.id;
    } catch (e) {
      print('Error creating folder: $e');
      return null;
    }
  }

  Future<void> moveFile(String fileId, String folderId) async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return;

      // Get the file's current parents
      final file = await driveApi.files.get(fileId, $fields: 'parents');
      final previousParents = file.parents?.join(',') ?? '';

      // Move the file to the new folder
      await driveApi.files.update(
        drive.File(),
        fileId,
        addParents: folderId,
        removeParents: previousParents,
        $fields: 'id, parents',
      );
    } catch (e) {
      print('Error moving file: $e');
    }
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
} 