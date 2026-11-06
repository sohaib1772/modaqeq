import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/portal_controller.dart';
import 'portal_view.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});
  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1850),
  );
  bool finished = false;
  @override
  void initState() {
    super.initState();
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => finished = true);
        final portal = Get.find<PortalController>();
        if (portal.serverLocked.value) portal.connect();
      }
    });
    animation.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.duration = const Duration(milliseconds: 200);
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (finished) return const PortalView();
    return Scaffold(
      backgroundColor: const Color(0xfff6faff),
      body: Center(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final reveal = Curves.easeOutCubic.transform(
              (animation.value / .7).clamp(0.0, 1.0),
            );
            final caption = ((animation.value - .28) / .45).clamp(0.0, 1.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: animation.value * math.pi * .22,
                        child: Transform.scale(
                          scale: .72 + .28 * reveal,
                          child: Opacity(
                            opacity: .55 * reveal,
                            child: Container(
                              width: 235,
                              height: 235,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xffd4eaff),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 205,
                        height: 205,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xff008fea,
                              ).withValues(alpha: .09 * reveal),
                              blurRadius: 55,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                      ),
                      Opacity(
                        opacity: reveal,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - reveal)),
                          child: Transform.scale(
                            scale: .82 + .18 * reveal,
                            child: Image.asset(
                              'assets/logo.png',
                              width: 180,
                              height: 180,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Opacity(
                  opacity: caption,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - caption)),
                    child: const Text(
                      'المدقق المحاسبي',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff07325c),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: caption,
                  child: const Text(
                    'وضوح في أرقامك، ثقة في أعمالك',
                    style: TextStyle(fontSize: 13, color: Color(0xff71849b)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
