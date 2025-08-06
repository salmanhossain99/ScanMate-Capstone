import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'screens/sign_in_screen.dart';
import 'screens/home_screen.dart';
import 'package:flutter_doc_scanner/services/image_cache_service.dart';

// Custom theme colors
class AppColors {
  // Updated gradient colors
  static const gradientStart = Color(0xFF0D062C); // Dark blue start
  static const gradientMiddle = Color(0xFF282467); // Middle purple
  static const gradientEnd = Color(0xFF504AF2); // Bright purple end
  
  // Deep blue colors for cover page
  static const deepBlueStart = Color(0xFF1E3A8A);
  static const deepBlueEnd = Color(0xFF3B82F6);
  
  static const primary = gradientStart;
  static const secondary = gradientMiddle;
  static const background = gradientStart;
  static const cardBackground = Colors.white;
  static const text = Colors.white;
  static const cardText = gradientStart;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Initialize cache service
  final cacheService = ImageCacheService();
  
  // Clear previous cache on startup for clean state
  await cacheService.clearCache();

  // Add a very obvious log message to verify our changes are loaded
  print('\n\n');
  print('=====================================================');
  print('OPTIMIZED CODE IS LOADED - PDF GENERATION SHOULD BE FAST');
  print('=====================================================');
  print('\n\n');
  
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
