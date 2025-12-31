import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/v2ray_config.dart';
import '../providers/v2ray_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/wallpaper_service.dart';
import '../utils/server_score_store.dart';
import 'split_mode_button.dart';

class ServerSelector extends StatefulWidget {
  const ServerSelector({super.key});

  @override
  State<ServerSelector> createState() => _ServerSelectorState();
}

class _ServerSelectorState extends State<ServerSelector> {
  ServerScoreMode _scoreMode = ServerScoreMode.discover;
  bool _hasScores = false;
  bool _isRefreshing = false;
  bool _newLocked = false;
  Map<String, ServerScore> _serverScores = {};

  @override
  void initState() {
    super.initState();
    _refreshScoreState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _refreshScoreState({List<V2RayConfig>? configs}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    final scores = await ServerScoreStore.loadScores();
    final mode = await ServerScoreStore.loadMode();
    if (!mounted) return;
    final hasScores = scores.isNotEmpty;
    final bool noConfigs = configs != null && configs.isEmpty;
    final hasNew = configs != null
        ? configs.any((c) => !scores.containsKey(c.id))
        : true;
    final shouldLockNew = noConfigs || (hasScores && !hasNew);
    final nextMode = shouldLockNew ? ServerScoreMode.scored : mode;
    setState(() {
      _serverScores = scores;
      _hasScores = hasScores;
      _scoreMode = nextMode;
      _newLocked = shouldLockNew;
    });
    if (!hasScores && !shouldLockNew && mode == ServerScoreMode.scored) {
      await ServerScoreStore.saveMode(ServerScoreMode.discover);
    } else if (shouldLockNew && mode != ServerScoreMode.scored) {
      await ServerScoreStore.saveMode(ServerScoreMode.scored);
    }
    _isRefreshing = false;
  }

  Future<void> _setScoreMode(ServerScoreMode mode) async {
    if (_newLocked && mode == ServerScoreMode.discover) {
      return;
    }
    if (!_hasScores && mode == ServerScoreMode.scored) {
      return;
    }
    setState(() {
      _scoreMode = mode;
    });
    await ServerScoreStore.saveMode(mode);
  }

  Future<void> _refreshServers(V2RayProvider provider) async {
    if (provider.isUpdatingSubscriptions) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('home.updating_subscriptions')),
      ),
    );

    await ServerScoreStore.clearScores();
    await ServerScoreStore.clearBadServers();
    await ServerScoreStore.saveMode(ServerScoreMode.discover);

    await provider.updateAllSubscriptions();
    provider.fetchNotificationStatus();
    await _refreshScoreState();

    if (!mounted) return;
    if (provider.errorMessage.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('home.subscriptions_updated')),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage),
        ),
      );
      provider.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<V2RayProvider, LanguageProvider, WallpaperService>(
      builder: (context, provider, languageProvider, wallpaperService, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _refreshScoreState(configs: provider.configs);
        });
        return Directionality(
          textDirection: languageProvider.textDirection,
          child: _buildServerSelector(context, provider, wallpaperService),
        );
      },
    );
  }

  Widget _buildServerSelector(
    BuildContext context,
    V2RayProvider provider,
    WallpaperService wallpaperService,
  ) {
    final isLoadingServers = provider.isLoadingServers;
    final isGlassBackground = wallpaperService.isGlassBackgroundEnabled;
    final configs = provider.configs;

    if (configs.isEmpty) {
      return _EmptyServerCard(isGlassBackground: isGlassBackground);
    }

    final isUpdating = provider.isUpdatingSubscriptions || isLoadingServers;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isGlassBackground
          ? AppTheme.surfaceCard.withOpacity(0.7)
          : AppTheme.cardDark,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 32,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      context.tr(TranslationKeys.homeSelectServer),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip:
                          context.tr(TranslationKeys.serverSelectionUpdateServers),
                      onPressed: provider.isUpdatingSubscriptions
                          ? null
                          : () => _refreshServers(provider),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: isUpdating
                    ? const _UpdatingMarquee(
                        key: ValueKey('updating_marquee'),
                      )
                    : SplitModeButton(
                        key: const ValueKey('split_mode'),
                        mode: _scoreMode,
                        scoredEnabled: _hasScores &&
                            provider.connectMode == ConnectMode.normal,
                        discoverEnabled: !_newLocked &&
                            provider.connectMode == ConnectMode.normal,
                        onChanged: _setScoreMode,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdatingMarquee extends StatefulWidget {
  const _UpdatingMarquee({super.key});

  @override
  State<_UpdatingMarquee> createState() => _UpdatingMarqueeState();
}

class _UpdatingMarqueeState extends State<_UpdatingMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const text = 'در حال بروز رسانی سرور لطفا منتظر بمانید!';
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.85),
      fontWeight: FontWeight.w600,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceCard),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: textStyle),
              textDirection: TextDirection.rtl,
            )..layout();
            final textWidth = painter.width;
            final minX = -textWidth;
            final maxX = constraints.maxWidth;

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final dx = minX + (maxX - minX) * t;
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(text, style: textStyle),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LoadingServerCard extends StatelessWidget {
  final bool isGlassBackground;

  const _LoadingServerCard({required this.isGlassBackground});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isGlassBackground
          ? AppTheme.surfaceCard.withOpacity(0.7)
          : AppTheme.cardDark,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.connectedGreen),
              const SizedBox(height: 16),
              Text(context.tr(TranslationKeys.serverSelectorLoadingServers)),
              const SizedBox(height: 16),
              Consumer<V2RayProvider>(
                builder: (context, provider, _) {
                  return TextButton(
                    onPressed: provider.isUpdatingSubscriptions
                        ? null
                        : () async {
                            final v2rayProvider = Provider.of<V2RayProvider>(
                              context,
                              listen: false,
                            );
                            try {
                              // Show loading indicator
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    context.tr('home.updating_subscriptions'),
                                  ),
                                ),
                              );

                              // Update all subscriptions instead of just fetching servers
                              await v2rayProvider.updateAllSubscriptions();
                              v2rayProvider.fetchNotificationStatus();

                              // Show success message
                              if (v2rayProvider.errorMessage.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      context.tr('home.subscriptions_updated'),
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(v2rayProvider.errorMessage),
                                  ),
                                );
                                v2rayProvider.clearError();
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${context.tr(TranslationKeys.serverSelectorErrorRefreshing)}: ${e.toString()}',
                                  ),
                                ),
                              );
                            }
                          },
                    child: Text(context.tr(TranslationKeys.commonRefresh)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyServerCard extends StatelessWidget {
  final bool isGlassBackground;

  const _EmptyServerCard({required this.isGlassBackground});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isGlassBackground
          ? AppTheme.surfaceCard.withOpacity(0.7)
          : AppTheme.cardDark,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppTheme.textGrey),
              const SizedBox(height: 16),
              Text(context.tr(TranslationKeys.serverSelectorNoServers)),
              const SizedBox(height: 16),
              Consumer<V2RayProvider>(
                builder: (context, provider, _) {
                  return ElevatedButton(
                    onPressed: provider.isUpdatingSubscriptions
                        ? null
                        : () async {
                            final v2rayProvider = Provider.of<V2RayProvider>(
                              context,
                              listen: false,
                            );
                            try {
                              // Show loading indicator
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    context.tr('home.updating_subscriptions'),
                                  ),
                                ),
                              );

                              // Update all subscriptions instead of just fetching servers
                              await v2rayProvider.updateAllSubscriptions();
                              v2rayProvider.fetchNotificationStatus();

                              // Show success message
                              if (v2rayProvider.errorMessage.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      context.tr('home.subscriptions_updated'),
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(v2rayProvider.errorMessage),
                                  ),
                                );
                                v2rayProvider.clearError();
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${context.tr(TranslationKeys.serverSelectorErrorRefreshing)}: ${e.toString()}',
                                  ),
                                ),
                              );
                            }
                          },
                    child: Text(context.tr(TranslationKeys.commonRefresh)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
