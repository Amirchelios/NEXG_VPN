import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/background_gradient.dart';
import 'main_navigation_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    _controller.text = text.trim();
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }


  Future<void> _scanQrCode() async {
    bool handled = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    if (handled) return;
                    final barcode = capture.barcodes.isNotEmpty
                        ? capture.barcodes.first
                        : null;
                    final value = barcode?.rawValue?.trim();
                    if (value == null || value.isEmpty) return;
                    handled = true;
                    _controller.text = value;
                    _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: _controller.text.length),
                    );
                    Navigator.of(dialogContext).pop();
                  },
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitCode() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorText = 'کد فعال سازی را وارد کنید';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      final url = Uri.parse(
        'https://raw.githubusercontent.com/Amirchelios/NG_manager/refs/heads/main/control_user/$code',
      );
      final response = await http.get(url);

      if (response.statusCode != 200) {
        setState(() {
          _errorText = 'کد نا معتبر است';
        });
        return;
      }

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] == true;
      final redeemStatus = data['redeem_status'] == true;
      if (!status) {
        setState(() {
          _errorText = 'کد نا معتبر است';
        });
        return;
      }
      if (!redeemStatus) {
        setState(() {
          _errorText = 'این کد قبلا استفاده شده است';
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('activation_code', code);
      await prefs.setString('profile_data', jsonEncode(data));

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'خطا در بررسی کد';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundGradient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: Card(
              color: AppTheme.cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'فعال سازی حساب',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'کد فعال سازی',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _pasteFromClipboard,
                              icon: const Icon(Icons.content_paste),
                              color: Colors.white70,
                              tooltip: 'Paste',
                            ),
                            IconButton(
                              onPressed: _scanQrCode,
                              icon: const Icon(Icons.qr_code_scanner),
                              color: Colors.white70,
                              tooltip: 'Scan',
                            ),
                          ],
                        ),
                        filled: true,
                        fillColor: AppTheme.surfaceContainer,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorText!,
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'تایید',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
