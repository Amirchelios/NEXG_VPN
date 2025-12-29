import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/server_score_store.dart';

class SplitModeButton extends StatelessWidget {
  final ServerScoreMode mode;
  final bool scoredEnabled;
  final bool discoverEnabled;
  final ValueChanged<ServerScoreMode> onChanged;

  const SplitModeButton({
    super.key,
    required this.mode,
    required this.scoredEnabled,
    required this.discoverEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final leftActive = mode == ServerScoreMode.discover;
    final rightActive = mode == ServerScoreMode.scored;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _SplitSide(
            active: leftActive,
            label: 'New',
            icon: Icons.flash_on,
            locked: !discoverEnabled,
            onTap: discoverEnabled
                ? () => onChanged(ServerScoreMode.discover)
                : null,
            activeGradient: LinearGradient(
              colors: [
                AppTheme.primaryGreen,
                AppTheme.primaryGreen.withValues(alpha: 0.65),
              ],
            ),
            inactiveGlow: Colors.white.withValues(alpha: 0.08),
          ),
          _SplitDivider(),
          _SplitSide(
            active: rightActive,
            label: 'Scored',
            icon: Icons.verified,
            locked: !scoredEnabled,
            onTap: scoredEnabled
                ? () => onChanged(ServerScoreMode.scored)
                : null,
            activeGradient: LinearGradient(
              colors: [
                AppTheme.connectingBlue,
                AppTheme.connectingBlue.withValues(alpha: 0.65),
              ],
            ),
            inactiveGlow: Colors.white.withValues(alpha: 0.08),
          ),
        ],
      ),
    );
  }
}

class _SplitDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white.withOpacity(0.12),
    );
  }
}

class _SplitSide extends StatelessWidget {
  final bool active;
  final bool locked;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Gradient activeGradient;
  final Color inactiveGlow;

  const _SplitSide({
    required this.active,
    required this.label,
    required this.icon,
    required this.activeGradient,
    required this.inactiveGlow,
    this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = active ? activeGradient : null;
    final borderColor = active
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.06);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: inactiveGlow,
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                locked ? Icons.lock : icon,
                size: 18,
                color: active ? Colors.white : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.grey,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
