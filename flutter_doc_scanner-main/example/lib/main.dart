import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'screens/sign_in_screen.dart';
import 'screens/home_screen.dart';

// Custom theme colors
class AppColors {
  static const primary = Color(0xFF6B3FA0); // Deep Purple
  static const secondary = Color(0xFF8952D0); // Light Purple
  static const background = Color(0xFF6B3FA0); // Deep Purple
  static const cardBackground = Colors.white;
  static const text = Colors.white;
  static const cardText = Color(0xFF6B3FA0);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => UserProvider()..initialize(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<UserProvider>().isDarkMode;
    final user = context.watch<UserProvider>();

    return MaterialApp(
      title: 'ScanMate',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          background: AppColors.background,
          brightness: isDarkMode ? Brightness.dark : Brightness.light,
        ),
        textTheme: GoogleFonts.poppinsTextTheme().apply(
          bodyColor: isDarkMode ? Colors.white : Colors.black,
          displayColor: isDarkMode ? Colors.white : Colors.black,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: isDarkMode ? Colors.white : Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.poppins(
            color: isDarkMode ? Colors.white : Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          color: isDarkMode ? Colors.grey[800] : Colors.white,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          background: Colors.grey[900]!,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: user.name == null ? const SignInScreen() : const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
