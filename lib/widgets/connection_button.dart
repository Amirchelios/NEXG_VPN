import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import '../providers/v2ray_provider.dart';
import '../models/v2ray_config.dart';
import '../theme/app_theme.dart';
import '../utils/auto_select_util.dart';
import '../utils/app_localizations.dart';
import '../utils/server_score_store.dart';

class ConnectionButton extends StatefulWidget {
  final bool isEnabled;

  const ConnectionButton({super.key, this.isEnabled = true});

  @override
  State<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends State<ConnectionButton> {
  // Cancellation token for auto-select operation
  AutoSelectCancellationToken? _autoSelectCancellationToken;

  // Stream controller for status updates
  late final StreamController<String> _autoSelectStatusStream =
      StreamController<String>.broadcast();
  late final PageController _pageController;
  int _pageIndex = 0;
  bool _pageInitialized = false;

  @override
  void dispose() {
    _pageController.dispose();
    _autoSelectStatusStream.close();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pageInitialized) {
      return;
    }
    final provider = Provider.of<V2RayProvider>(context, listen: false);
    _pageIndex = provider.connectMode == ConnectMode.smart ? 1 : 0;
    _pageController = PageController(initialPage: _pageIndex);
    _pageInitialized = true;
  }

  String _countryCodeToFlag(String countryCode) {
    if (countryCode.length != 2) {
      return countryCode.toUpperCase();
    }
    final base = countryCode.toUpperCase().codeUnits;
    return String.fromCharCodes(base.map((codeUnit) => 127397 + codeUnit));
  }

  String _formatServerLocation(ServerScore? score, V2RayConfig config) {
    if (score == null) {
      return config.remark;
    }
    final parts = <String>[];
    if (score.city.isNotEmpty) {
      parts.add(score.city);
    }
    if (score.country.isNotEmpty) {
      parts.add(score.country);
    }
    if (parts.isEmpty) {
      return config.remark;
    }
    return parts.join(' • ');
  }

  Future<void> _showScoredCountryPickerAndConnect(
    BuildContext context,
    V2RayProvider provider,
  ) async {
    final mode = await ServerScoreStore.loadMode();
    if (mode != ServerScoreMode.scored) {
      return;
    }

    final scores = await ServerScoreStore.loadScores();
    final badIds = await ServerScoreStore.loadBadServerIds();
    final scoredIds = scores.keys.toSet();

    final scoredConfigs = provider.configs
        .where((c) => scoredIds.contains(c.id))
        .where((c) => !badIds.contains(c.id))
        .toList();

    if (scoredConfigs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No scored servers available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final Map<String, List<V2RayConfig>> grouped = {};
    final Map<String, String> countryNames = {};

    for (final config in scoredConfigs) {
      final score = scores[config.id];
      if (score == null) continue;
      final code = score.countryCode.trim();
      if (code.isEmpty) continue;
      grouped.putIfAbsent(code, () => []).add(config);
      if (score.country.isNotEmpty) {
        countryNames[code] = score.country;
      }
    }

    if (grouped.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No scored countries available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    final selectedCode = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final codes = grouped.keys.toList()..sort();
        return AlertDialog(
          backgroundColor: AppTheme.secondaryDark,
          title: const Text(
            'Select Country',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: codes.length,
              itemBuilder: (context, index) {
                final code = codes[index];
                final flag = _countryCodeToFlag(code);
                final label = countryNames[code] ?? code.toUpperCase();
                return InkWell(
                  onTap: () => Navigator.of(context).pop(code),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.5),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(flag, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.primaryGreen),
              ),
            ),
          ],
        );
      },
    );

    if (selectedCode == null || selectedCode.isEmpty) {
      return;
    }

    final selectedConfigs = grouped[selectedCode] ?? [];
    if (selectedConfigs.isEmpty) {
      return;
    }

