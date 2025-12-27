import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/server_score_store.dart';

class SplitModeButton extends StatelessWidget {
  final ServerScoreMode mode;
  final bool scoredEnabled;
  final ValueChanged<ServerScoreMode> onChanged;

  const SplitModeButton({
    super.key,
    required this.mode,
    required this.scoredEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final leftActive = mode == ServerScoreMode.discover;
    final rightActive = mode == ServerScoreMode.scored;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
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
            onTap: () => onChanged(ServerScoreMode.discover),
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

  const _SplitSide({
    required this.active,
    required this.label,
    required this.icon,
    this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = active
        ? LinearGradient(
            colors: [
              AppTheme.primaryGreen,
              AppTheme.primaryGreen.withValues(alpha: 0.6),
            ],
          )
        : null;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(12),
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
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
