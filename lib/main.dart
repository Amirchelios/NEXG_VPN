import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/telegram_proxy_provider.dart';
import 'providers/v2ray_provider.dart';
import 'providers/language_provider.dart';
import 'services/wallpaper_service.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/privacy_welcome_screen.dart';
import 'screens/activation_screen.dart';
import 'screens/loading_screen.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'dart:async';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppBootstrapper());
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  LanguageProvider? _languageProvider;
  bool _privacyAccepted = false;
  bool _isActivated = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    final languageProvider = LanguageProvider();
    await languageProvider.initialize();

    final prefs = await SharedPreferences.getInstance();
    final privacyAccepted = prefs.getBool('privacy_accepted') ?? false;
    final isActivated =
        (prefs.getString('activation_code') ?? '').trim().isNotEmpty;

    if (!mounted) return;
    setState(() {
      _languageProvider = languageProvider;
      _privacyAccepted = privacyAccepted;
      _isActivated = isActivated;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _languageProvider == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: LoadingScreen(),
      );
    }

    return MyApp(
      privacyAccepted: _privacyAccepted,
      isActivated: _isActivated,
      languageProvider: _languageProvider!,
    );
  }
}

class MyApp extends StatefulWidget {
  final bool privacyAccepted;
  final bool isActivated;
  final LanguageProvider languageProvider;

  const MyApp({
    super.key,
    required this.privacyAccepted,
    required this.isActivated,
    required this.languageProvider,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final UpdateService _updateService = UpdateService();
  Timer? _cleanupTimer;
  WallpaperService? _wallpaperService;

  @override
  void initState() {
    super.initState();
    // Check for updates after the app is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      _startPeriodicCleanup();
    });
  }

  /// Start a periodic cleanup task to prevent app size bloat
  void _startPeriodicCleanup() {
    // Run cleanup every 6 hours
    _cleanupTimer = Timer.periodic(const Duration(hours: 6), (timer) async {
      try {
        // Perform cleanup using the service instance
        if (_wallpaperService != null) {
          await _wallpaperService!.cleanupAllOldWallpapers();
        }
      } catch (e) {
        // Silently ignore cleanup errors to avoid disturbing the user
      }
    });
  }

  Future<void> _checkForUpdates() async {
    final update = await _updateService.checkForUpdates();
    if (update != null && mounted) {
      _updateService.showUpdateDialog(context, update);
    }
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.languageProvider),
        ChangeNotifierProvider(create: (context) => V2RayProvider()),
        ChangeNotifierProvider(create: (context) => TelegramProxyProvider()),
        ChangeNotifierProvider(
          create: (context) {
            _wallpaperService = WallpaperService()..initialize();
            return _wallpaperService!;
          },
        ),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, child) {
          return MaterialApp(
            title: 'NG VPN',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme(languageProvider.currentLanguage.code),
            locale: languageProvider.locale,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en'), // English
              Locale('tr'), // Turkish
              Locale('es'), // Spanish
              Locale('fr'), // French
              Locale('ar'), // Arabic
              Locale('zh'), // Chinese
              Locale('ru'), // Russian
              Locale('fa'), // Persian
            ],
            home: Consumer<V2RayProvider>(
              builder: (context, v2rayProvider, _) {
                return AppLoadingGate(
                  isReady: !v2rayProvider.isInitializing,
                  child: widget.privacyAccepted
                      ? (widget.isActivated
                          ? const MainNavigationScreen()
                          : const ActivationScreen())
                      : const PrivacyWelcomeScreen(),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
