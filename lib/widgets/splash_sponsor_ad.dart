import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_remote_config.dart';
import '../theme/app_theme.dart';

/// Shows a directly managed sponsored image only after the image is available.
/// Both the artwork and its destination are supplied through Remote Config.
class SplashSponsorAd extends StatefulWidget {
  const SplashSponsorAd({super.key});

  @override
  State<SplashSponsorAd> createState() => _SplashSponsorAdState();
}

class _SplashSponsorAdState extends State<SplashSponsorAd> {
  final AppRemoteConfig _config = AppRemoteConfig.instance;
  bool _imageReady = false;
  bool _impressionLogged = false;
  String? _checkedImageUrl;
  Timer? _impressionTimer;

  @override
  void initState() {
    super.initState();
    _config.addListener(_onConfigChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preloadImage();
  }

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    _impressionTimer?.cancel();
    super.dispose();
  }

  void _onConfigChanged() {
    if (_checkedImageUrl != _config.splashAdImageUrl) {
      _preloadImage();
    }
    if (mounted) setState(() {});
  }

  void _preloadImage() {
    final imageUrl = _config.splashAdImageUrl;
    if (imageUrl == _checkedImageUrl) return;
    _checkedImageUrl = imageUrl;
    _imageReady = false;
    _impressionLogged = false;
    _impressionTimer?.cancel();

    final uri = Uri.tryParse(imageUrl);
    if (!_config.splashAdEnabled ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      return;
    }

    final provider = NetworkImage(imageUrl);
    precacheImage(provider, context)
        .then((_) {
          if (!mounted || !_config.splashAdEnabled) return;
          setState(() => _imageReady = true);
          _impressionTimer = Timer(const Duration(seconds: 1), () {
            if (!mounted || !_imageReady || _impressionLogged) return;
            _impressionLogged = true;
            _config.logSplashAdImpression();
          });
        })
        .catchError((Object _) {
          // No blank placeholder is left on screen when the image is unavailable.
        });
  }

  Future<void> _openAd() async {
    final uri = Uri.tryParse(_config.splashAdLinkUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    await _config.logSplashAdClick();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Keep the splash stable if no handler can open the destination.
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = Uri.tryParse(_config.splashAdLinkUrl);
    if (!_imageReady ||
        !_config.splashAdEnabled ||
        target == null ||
        target.scheme != 'https' ||
        target.host.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: '${_config.splashAdLabel}. Opens sponsored link.',
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Material(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _openAd,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(21),
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 3.1,
                      child: Image.network(
                        _config.splashAdImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xD91C1C1E),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: Text(
                            _config.splashAdLabel,
                            style: AppTheme.sans(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.25,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xD91C1C1E),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Icon(
                          Icons.north_east_rounded,
                          size: 15,
                          color: Colors.white,
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
