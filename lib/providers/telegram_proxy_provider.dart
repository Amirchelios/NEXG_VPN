import 'package:flutter/foundation.dart';
import 'dart:io';
import '../models/telegram_proxy.dart';
import '../services/telegram_proxy_service.dart';

class TelegramProxyProvider extends ChangeNotifier {
  final TelegramProxyService _proxyService = TelegramProxyService();

  List<TelegramProxy> _proxies = [];
  bool _isLoading = false;
  String _errorMessage = '';

  List<TelegramProxy> get proxies => _proxies;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  Future<void> fetchProxies() async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final proxies = await _proxyService.fetchProxies();
      _proxies = await _filterReachableProxies(proxies, maxCount: 10);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<TelegramProxy>> _filterReachableProxies(
    List<TelegramProxy> proxies, {
    required int maxCount,
  }) async {
    const batchSize = 12;
    final reachable = <TelegramProxy>[];
    proxies.shuffle();

    for (var i = 0; i < proxies.length; i += batchSize) {
      if (reachable.length >= maxCount) {
        break;
      }
      final batch = proxies.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((proxy) => _isProxyReachable(proxy)),
      );
      for (var j = 0; j < batch.length; j++) {
        if (results[j]) {
          reachable.add(batch[j]);
          if (reachable.length >= maxCount) {
            break;
          }
        }
      }
    }

    return reachable;
  }

  Future<bool> _isProxyReachable(TelegramProxy proxy) async {
    try {
      final socket = await Socket.connect(
        proxy.host,
        proxy.port,
        timeout: const Duration(seconds: 4),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }
}
