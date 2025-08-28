import 'package:flutter/material.dart';

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? Colors.white.withOpacity(0.06) : Colors.white;
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black12;
    final glow = isDark ? const Color(0xFF6D28D9).withOpacity(0.25) : Colors.black12;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutorial'),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B134B), Color(0xFF2A1B7E), Color(0xFF4F46E5)],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StepCard(
            title: 'Important: APK photo limit',
            steps: const [
              'This APK allows up to 200 photos per account (email).',
              'You can capture them across multiple scans or in a single scan.',
              'Once you reach 200 photos, Scan and Cover will be disabled until the final product is launched.'
            ],
            cardBg: cardBg,
            borderColor: borderColor,
            glow: glow,
          ),
          const SizedBox(height: 14),
          _StepCard(
            title: 'Turn images into a PDF',
            steps: const [
              'Tap Cover in the options on the home page',
              'Tap to take the image(s)',
              'Tap Generate Cover Page and add your info',
              'Open PDF Preview — you will see options like edit, AI, share, save',
            ],
            imageAsset: 'assets/pdfpreviewtutorial.jpg',
            cardBg: cardBg,
            borderColor: borderColor,
            glow: glow,
          ),
          const SizedBox(height: 14),
          _StepCard(
            title: 'Reorder pages',
            steps: const [
              'In PDF Preview, switch to Edit',
              'Drag pages to reorder as you like',
            ],
            imageAsset: 'assets/dragtutorial.jpg',
            cardBg: cardBg,
            borderColor: borderColor,
            glow: glow,
          ),
          const SizedBox(height: 14),
          _StepCard(
            title: 'Save and find your PDF',
            steps: const [
              'Tap Save',
              'Your PDF will be saved in Downloads/ScanMate',
            ],
            cardBg: cardBg,
            borderColor: borderColor,
            glow: glow,
          ),
          const SizedBox(height: 20),
          _HelpBox(cardBg: cardBg, borderColor: borderColor, glow: glow),
          const SizedBox(height: 16),
          _CreditsCard(cardBg: cardBg, borderColor: borderColor, glow: glow),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String title;
  final List<String> steps;
  final String? imageAsset;
  final Color cardBg;
  final Color borderColor;
  final Color glow;

  const _StepCard({
    required this.title,
    required this.steps,
    required this.cardBg,
    required this.borderColor,
    required this.glow,
    this.imageAsset,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [BoxShadow(color: glow, blurRadius: 20, offset: const Offset(0, 8))],
        gradient: isDark
            ? LinearGradient(colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF6D28D9) : const Color(0xFF504AF2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...steps.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontSize: 14)),
                    Expanded(child: Text(s, style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87))),
                  ],
                ),
              )),
          if (imageAsset != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                imageAsset!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) {
                  return Container(
                    height: 160,
                    color: Colors.grey[200],
                    alignment: Alignment.center,
                    child: Text('Missing: ${imageAsset!}', style: const TextStyle(fontSize: 12)),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreditsCard extends StatelessWidget {
  final Color cardBg;
  final Color borderColor;
  final Color glow;

  const _CreditsCard({required this.cardBg, required this.borderColor, required this.glow});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [BoxShadow(color: glow, blurRadius: 20, offset: const Offset(0, 8))],
        gradient: isDark
            ? LinearGradient(colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Text('Developed by', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        Text('• Mohammad Salman Hossain'),
        Text('• Syeed Mikdad Rahman'),
        Text('• Samira Hoq Lara'),
        Text('• Mosammat Shahana Islam'),
      ]),
    );
  }
}

class _HelpBox extends StatelessWidget {
  final Color cardBg;
  final Color borderColor;
  final Color glow;
  const _HelpBox({required this.cardBg, required this.borderColor, required this.glow});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [BoxShadow(color: glow, blurRadius: 20, offset: const Offset(0, 8))],
        gradient: isDark
            ? LinearGradient(colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Troubleshooting', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('- If permissions are denied, enable Storage/Photos in Settings.\n- On Android 13+, grant Photos and Videos permission.',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
      ]),
    );
  }
}