    selectedConfigs.sort((a, b) {
      final scoreA = scores[a.id]?.score ?? 0;
      final scoreB = scores[b.id]?.score ?? 0;
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }
      final pingA = scores[a.id]?.ping ?? 10000;
      final pingB = scores[b.id]?.ping ?? 10000;
      return pingA.compareTo(pingB);
    });

    if (selectedConfigs.length == 1) {
      await provider.connectToServer(
        selectedConfigs.first,
        provider.isProxyMode,
      );
      return;
    }

    if (!mounted) return;
    final pickedConfig = await showDialog<V2RayConfig>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.secondaryDark,
          title: const Text(
            'Select Server',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: selectedConfigs.length,
              separatorBuilder: (_, __) => Divider(
                color: Colors.white.withValues(alpha: 0.08),
                height: 12,
              ),
              itemBuilder: (context, index) {
                final config = selectedConfigs[index];
                final score = scores[config.id];
                final location = _formatServerLocation(score, config);
                final cityLabel = score != null && score.city.isNotEmpty
                    ? score.city
                    : location;
                final ping = score?.ping;
                return ListTile(
                  onTap: () => Navigator.of(context).pop(config),
                  title: Text(
                    cityLabel,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: ping != null
                      ? Text(
                          '${ping}ms',
                          style: const TextStyle(
                            color: AppTheme.primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.primaryGreen),
              ),
            ),
          ],
        );
      },
    );

    if (pickedConfig == null) return;
    await provider.connectToServer(pickedConfig, provider.isProxyMode);
  }

  // Helper method to run auto-select and then connect
  Future<void> _runAutoSelectAndConnect(
    BuildContext context,
    V2RayProvider provider,
  ) async {
    final mode = await ServerScoreStore.loadMode();
    final scores = await ServerScoreStore.loadScores();
    final badIds = await ServerScoreStore.loadBadServerIds();
    if (!mounted) return;
    final scoredIds = scores.keys.toSet();
    final configs = mode == ServerScoreMode.scored
        ? provider.configs
              .where((c) => scoredIds.contains(c.id))
              .where((c) => !badIds.contains(c.id))
              .toList()
        : provider.configs
              .where((c) => !scoredIds.contains(c.id))
              .where((c) => !badIds.contains(c.id))
              .toList();

    if (configs.isEmpty) {
      if (!mounted) return;
      final message = mode == ServerScoreMode.scored
          ? 'No scored servers available'
          : context.tr(TranslationKeys.serverSelectorNoServers);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
      return;
    }

    // Create cancellation token for this auto-select operation
    _autoSelectCancellationToken = AutoSelectCancellationToken();

    try {
      AutoSelectResult result;
      if (mode == ServerScoreMode.scored) {
        _autoSelectStatusStream.add('Using saved scores...');
        configs.sort((a, b) {
          final scoreA = scores[a.id]?.score ?? 0;
          final scoreB = scores[b.id]?.score ?? 0;
          if (scoreA != scoreB) {
            return scoreB.compareTo(scoreA);
          }
          final pingA = scores[a.id]?.ping ?? 10000;
          final pingB = scores[b.id]?.ping ?? 10000;
          return pingA.compareTo(pingB);
        });
        result = AutoSelectResult(
          selectedConfig: configs.first,
          bestPing: scores[configs.first.id]?.ping,
        );
      } else {
        // Run auto-select algorithm with cancellation support and status updates
        provider.setSmartFlowState(SmartFlowState.searching);
        result = await AutoSelectUtil.runAutoSelect(
          configs,
          provider.v2rayService,
          onStatusUpdate: (message) {
            // Update status in the dialog
            _autoSelectStatusStream.add(message);
          },
          onBadServer: (config) async {
            await ServerScoreStore.addBadServer(config.id);
            await ServerScoreStore.removeScore(config.id);
          },
          cancellationToken: _autoSelectCancellationToken,
        );
        if (provider.connectMode == ConnectMode.normal) {
          provider.setSmartFlowState(SmartFlowState.idle);
        }
      }

      // Check if operation was cancelled
      if (!mounted) return;
      if (result.errorMessage == 'Auto-select cancelled') {
        if (provider.connectMode == ConnectMode.normal) {
          provider.setSmartFlowState(SmartFlowState.idle);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('common.cancel')),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (result.selectedConfig != null && result.bestPing != null) {
        // Select and connect to the best server
        await provider.selectConfig(result.selectedConfig!);
        await provider.connectToServer(
          result.selectedConfig!,
          provider.isProxyMode,
        );
      } else {
        // Show error message
        if (!mounted) return;
        if (provider.connectMode == ConnectMode.normal) {
          provider.setSmartFlowState(SmartFlowState.idle);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Auto-select failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Show error message
      if (!mounted) return;
      if (provider.connectMode == ConnectMode.normal) {
        provider.setSmartFlowState(SmartFlowState.idle);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-select error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Map<String, String>> _loadCustomPresets() {
    const rawPresets = '''[
  {
    "remarks": "ServLess frag tlshello",
    "log": {
      "access": "",
      "error": "",
      "loglevel": "none",
      "dnsLog": false
    },
    "dns": {
      "tag": "dns",
      "hosts": {
        "cloudflare-dns.com": [
          "172.67.73.38",
          "104.19.155.92",
          "172.67.73.163",
          "104.18.155.42",
          "104.16.124.175",
          "104.16.248.249",
          "104.16.249.249",
          "104.26.13.8"
        ],
        "domain:youtube.com": ["google.com"]
      },
      "servers": ["https://cloudflare-dns.com/dns-query"]
    },
    "inbounds": [
      {
        "domainOverride": ["http", "tls"],
        "protocol": "socks",
        "tag": "socks-in",
        "listen": "127.0.0.1",
        "port": 10808,
        "settings": {
          "auth": "noauth",
          "udp": true,
          "userLevel": 8
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        }
      },
      {
        "protocol": "http",
        "tag": "http-in",
        "listen": "127.0.0.1",
        "port": 10809,
        "settings": {
          "userLevel": 8
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        }
      }
    ],
    "outbounds": [
      {
        "protocol": "freedom",
        "tag": "fragment-out",
        "domainStrategy": "UseIP",
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        },
        "settings": {
          "fragment": {
            "packets": "tlshello",
            "length": "10-20",
            "interval": "10-20"
          }
        },
        "streamSettings": {
          "sockopt": {
            "tcpNoDelay": true,
            "tcpKeepAliveIdle": 100,
            "mark": 255,
            "domainStrategy": "UseIP"
          }
        }
      },
      {
        "protocol": "dns",
        "tag": "dns-out"
      },
      {
        "protocol": "vless",
        "tag": "fakeproxy-out",
        "domainStrategy": "",
        "settings": {
          "vnext": [
            {
              "address": "google.com",
              "port": 443,
              "users": [
                {
                  "encryption": "none",
                  "flow": "",
                  "id": "UUID",
                  "level": 8,
                  "security": "auto"
                }
              ]
            }
          ]
        },
        "streamSettings": {
          "network": "ws",
          "security": "tls",
          "tlsSettings": {
            "allowInsecure": false,
            "alpn": ["h2", "http/1.1"],
            "fingerprint": "randomized",
            "publicKey": "",
            "serverName": "google.com",
            "shortId": "",
            "show": false,
            "spiderX": ""
          },
          "wsSettings": {
            "headers": {
              "Host": "google.com"
            },
            "path": "/"
          }
        },
        "mux": {
          "concurrency": 8,
          "enabled": false
        }
      }
    ],
    "policy": {
      "levels": {
        "8": {
          "connIdle": 300,
          "downlinkOnly": 1,
          "handshake": 4,
          "uplinkOnly": 1
        }
      },
      "system": {
        "statsOutboundUplink": true,
        "statsOutboundDownlink": true
      }
    },
    "routing": {
      "domainStrategy": "IPIfNonMatch",
      "rules": [
        {
          "inboundTag": ["socks-in", "http-in"],
          "type": "field",
          "port": "53",
          "outboundTag": "dns-out",
          "enabled": true
        },
        {
          "inboundTag": ["socks-in", "http-in"],
          "type": "field",
          "port": "0-65535",
          "outboundTag": "fragment-out",
          "enabled": true
        }
      ],
      "strategy": "rules"
    },
    "stats": {}
  },
  {
    "remarks": "ServLess frag 1-1",
    "log": {
      "access": "",
      "error": "",
      "loglevel": "none",
      "dnsLog": false
    },
    "dns": {
      "tag": "dns",
      "hosts": {
        "cloudflare-dns.com": [
          "172.67.73.38",
          "104.19.155.92",
          "172.67.73.163",
          "104.18.155.42",
          "104.16.124.175",
          "104.16.248.249",
          "104.16.249.249",
          "104.26.13.8"
        ],
        "domain:youtube.com": ["google.com"]
      },
      "servers": ["https://cloudflare-dns.com/dns-query"]
    },
    "inbounds": [
      {
        "domainOverride": ["http", "tls"],
        "protocol": "socks",
        "tag": "socks-in",
        "listen": "127.0.0.1",
        "port": 10808,
        "settings": {
          "auth": "noauth",
          "udp": true,
          "userLevel": 8
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        }
      },
      {
        "protocol": "http",
        "tag": "http-in",
        "listen": "127.0.0.1",
        "port": 10809,
        "settings": {
          "userLevel": 8
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        }
      }
    ],
    "outbounds": [
      {
        "protocol": "freedom",
        "tag": "fragment-out",
        "domainStrategy": "UseIP",
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        },
        "settings": {
          "fragment": {
            "packets": "1-1",
            "length": "1-3",
            "interval": "5-10"
          }
        },
        "streamSettings": {
          "sockopt": {
            "tcpNoDelay": true,
            "tcpKeepAliveIdle": 100,
            "mark": 255,
            "domainStrategy": "UseIP"
          }
        }
      },
      {
        "protocol": "dns",
        "tag": "dns-out"
      },
      {
        "protocol": "vless",
        "tag": "fakeproxy-out",
        "domainStrategy": "",
        "settings": {
          "vnext": [
            {
              "address": "google.com",
              "port": 443,
              "users": [
                {
                  "encryption": "none",
                  "flow": "",
                  "id": "UUID",
                  "level": 8,
                  "security": "auto"
                }
              ]
            }
          ]
        },
        "streamSettings": {
          "network": "ws",
          "security": "tls",
          "tlsSettings": {
            "allowInsecure": false,
            "alpn": ["h2", "http/1.1"],
            "fingerprint": "randomized",
            "publicKey": "",
            "serverName": "google.com",
            "shortId": "",
            "show": false,
            "spiderX": ""
          },
          "wsSettings": {
            "headers": {
              "Host": "google.com"
            },
            "path": "/"
          }
        },
        "mux": {
          "concurrency": 8,
          "enabled": false
        }
      }
    ],
    "policy": {
      "levels": {
        "8": {
          "connIdle": 300,
          "downlinkOnly": 1,
          "handshake": 4,
          "uplinkOnly": 1
        }
      },
      "system": {
        "statsOutboundUplink": true,
        "statsOutboundDownlink": true
      }
    },
    "routing": {
      "domainStrategy": "IPIfNonMatch",
      "rules": [
        {
          "inboundTag": ["socks-in", "http-in"],
          "type": "field",
          "port": "53",
          "outboundTag": "dns-out",
          "enabled": true
        },
        {
          "inboundTag": ["socks-in", "http-in"],
          "type": "field",
          "port": "0-65535",
          "outboundTag": "fragment-out",
          "enabled": true
        }
      ],
      "strategy": "rules"
    },
    "stats": {}
  }
]''';

    final data = jsonDecode(rawPresets) as List<dynamic>;
    return data.map((entry) {
      final map = entry as Map<String, dynamic>;
      final remark = map['remarks']?.toString() ?? 'Custom';
      return {'remark': remark, 'config': jsonEncode(map)};
    }).toList();
  }

  Widget _buildModeDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDot(_pageIndex == 0),
        const SizedBox(width: 6),
        _buildDot(_pageIndex == 1),
      ],
    );
  }

  Widget _buildDot(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 16 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? AppTheme.primaryGreen : AppTheme.textGrey,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<V2RayProvider>(
      builder: (context, provider, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {});
        // Show loading state while initializing
        if (provider.isInitializing) {
          return Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.cardDark,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                strokeWidth: 4,
              ),
            ),
          );
        }

        final isConnected = provider.activeConfig != null;
        final isConnecting = provider.isConnecting;
        final selectedConfig = provider.selectedConfig;
        final hasConfigs = provider.configs.isNotEmpty;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: AnimatedBuilder(
                        animation: _pageController,
                        builder: (context, child) {
                          final page = _pageController.hasClients
                              ? (_pageController.page ?? _pageIndex.toDouble())
                              : _pageIndex.toDouble();
                          return PageView(
                            controller: _pageController,
                            physics: isConnected ||
                                    isConnecting ||
                                    provider.smartFlowState !=
                                        SmartFlowState.idle
                                ? const NeverScrollableScrollPhysics()
                                : const BouncingScrollPhysics(),
                            clipBehavior: Clip.none,
                            onPageChanged: (index) {
                              setState(() {
                                _pageIndex = index;
                              });
                              provider.setConnectMode(
                                index == 1
                                    ? ConnectMode.smart
                                    : ConnectMode.normal,
                              );
                            },
                            children: [
                              Opacity(
                                opacity: (1 - (page - 0).abs()).clamp(0.0, 1.0),
                                child: _buildConnectButton(
                                  context,
                                  provider,
                                  isCustom: false,
                                  isConnected: isConnected,
                                  isConnecting: isConnecting,
                                  selectedConfig: selectedConfig,
                                  hasConfigs: hasConfigs,
                                  smartFlowState: provider.smartFlowState,
                                ),
                              ),
                              Opacity(
                                opacity: (1 - (page - 1).abs()).clamp(0.0, 1.0),
                                child: _buildConnectButton(
                                  context,
                                  provider,
                                  isCustom: true,
                                  isConnected: isConnected,
                                  isConnecting: isConnecting,
                                  selectedConfig: selectedConfig,
                                  hasConfigs: hasConfigs,
                                  smartFlowState: provider.smartFlowState,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  
                  if (!isConnected &&
                      !isConnecting &&
                      provider.smartFlowState == SmartFlowState.idle &&
                      _pageIndex == 0)
                    Positioned(
                      left: 0,
                      child: _buildPageArrow(
                        icon: Icons.arrow_back_ios_new,
                        onTap: () {
                          _pageController.animateToPage(
                            1,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        },
                      ),
                    ),
                  if (!isConnected &&
                      !isConnecting &&
                      provider.smartFlowState == SmartFlowState.idle &&
                      _pageIndex == 1)
                    Positioned(
                      right: 0,
                      child: _buildPageArrow(
                        icon: Icons.arrow_forward_ios,
                        onTap: () {
                          _pageController.animateToPage(
                            0,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildModeDots(),
          ],
        );
      },
    );
  }

  Widget _buildConnectButton(
    BuildContext context,
    V2RayProvider provider, {
    required bool isCustom,
    required bool isConnected,
    required bool isConnecting,
    required V2RayConfig? selectedConfig,
    required bool hasConfigs,
    required SmartFlowState smartFlowState,
  }) {
    final isReplacing = smartFlowState == SmartFlowState.searching && !isCustom;
    final isTesting = smartFlowState == SmartFlowState.testing && !isCustom;
    final effectiveConnecting = isConnecting || isReplacing || isTesting;
    final isBusy = isConnecting || smartFlowState != SmartFlowState.idle;
    return GestureDetector(
      onTap: () async {
        if (!widget.isEnabled) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'دسترسی شما توسط ادمین در حالت تعلیق در آمده است',
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          return;
        }
        if (provider.isInitializing) {
          return;
        }

        try {
          if (isBusy) {
            _autoSelectCancellationToken?.cancel();
            _autoSelectCancellationToken = null;
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            await provider.cancelSmartFlowAndDisconnect();
            return;
          }

          if (isConnected) {
            await provider.disconnect();
            return;
          }

          if (isCustom) {
            final presets = _loadCustomPresets();
            if (presets.isEmpty) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Custom config missing'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
              return;
            }
            await provider.connectToCustomConfigs(presets);
            return;
          }

          if (selectedConfig != null) {
            final mode = await ServerScoreStore.loadMode();
            if (mode == ServerScoreMode.scored) {
              await _showScoredCountryPickerAndConnect(context, provider);
              return;
            }
            final scores = await ServerScoreStore.loadScores();
            final badIds = await ServerScoreStore.loadBadServerIds();
            final scoredIds = scores.keys.toSet();
            final isBad = badIds.contains(selectedConfig.id);
            final isScored = scoredIds.contains(selectedConfig.id);
            final useSelected = mode == ServerScoreMode.scored
                ? isScored
                : !isScored;

            if (isBad || !useSelected) {
              await _runAutoSelectAndConnect(context, provider);
              return;
            }
            await provider.connectToServer(
              selectedConfig,
              provider.isProxyMode,
            );
          } else if (hasConfigs) {
            final mode = await ServerScoreStore.loadMode();
            if (mode == ServerScoreMode.scored) {
              await _showScoredCountryPickerAndConnect(context, provider);
              return;
            }
            await _runAutoSelectAndConnect(context, provider);
          } else {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.tr(TranslationKeys.serverSelectorNoServers),
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${context.tr('home.connection_failed')}: ${e.toString()}',
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      },
      child: AnimatedScale(
        scale: effectiveConnecting ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        child: SizedBox(
          width: 210,
          height: 210,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: widget.isEnabled ? 1.0 : 0.5,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _getButtonColor(
                          isConnected,
                          isConnecting,
                          isCustom,
                          isReplacing,
                          isTesting,
                        ).withValues(alpha: 0.4),
                        blurRadius: 25,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulsing background ring (only visible when connecting)
                      if (effectiveConnecting)
                        Container(
                              width: 210,
                              height: 210,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _getButtonColor(
                                    isConnected,
                                    effectiveConnecting,
                                    isCustom,
                                    isReplacing,
                                    isTesting,
                                  ).withValues(alpha: 0.3),
                                  width: 4,
                                ),
                              ),
                            )
                            .animate(
                              onPlay: (controller) => controller.repeat(reverse: true),
                            )
                            .scaleXY(end: 1.2, duration: 1000.ms),

                      // Outer animated ring (only visible when connecting)
                      if (effectiveConnecting)
                        Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _getButtonColor(
                                    isConnected,
                                    effectiveConnecting,
                                    isCustom,
                                    isReplacing,
                                    isTesting,
                                  ),
                                  width: 3,
                                ),
                              ),
                            )
                            .animate(onPlay: (controller) => controller.repeat())
                            .rotate(duration: 2000.ms, begin: 0, end: 1),

                      // Middle ring
                      if (effectiveConnecting)
                        Container(
                              width: 170,
                              height: 170,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _getButtonColor(
                                    isConnected,
                                    effectiveConnecting,
                                    isCustom,
                                    isReplacing,
                                    isTesting,
                                  ).withValues(alpha: 0.7),
                                  width: 2,
                                ),
                              ),
                            )
                            .animate(
                              onPlay: (controller) => controller.repeat(reverse: true),
                            )
                            .scaleXY(end: 1.1, duration: 1500.ms),

                      // Main button with enhanced design
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _getGradientColors(
                              isConnected,
                              effectiveConnecting,
                              isCustom,
                              isReplacing,
                              isTesting,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _getButtonColor(
                                isConnected,
                                effectiveConnecting,
                                isCustom,
                                isReplacing,
                                isTesting,
                              ).withValues(alpha: 0.5),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Inner glow effect
                            Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.2),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),

                            // Icon with label
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _getButtonIcon(isConnected, effectiveConnecting),
                                  color: Colors.white,
                                  size: 54,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _getButtonText(
                                    isConnected,
                                    effectiveConnecting,
                                    hasConfigs,
                                    isCustom,
                                    smartFlowState,
                                  ),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: isCustom ? 0.6 : 0.2,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),

                            if (isCustom)
                              Positioned(
                                top: 14,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: const Text(
                                    'SMART',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),

                            // Progress indicator when connecting
                            if (effectiveConnecting)
                              Positioned.fill(
                                child: CircularProgressIndicator(
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                  strokeWidth: 3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!widget.isEnabled)
                Positioned(
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Icon(Icons.lock, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageArrow({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.cardDark.withValues(alpha: 0.9),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }

  Color _getButtonColor(
    bool isConnected,
    bool isConnecting,
    bool isCustom,
    bool isReplacing,
    bool isTesting,
  ) {
    if (isConnecting) {
      if (isTesting && !isCustom) {
        return AppTheme.connectedGreen;
      }
      if (isReplacing && !isCustom) {
        return Colors.amber;
      }
      return isCustom ? AppTheme.primaryBlueDark : AppTheme.connectingBlue;
    }
    if (isConnected) {
      return isCustom ? AppTheme.primaryBlue : AppTheme.connectedGreen;
    }
    return isCustom ? AppTheme.primaryBlueDark : AppTheme.disconnectedRed;
  }

  List<Color> _getGradientColors(
    bool isConnected,
    bool isConnecting,
    bool isCustom,
    bool isReplacing,
    bool isTesting,
  ) {
    if (isConnecting) {
      if (isTesting && !isCustom) {
        return [
          AppTheme.connectedGreen,
          AppTheme.connectedGreen.withValues(alpha: 0.7),
        ];
      }
      if (isReplacing && !isCustom) {
        return [Colors.amber, Colors.amber.withValues(alpha: 0.7)];
      }
      return isCustom
          ? [
              AppTheme.primaryBlueDark,
              AppTheme.primaryBlue.withValues(alpha: 0.7),
            ]
          : [
              AppTheme.connectingBlue,
              AppTheme.connectingBlue.withValues(alpha: 0.7),
            ];
    } else if (isConnected) {
      return isCustom
          ? [
              AppTheme.primaryBlue,
              AppTheme.primaryBlueDark.withValues(alpha: 0.7),
            ]
          : [
              AppTheme.connectedGreen,
              AppTheme.connectedGreen.withValues(alpha: 0.7),
            ];
    } else {
      return isCustom
          ? [
              AppTheme.primaryBlueDark,
              AppTheme.primaryBlue.withValues(alpha: 0.7),
            ]
          : [
              AppTheme.disconnectedRed,
              AppTheme.disconnectedRed.withValues(alpha: 0.7),
            ];
    }
  }

  IconData _getButtonIcon(bool isConnected, bool isConnecting) {
    if (isConnecting) return Icons.sync;
    return isConnected ? Icons.power_off : Icons.power_settings_new;
  }

  String _getButtonText(
    bool isConnected,
    bool isConnecting,
    bool hasConfigs,
    bool isCustom,
    SmartFlowState smartFlowState,
  ) {
    if (!isCustom && smartFlowState == SmartFlowState.searching) {
      return 'در حال جایگزینی سرور';
    }
    if (isConnecting) return 'در حال اتصال...';
    if (!isCustom && smartFlowState == SmartFlowState.testing) {
      return 'در حال تست سرور';
    }
    if (isConnected) return 'قطع اتصال';
    if (isCustom) return 'اتصال هوشمند (اینستاگرام و یوتیوب)';
    if (hasConfigs) return 'XConnect';
    return 'No Servers';
  }
}
