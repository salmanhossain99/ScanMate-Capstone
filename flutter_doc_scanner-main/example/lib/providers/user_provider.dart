import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider extends ChangeNotifier {
  String? _name;
  String? _email;
  String? _studentId;
  String? _password; // Prototype only; do not use in production
  bool _isDarkMode = false;
  bool _isGuest = false;

  String? get name => _name;
  String? get email => _email;
  String? get studentId => _studentId;
  bool get isDarkMode => _isDarkMode;
  bool get isGuest => _isGuest;
  static const int apkScanLimit = 200;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('user_name');
    _email = prefs.getString('user_email');
    _studentId = prefs.getString('user_id');
    _password = prefs.getString('user_password');
    _isGuest = prefs.getBool('user_is_guest') ?? false;
    _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    notifyListeners();
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String studentId,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_name', name);
    await prefs.setString('account_email', email);
    await prefs.setString('account_id', studentId);
    await prefs.setString('account_password', password);

    // Log the user in immediately
    await prefs.setString('user_name', name);
    await prefs.setString('user_email', email);
    await prefs.setString('user_id', studentId);
    await prefs.setString('user_password', password);
    await prefs.setBool('user_is_guest', false);

    _name = name;
    _email = email;
    _studentId = studentId;
    _password = password;
    _isGuest = false;
    notifyListeners();
  }

  Future<bool> signInWithPassword(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('account_email');
    final savedPassword = prefs.getString('account_password');
    if (savedEmail == email && savedPassword == password) {
      final name = prefs.getString('account_name') ?? '';
      final studentId = prefs.getString('account_id') ?? '';
      await prefs.setString('user_name', name);
      await prefs.setString('user_email', email);
      await prefs.setString('user_id', studentId);
      await prefs.setString('user_password', password);
      await prefs.setBool('user_is_guest', false);
      _name = name;
      _email = email;
      _studentId = studentId;
      _password = password;
      _isGuest = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> signInGuest(String name, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    await prefs.setString('user_email', email);
    await prefs.remove('user_password');
    await prefs.setBool('user_is_guest', true);
    _name = name;
    _email = email;
    _studentId = null;
    _password = null;
    _isGuest = true;
    notifyListeners();
  }

  Future<void> updateAccount({
    required String name,
    required String email,
    required String studentId,
    String? password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_name', name);
    await prefs.setString('account_email', email);
    await prefs.setString('account_id', studentId);
    if (password != null && password.isNotEmpty) {
      await prefs.setString('account_password', password);
    }
    // If currently signed in, mirror to user_*
    await prefs.setString('user_name', name);
    await prefs.setString('user_email', email);
    await prefs.setString('user_id', studentId);
    if (password != null && password.isNotEmpty) {
      await prefs.setString('user_password', password);
    }
    _name = name;
    _email = email;
    _studentId = studentId;
    if (password != null && password.isNotEmpty) {
      _password = password;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_name');
    await prefs.remove('user_email');
    await prefs.remove('user_id');
    await prefs.remove('user_password');
    await prefs.setBool('user_is_guest', false);
    _name = null;
    _email = null;
    _studentId = null;
    _password = null;
    _isGuest = false;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = !_isDarkMode;
    await prefs.setBool('is_dark_mode', _isDarkMode);
    notifyListeners();
  }

  Future<String> _photoCountKey() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email') ?? _email ?? 'guest';
    return 'photo_count_${email.toLowerCase()}';
  }

  Future<int> getScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _photoCountKey();
    return prefs.getInt(key) ?? 0;
  }

  Future<bool> hasReachedScanLimit() async {
    final count = await getScanCount();
    return count >= apkScanLimit;
  }

  Future<void> incrementScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _photoCountKey();
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + 1);
  }

  Future<void> incrementScanCountBy(int delta) async {
    if (delta <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final key = await _photoCountKey();
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + delta);
  }
}