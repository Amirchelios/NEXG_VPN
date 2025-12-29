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
import '../services/v2ray_service.dart';
import '../services/wallpaper_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _profileData;
  bool _isRefreshingProfile = false;

  @override
  void initState() {
    super.initState();

    // Listen for connection state changes
    final v2rayProvider = Provider.of<V2RayProvider>(context, listen: false);
    v2rayProvider.addListener(_onProviderChanged);
    _loadProfileData();
  }

  void _onProviderChanged() {}

  @override
  void dispose() {
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('در حال بروزرسانی پروفایل...'),
          backgroundColor: AppTheme.cardDark,
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
                      return IconButton(
                        icon: Icon(
                          enabled ? Icons.security : Icons.security_outlined,
                          color: enabled ? AppTheme.primaryGreen : Colors.white,
                        ),
                        onPressed: () async {
                          await provider.setAdBlockEnabled(!enabled);
                        },
                        tooltip: enabled ? 'AdBlock: On' : 'AdBlock: Off',
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

                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildUserProfileCard(),

                                const SizedBox(height: 16),

                                // Server selector (now includes Proxy Mode Switch)
                                const ServerSelector(),

                                const SizedBox(height: 20),

                                // Connection button
                                ConnectionButton(
                                  isEnabled: !_isAccessSuspended(),
                                ),

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
          child: Padding(
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
                          expiryDate,
                          style: const TextStyle(
                            color: AppTheme.textGrey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Column(
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
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _isRefreshingProfile
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
                      'زمان باقی مانده: $remainingDays روز',
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
                      Container(height: 8, color: AppTheme.surfaceContainer),
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
