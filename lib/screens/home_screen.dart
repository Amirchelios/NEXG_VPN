import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/v2ray_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_localizations.dart';
import '../widgets/connection_button.dart';
import '../widgets/server_selector.dart';
import '../widgets/background_gradient.dart';
import '../theme/app_theme.dart';
import '../services/v2ray_service.dart';
import '../services/wallpaper_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();

    // Listen for connection state changes
    final v2rayProvider = Provider.of<V2RayProvider>(context, listen: false);
    v2rayProvider.addListener(_onProviderChanged);
  }

  void _onProviderChanged() {
  }

  @override
  void dispose() {
    super.dispose();
  }


  // Share V2Ray link to clipboard
  void _shareV2RayLink(BuildContext context) async {
    try {
      final provider = Provider.of<V2RayProvider>(context, listen: false);
      final activeConfig = provider.activeConfig;

      if (activeConfig != null && activeConfig.fullConfig.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: activeConfig.fullConfig));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  color: AppTheme.connectedGreen,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('home.v2ray_link_copied'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.cardDark,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('home.no_v2ray_config'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${context.tr('home.error_copying')}: ${e.toString()}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, child) {
        return Directionality(
          textDirection: languageProvider.textDirection,
          child: BackgroundGradient(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: Text(context.tr(TranslationKeys.homeTitle)),
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: false,
                actions: [],
              ),
              body: Column(
                children: [
                  // Main content
                  Expanded(
                    child: Consumer<V2RayProvider>(
                      builder: (context, provider, _) {
                        // Show loading indicator while initializing
                        if (provider.isInitializing) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.primaryBlue,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  context.tr('common.loading'),
                                  style: const TextStyle(
                                    color: AppTheme.textGrey,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Server selector (now includes Proxy Mode Switch)
                                const ServerSelector(),

                                const SizedBox(height: 20),

                                // Connection button
                                const ConnectionButton(),

                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Consumer<V2RayProvider>(
                    builder: (context, provider, _) {
                      if (provider.activeConfig == null) {
                        return const SizedBox.shrink();
                      }

                      return _buildLocationBar(provider);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _countryCodeToFlag(String countryCode) {
    final code = countryCode.trim().toUpperCase();
    if (code.length != 2) {
      return '';
    }

    final first = code.codeUnitAt(0);
    final second = code.codeUnitAt(1);
    if (first < 65 || first > 90 || second < 65 || second > 90) {
      return '';
    }

    return String.fromCharCode(first + 127397) +
        String.fromCharCode(second + 127397);
  }

  Widget _buildLocationBar(V2RayProvider provider) {
    final v2rayService = provider.v2rayService;

    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data! % 5 == 0) {
          if (v2rayService.activeConfig != null) {
            v2rayService.fetchIpInfo().catchError((error) {
              debugPrint('Error refreshing IP info: $error');
            });
          }
        }

        final ipInfo = v2rayService.ipInfo;
        final locationText = ipInfo == null
            ? '...'
            : '${ipInfo.country} - ${ipInfo.city}'.trim();
        final flag = _countryCodeToFlag(ipInfo?.countryCode ?? '');

        return Consumer<WallpaperService>(
          builder: (context, wallpaperService, _) {
            final isGlassBackground = wallpaperService.isGlassBackgroundEnabled;

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              decoration: BoxDecoration(
                color: isGlassBackground
                    ? AppTheme.cardDark.withOpacity(0.7)
                    : AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (flag.isNotEmpty) ...[
                    Text(flag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                  ],
                  const Icon(
                    Icons.location_on,
                    size: 16,
                    color: AppTheme.textGrey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locationText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
