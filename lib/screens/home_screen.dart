import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../providers/v2ray_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_localizations.dart';
import '../widgets/connection_button.dart';
import '../widgets/server_selector.dart';
import '../widgets/background_gradient.dart';
import '../theme/app_theme.dart';
import '../services/wallpaper_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? _profileData;
  bool _isRefreshingProfile = false;
  Timer? _profileRefreshTimer;
  DateTime? _nextProfileRefreshAllowedAt;
  late final AnimationController _adBlockPulseController;
  late final Animation<double> _adBlockScale;
  late final AnimationController _expiryPulseController;
  late final Animation<double> _expiryPulse;
  late final AnimationController _expiryMarqueeController;

  @override
  void initState() {
    super.initState();

    // Listen for connection state changes
    final v2rayProvider = Provider.of<V2RayProvider>(context, listen: false);
    v2rayProvider.addListener(_onProviderChanged);
    _loadProfileData();
    _profileRefreshTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _refreshProfileData(),
    );
    _adBlockPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _adBlockScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _adBlockPulseController, curve: Curves.easeInOut),
    );
    _expiryPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _expiryPulse = Tween<double>(begin: 1.0, end: 0.2).animate(
      CurvedAnimation(parent: _expiryPulseController, curve: Curves.easeInOut),
    );
    _expiryMarqueeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    );
  }

  void _onProviderChanged() {}

  @override
  void dispose() {
    _profileRefreshTimer?.cancel();
    _adBlockPulseController.dispose();
    _expiryPulseController.dispose();
    _expiryMarqueeController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('profile_data');
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _profileData = data;
      });
    } catch (_) {}
  }

  Future<void> _refreshProfileData() async {
    if (_isRefreshingProfile) return;
    final now = DateTime.now();
    if (_nextProfileRefreshAllowedAt != null &&
        now.isBefore(_nextProfileRefreshAllowedAt!)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final code = (prefs.getString('activation_code') ?? '').trim();
    if (code.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('کد فعال سازی یافت نشد'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }
    setState(() {
      _isRefreshingProfile = true;
    });
    try {
      _nextProfileRefreshAllowedAt = DateTime.now().add(
        const Duration(minutes: 4),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('در حال بروزرسانی پروفایل...'),
          backgroundColor: AppTheme.primaryBlue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      final url = Uri.parse(
        'https://raw.githubusercontent.com/Amirchelios/NG_manager/refs/heads/main/control_user/$code',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await prefs.setString('profile_data', jsonEncode(data));
        if (!mounted) return;
        setState(() {
          _profileData = data;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('اطلاعات پروفایل بروزرسانی شد'),
            backgroundColor: AppTheme.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('بروزرسانی پروفایل ناموفق بود'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (_) {
      // Ignore refresh errors for now.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('خطا در بروزرسانی پروفایل'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingProfile = false;
        });
      }
    }
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

  void _updateAdBlockPulse(bool enabled) {
    if (enabled) {
      if (!_adBlockPulseController.isAnimating) {
        _adBlockPulseController.repeat(reverse: true);
      }
      return;
    }

    if (_adBlockPulseController.isAnimating ||
        _adBlockPulseController.value != 0) {
      _adBlockPulseController.stop();
      _adBlockPulseController.value = 0;
    }
  }

  void _updateExpiryAnimations({
    required bool pulse,
    required bool marquee,
  }) {
    if (pulse) {
      if (!_expiryPulseController.isAnimating) {
        _expiryPulseController.repeat(reverse: true);
      }
    } else if (_expiryPulseController.isAnimating ||
        _expiryPulseController.value != 0) {
      _expiryPulseController.stop();
      _expiryPulseController.value = 0;
    }

    if (marquee) {
      if (!_expiryMarqueeController.isAnimating) {
        _expiryMarqueeController.repeat();
      }
    } else if (_expiryMarqueeController.isAnimating ||
        _expiryMarqueeController.value != 0) {
      _expiryMarqueeController.stop();
      _expiryMarqueeController.value = 0;
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
                leading: null,
                actions: [
                  Consumer<V2RayProvider>(
                    builder: (context, provider, _) {
                      final enabled = provider.adBlockEnabled;
                      _updateAdBlockPulse(enabled);
                      return Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            await provider.setAdBlockEnabled(!enabled);
                          },
                          child: ScaleTransition(
                            scale: _adBlockScale,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: enabled
                                    ? AppTheme.primaryGreen.withOpacity(0.15)
                                    : Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: enabled
                                      ? AppTheme.primaryGreen
                                      : Colors.white24,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    enabled
                                        ? Icons.security
                                        : Icons.security_outlined,
                                    color: enabled
                                        ? AppTheme.primaryGreen
                                        : Colors.white,
                                    size: 26,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'ضد تبلیغات',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
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

                        return RefreshIndicator(
                          onRefresh: _refreshProfileData,
                          color: AppTheme.primaryGreen,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildUserProfileCard(),

                                  const SizedBox(height: 16),

                                  // Server selector (now includes Proxy Mode Switch)
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 550),
                                    switchInCurve: Curves.easeOutQuart,
                                    switchOutCurve: Curves.easeInQuart,
                                    transitionBuilder: (child, animation) {
                                      final slide = Tween<Offset>(
                                        begin: const Offset(0, 0.06),
                                        end: Offset.zero,
                                      ).animate(animation);
                                      return FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: slide,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: provider.connectMode ==
                                            ConnectMode.normal
                                        ? const Padding(
                                            key: ValueKey('server_selector'),
                                            padding: EdgeInsets.only(bottom: 20),
                                            child: ServerSelector(),
                                          )
                                        : const SizedBox(
                                            key: ValueKey('no_server_selector'),
                                            height: 20,
                                          ),
                                  ),

                                  // Connection button
                                  AnimatedSlide(
                                    duration: const Duration(milliseconds: 550),
                                    curve: Curves.easeOutQuart,
                                    offset: provider.connectMode ==
                                            ConnectMode.smart
                                        ? const Offset(0, -0.03)
                                        : Offset.zero,
                                    child: AnimatedOpacity(
                                      duration: const Duration(milliseconds: 550),
                                      curve: Curves.easeOutQuart,
                                      opacity: 1,
                                      child: ConnectionButton(
                                        isEnabled: !_isAccessSuspended() &&
                                            !_isProfileExpired(),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 40),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Consumer<V2RayProvider>(
                    builder: (context, provider, _) {
                      if (_isAccessSuspended()) {
                        return _buildSuspendedBanner();
                      }

                      if (provider.activeConfig == null ||
                          provider.connectMode == ConnectMode.smart) {
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

  Widget _buildUserProfileCard() {
    final userName = (_profileData?['name'] ?? '-') as String;
    final phoneNumber = (_profileData?['phone'] ?? '-') as String;
    final activationDate = (_profileData?['start_jalali'] ?? '-') as String;
    final expiryDate = (_profileData?['expiry_jalali'] ?? '-') as String;
    final totalDays = _dateDiffInDays(activationDate, expiryDate);
    final remainingDays = _dateDiffFromNow(expiryDate);
    final isExpired = remainingDays < 0;
    final isExpiring = remainingDays <= 5 && remainingDays >= 0;
    _updateExpiryAnimations(
      pulse: isExpiring,
      marquee: isExpiring || isExpired,
    );
    final normalizedRemaining = remainingDays < 0
        ? 0
        : (remainingDays > totalDays ? totalDays : remainingDays);
    final remainingRatio = totalDays <= 0
        ? 0.0
        : normalizedRemaining / totalDays;

    return Consumer<WallpaperService>(
      builder: (context, wallpaperService, _) {
        final isGlassBackground = wallpaperService.isGlassBackgroundEnabled;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: isGlassBackground
              ? AppTheme.cardDark.withOpacity(0.75)
              : AppTheme.cardDark,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                if (isExpiring || isExpired)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            (isExpired
                                ? Colors.redAccent
                                : Colors.amber).withValues(alpha: 0.25),
                            (isExpired
                                ? Colors.red
                                : Colors.redAccent).withValues(alpha: 0.22),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'پروفایل شما',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _todayLabel(),
                                style: const TextStyle(
                                  color: AppTheme.textGrey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              AnimatedBuilder(
                                animation: _expiryPulse,
                                builder: (context, child) {
                                  return Opacity(
                                    opacity: isExpiring
                                        ? _expiryPulse.value
                                        : 1.0,
                                    child: child,
                                  );
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      userName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'شماره: $phoneNumber',
                                      style: const TextStyle(
                                        color: AppTheme.textGrey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: _isRefreshingProfile ||
                                        (_nextProfileRefreshAllowedAt != null &&
                                            DateTime.now().isBefore(
                                              _nextProfileRefreshAllowedAt!,
                                            ))
                                    ? null
                                    : _refreshProfileData,
                                child: AnimatedRotation(
                                  turns: _isRefreshingProfile ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 700),
                                  curve: Curves.easeInOut,
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTheme.surfaceContainer,
                                    ),
                                    child: const Icon(
                                      Icons.refresh,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (isExpiring || isExpired) ...[
                        const SizedBox(height: 12),
                        _ExpiringMarquee(
                          controller: _expiryMarqueeController,
                          onTap: _openAdminChat,
                          text: isExpired
                              ? 'اشتراک شما منقضی شده جهت تمدید اشتراک اینجا کلیک کنید تا به ادمین متصل شوید'
                              : 'مدت زمان اشتراک شما در حال به پایان رسیدن میباشد جهت تمدید اشتراک اینجا کلیک کنید',
                          gradientColors: isExpired
                              ? [Colors.redAccent, Colors.red]
                              : [Colors.redAccent, Colors.amber],
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'انقضا: $expiryDate',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'تاریخ ساخت: $activationDate',
                            style: const TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'از $totalDays روز',
                            style: const TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            _remainingLabel(remainingDays, expiryDate),
                            style: TextStyle(
                              color: remainingDays <= 3
                                  ? Colors.redAccent
                                  : (remainingDays <= 10
                                        ? Colors.amber
                                        : AppTheme.primaryGreen),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Container(
                              height: 8,
                              color: AppTheme.surfaceContainer,
                            ),
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FractionallySizedBox(
                                  widthFactor: remainingRatio.clamp(0.0, 1.0),
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerRight,
                                        end: Alignment.centerLeft,
                                        colors: [
                                          AppTheme.primaryBlue,
                                          AppTheme.primaryGreen,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        );
      },
    );
  }

  Widget _buildSuspendedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: _openAdminChat,
        child: Row(
          children: const [
            Icon(Icons.info_outline, color: Colors.redAccent, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'پیام دسترسی شما توسط ادمین در حالت تعلیق در آمده است',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'برای ارتباط با ادمین کلیک کنید',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isAccessSuspended() {
    if (_profileData == null) return false;
    return _profileData?['status'] == false;
  }

  bool _isProfileExpired() {
    if (_profileData == null) return false;
    final expiryDate = (_profileData?['expiry_jalali'] ?? '-') as String;
    if (expiryDate == '-') return false;
    return _dateDiffFromNow(expiryDate) < 0;
  }

  Future<void> _openAdminChat() async {
    try {
      final url = Uri.parse(
        'https://raw.githubusercontent.com/Amirchelios/NG_manager/refs/heads/main/admin.txt',
      );
      final response = await http.get(url);
      if (response.statusCode != 200) return;
      final adminId = response.body.trim();
      if (adminId.isEmpty) return;
      final tgUrl = Uri.parse('https://t.me/$adminId');
      await launchUrl(tgUrl, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  int _dateDiffInDays(String start, String end) {
    final startDate = _parseDate(start);
    final endDate = _parseDate(end);
    if (startDate == null || endDate == null) {
      return 0;
    }
    return endDate.difference(startDate).inDays.abs();
  }

  int _dateDiffFromNow(String end) {
    final endDate = _parseDate(end);
    if (endDate == null) {
      return 0;
    }
    return endDate.difference(DateTime.now()).inDays;
  }

  String _remainingLabel(int remainingDays, String expiryDate) {
    if (remainingDays < 0) {
      return 'زمان باقی مانده: منقضی شده';
    }
    if (remainingDays > 1) {
      return 'زمان باقی مانده: $remainingDays روز';
    }
    final endDate = _parseDate(expiryDate);
    if (endDate == null) {
      return remainingDays == 1
          ? 'زمان باقی مانده: 1 روز'
          : 'زمان باقی مانده: 0 روز';
    }
    final endOfDay = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
    );
    var diff = endOfDay.difference(DateTime.now());
    if (diff.isNegative) {
      diff = Duration.zero;
    }
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    return 'مدت باقی مانده: $hours ساعت و $minutes دقیقه';
  }

  String _todayLabel() {
    final now = DateTime.now();
    return _gregorianToJalaliString(now.year, now.month, now.day);
  }

  String _gregorianToJalaliString(int gy, int gm, int gd) {
    final j = _gregorianToJalali(gy, gm, gd);
    final year = j[0].toString().padLeft(4, '0');
    final month = j[1].toString().padLeft(2, '0');
    final day = j[2].toString().padLeft(2, '0');
    return '$year/$month/$day';
  }

  List<int> _gregorianToJalali(int gy, int gm, int gd) {
    final gDays = <int>[
      0,
      31,
      59,
      90,
      120,
      151,
      181,
      212,
      243,
      273,
      304,
      334,
    ];

    int gy2 = (gm > 2) ? gy + 1 : gy;
    int days =
        355666 + (365 * gy) + ((gy2 + 3) ~/ 4) - ((gy2 + 99) ~/ 100) +
            ((gy2 + 399) ~/ 400) + gd + gDays[gm - 1];
    int jy = -1595 + 33 * (days ~/ 12053);
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    int jm = (days < 186) ? 1 + (days ~/ 31) : 7 + ((days - 186) ~/ 30);
    int jd = 1 + ((days < 186) ? (days % 31) : ((days - 186) % 30));
    return [jy, jm, jd];
  }

  DateTime? _parseDate(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return _jalaliToGregorian(year, month, day);
  }

  DateTime _jalaliToGregorian(int jy, int jm, int jd) {
    var jyAdj = jy - 979;
    var jmAdj = jm - 1;
    var jdAdj = jd - 1;

    var jDayNo = 365 * jyAdj + (jyAdj ~/ 33) * 8 + ((jyAdj % 33) + 3) ~/ 4;
    for (var i = 0; i < jmAdj; ++i) {
      jDayNo += i < 6 ? 31 : 30;
    }
    jDayNo += jdAdj;

    var gDayNo = jDayNo + 79;

    var gy = 1600 + 400 * (gDayNo ~/ 146097);
    gDayNo %= 146097;

    var leap = true;
    if (gDayNo >= 36525) {
      gDayNo--;
      gy += 100 * (gDayNo ~/ 36524);
      gDayNo %= 36524;

      if (gDayNo >= 365) {
        gDayNo++;
      } else {
        leap = false;
      }
    }

    gy += 4 * (gDayNo ~/ 1461);
    gDayNo %= 1461;

    if (gDayNo >= 366) {
      leap = false;
      gDayNo--;
      gy += gDayNo ~/ 365;
      gDayNo %= 365;
    }

    final gMonthDays = <int>[
      31,
      leap ? 29 : 28,
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31,
    ];

    var gm = 0;
    while (gm < 12 && gDayNo >= gMonthDays[gm]) {
      gDayNo -= gMonthDays[gm];
      gm++;
    }
    final gd = gDayNo + 1;
    return DateTime(gy, gm + 1, gd);
  }
}

class _ExpiringMarquee extends StatelessWidget {
  final Animation<double> controller;
  final VoidCallback onTap;
  final String text;
  final List<Color> gradientColors;

  const _ExpiringMarquee({
    required this.controller,
    required this.onTap,
    required this.text,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.95),
      fontWeight: FontWeight.w600,
      fontSize: 12,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              gradientColors.first.withValues(alpha: 0.8),
              gradientColors.last.withValues(alpha: 0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: TextSpan(text: text, style: textStyle),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout();
              final textWidth = painter.width;
              final minX = -textWidth;
              final maxX = constraints.maxWidth;

              return AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final t = controller.value;
                  final dx = minX + (maxX - minX) * t;
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        text,
                        style: textStyle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
