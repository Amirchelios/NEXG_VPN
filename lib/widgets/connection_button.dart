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
  const ConnectionButton({super.key});

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
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Create cancellation token for this auto-select operation
    _autoSelectCancellationToken = AutoSelectCancellationToken();

    // Show a loading dialog while auto-select is running with cancel button
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.secondaryDark,
        title: Text(context.tr(TranslationKeys.serverSelectionAutoSelect)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
            ),
            const SizedBox(height: 16),
            Text(context.tr(TranslationKeys.serverSelectionTestingServers)),
            const SizedBox(height: 8),
            StreamBuilder<String>(
              stream: _autoSelectStatusStream.stream,
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Cancel the auto-select operation
              _autoSelectCancellationToken?.cancel();
              Navigator.of(context).pop();
            },
            child: Text(
              context.tr('common.cancel'),
              style: const TextStyle(color: AppTheme.primaryGreen),
            ),
          ),
        ],
      ),
    );

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
      }

      // Check if operation was cancelled
      if (!mounted) return;
      if (result.errorMessage == 'Auto-select cancelled') {
        // Close the dialog
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('common.cancel')),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Close the dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Auto-select failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Close the dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      if (!mounted) return;
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
      return {
        'remark': remark,
        'config': jsonEncode(map),
      };
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
              width: 220,
              height: 220,
              child: PageView(
                controller: _pageController,
                physics:
                    isConnected ||
                            isConnecting ||
                            provider.smartFlowState != SmartFlowState.idle
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                clipBehavior: Clip.none,
                onPageChanged: (index) {
                  setState(() {
                    _pageIndex = index;
                  });
                  provider.setConnectMode(
                    index == 1 ? ConnectMode.smart : ConnectMode.normal,
                  );
                },
                children: [
                  _buildConnectButton(
                    context,
                    provider,
                    isCustom: false,
                    isConnected: isConnected,
                    isConnecting: isConnecting,
                    selectedConfig: selectedConfig,
                    hasConfigs: hasConfigs,
                    smartFlowState: provider.smartFlowState,
                  ),
                  _buildConnectButton(
                    context,
                    provider,
                    isCustom: true,
                    isConnected: isConnected,
                    isConnecting: isConnecting,
                    selectedConfig: selectedConfig,
                    hasConfigs: hasConfigs,
                    smartFlowState: provider.smartFlowState,
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
    final effectiveConnecting =
        isConnecting || smartFlowState == SmartFlowState.searching;
    return GestureDetector(
      onTap: () async {
        if (provider.isInitializing) {
          return;
        }

        try {
          if (isConnecting || smartFlowState != SmartFlowState.idle) {
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
            final scores = await ServerScoreStore.loadScores();
            final badIds = await ServerScoreStore.loadBadServerIds();
            final scoredIds = scores.keys.toSet();
            final isBad = badIds.contains(selectedConfig.id);
            final isScored = scoredIds.contains(selectedConfig.id);
            final useSelected =
                mode == ServerScoreMode.scored ? isScored : !isScored;

            if (isBad || !useSelected) {
              await _runAutoSelectAndConnect(context, provider);
              return;
            }
            await provider.connectToServer(
              selectedConfig,
              provider.isProxyMode,
            );
          } else if (hasConfigs) {
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
                          ).withValues(alpha: 0.3),
                          width: 4,
                        ),
                      ),
                    )
                    .animate(
                      onPlay: (controller) =>
                          controller.repeat(reverse: true),
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
                          ).withValues(alpha: 0.7),
                          width: 2,
                        ),
                      ),
                    )
                    .animate(
                      onPlay: (controller) =>
                          controller.repeat(reverse: true),
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
                  ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _getButtonColor(
                        isConnected,
                        effectiveConnecting,
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
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
    );
  }

  Color _getButtonColor(bool isConnected, bool isConnecting) {
    if (isConnecting) return AppTheme.connectingBlue;
    return isConnected ? AppTheme.connectedGreen : AppTheme.disconnectedRed;
  }

  List<Color> _getGradientColors(bool isConnected, bool isConnecting) {
    if (isConnecting) {
      return [
        AppTheme.connectingBlue,
        AppTheme.connectingBlue.withValues(alpha: 0.7),
      ];
    } else if (isConnected) {
      return [
        AppTheme.connectedGreen,
        AppTheme.connectedGreen.withValues(alpha: 0.7),
      ];
    } else {
      return [
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

