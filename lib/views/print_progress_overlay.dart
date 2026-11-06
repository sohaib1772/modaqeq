import 'package:flutter/material.dart';

class PrintProgressOverlay extends StatelessWidget {
  final String message;
  const PrintProgressOverlay({super.key, required this.message});
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: ModalBarrier(dismissible: false, color: Color(0x660b223a)),
      ),
      Center(
        child: SingleChildScrollView(
          child: Semantics(
            liveRegion: true,
            label: message,
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 22),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'يرجى الانتظار، لا حاجة للضغط مرة أخرى.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xff64758a)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
