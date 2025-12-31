import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppLoadingGate extends StatefulWidget {
  final Widget child;
  final Duration minDuration;
  final bool isReady;

  const AppLoadingGate({
    super.key,
    required this.child,
    required this.isReady,
    this.minDuration = const Duration(milliseconds: 1400),
  });

  @override
  State<AppLoadingGate> createState() => _AppLoadingGateState();
}

class _AppLoadingGateState extends State<AppLoadingGate> {
  bool _minElapsed = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.minDuration, () {
      if (!mounted) return;
      setState(() => _minElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showLoading = !_minElapsed || !widget.isReady;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: showLoading ? const LoadingScreen() : widget.child,
    );
  }
}

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _orbitController;
  late final AnimationController _pulseController;
  late final Animation<Color?> _taglineColor;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _taglineColor = ColorTween(
      begin: AppTheme.connectedGreen.withValues(alpha: 0.75),
      end: AppTheme.primaryBlue.withValues(alpha: 0.95),
    ).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _LoadingBackground(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _OrbitalLoader(
                  orbitAnimation: _orbitController,
                  pulseAnimation: _pulseController,
                ),
                const SizedBox(height: 26),
                Text(
                  'NG VPN',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 6),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    final scale = 0.96 + (0.08 * _pulseController.value);
                    return Transform.scale(
                      scale: scale,
                      child: Text(
                        'سریع • هوشمند • امن',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              color: _taglineColor.value,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _LoadingDots(animation: _pulseController),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBackground extends StatelessWidget {
  const _LoadingBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0A0F1E),
                Color(0xFF0E1A2D),
                Color(0xFF12253A),
              ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -60,
          child: _BlurBlob(
            size: 220,
            color: AppTheme.primaryBlue.withValues(alpha: 0.45),
          ),
        ),
        Positioned(
          bottom: -140,
          right: -40,
          child: _BlurBlob(
            size: 260,
            color: AppTheme.connectedGreen.withValues(alpha: 0.35),
          ),
        ),
        Positioned(
          top: 120,
          right: -80,
          child: _BlurBlob(
            size: 180,
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

class _BlurBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _BlurBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _OrbitalLoader extends StatelessWidget {
  final Animation<double> orbitAnimation;
  final Animation<double> pulseAnimation;

  const _OrbitalLoader({
    required this.orbitAnimation,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.05).animate(
              CurvedAnimation(parent: pulseAnimation, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryBlue.withValues(alpha: 0.95),
                    AppTheme.primaryBlueDark.withValues(alpha: 0.8),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.45),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          RotationTransition(
            turns: orbitAnimation,
            child: CustomPaint(
              size: const Size(190, 190),
              painter: _OrbitPainter(),
            ),
          ),
          RotationTransition(
            turns: Tween<double>(begin: 0, end: -1).animate(orbitAnimation),
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final arcs = [
      _ArcStyle(0.1, 1.1, AppTheme.primaryBlue),
      _ArcStyle(1.6, 2.4, AppTheme.connectedGreen),
      _ArcStyle(3.4, 4.0, Colors.white.withValues(alpha: 0.7)),
    ];

    for (final arc in arcs) {
      arcPaint.color = arc.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        arc.startAngle,
        arc.sweepAngle,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ArcStyle {
  final double startAngle;
  final double sweepAngle;
  final Color color;

  _ArcStyle(double start, double end, this.color)
      : startAngle = start * pi,
        sweepAngle = (end - start) * pi;
}

class _LoadingDots extends StatelessWidget {
  final Animation<double> animation;

  const _LoadingDots({required this.animation});

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: 0.75);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (t + index * 0.18) % 1.0;
            final scale = 0.7 + 0.45 * sin(phase * pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _AppIconHalo extends StatelessWidget {
  final Animation<double> pulseAnimation;

  const _AppIconHalo({required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1.04).animate(
        CurvedAnimation(parent: pulseAnimation, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.2),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: Transform.translate(
            offset: const Offset(0, 14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Image.asset(
                'assets/images/app_icon.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
