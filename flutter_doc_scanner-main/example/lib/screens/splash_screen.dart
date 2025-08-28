import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import 'sign_in_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
      lowerBound: 0.9,
      upperBound: 1.1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goNext() {
    final user = context.read<UserProvider>();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => user.name == null ? const SignInScreen() : const HomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _goNext,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0B134B), // deep blue
                Color(0xFF2A1B7E), // deep purple
                Color(0xFF4F46E5), // vivid indigo
              ],
            ),
          ),
          child: Center(
            child: SizedBox(
              width: size.width * 0.72,
              height: size.width * 0.72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _controller.value,
                        child: CustomPaint(
                          size: Size.square(size.width * 0.7),
                          painter: _GlowRingPainter(),
                        ),
                      );
                    },
                  ),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.25),
                          blurRadius: 30,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(28),
                    child: Image.asset(
                      'assets/Scanmatelogo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.38;

    // Outer soft circular glow
    final outerGlow = Paint()
      ..color = const Color(0xFF6D28D9).withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(center, radius, outerGlow);

    // Solid subtle ring
    final ring = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF6D28D9), Color(0xFF4F46E5), Color(0xFF6D28D9)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);
    canvas.drawCircle(center, radius, ring);

    // Inner faint glow fill
    final innerFill = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF4F46E5).withOpacity(0.15), Colors.transparent],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.05));
    canvas.drawCircle(center, radius * 1.02, innerFill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


