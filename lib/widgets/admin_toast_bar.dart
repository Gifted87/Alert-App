import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_remote_config.dart';

/// A single, dismissible admin message shown once per cold app launch.
/// The announcement is read from the already-cached shared settings at 30s.
class AdminToastBarHost extends StatefulWidget {
  final double bottomOffset;

  const AdminToastBarHost({super.key, this.bottomOffset = 14});

  @override
  State<AdminToastBarHost> createState() => _AdminToastBarHostState();
}

class _AdminToastBarHostState extends State<AdminToastBarHost> {
  final AppRemoteConfig _config = AppRemoteConfig.instance;
  Timer? _timer;
  bool _delayElapsed = false;
  String? _subject;
  String? _tagline;
  String? _linkUrl;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    final remaining = _config.toastBarDelayRemaining;
    _timer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      _onDelayElapsed,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onDelayElapsed() {
    if (!mounted) return;
    final subject = _config.toastBarSubject;
    final tagline = _config.toastBarTagline;
    final uri = Uri.tryParse(_config.toastBarLinkUrl);
    setState(() {
      _delayElapsed = true;
      if (_config.toastBarEnabled &&
          subject.isNotEmpty &&
          tagline.isNotEmpty &&
          uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty) {
        _subject = subject;
        _tagline = tagline;
        _linkUrl = _config.toastBarLinkUrl;
        _imageUrl = _config.toastBarImageUrl;
      }
    });
  }

  Future<void> _openLink() async {
    final uri = Uri.tryParse(_linkUrl ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Keep the app usable if the device cannot open the destination.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_delayElapsed ||
        _config.toastBarDismissedThisLaunch ||
        _subject == null ||
        _tagline == null) {
      return const SizedBox.shrink();
    }

    final subject = _subject!;
    final tagline = _tagline!;
    final link = Uri.tryParse(_linkUrl ?? '');
    if (subject.isEmpty ||
        tagline.isEmpty ||
        link == null ||
        link.scheme != 'https' ||
        link.host.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageUrl = _imageUrl ?? '';
    final media = MediaQuery.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          media.viewInsets.bottom + widget.bottomOffset,
        ),
        child: SafeArea(
          top: false,
          bottom: false,
        child: Material(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x38FFFFFF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 26,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                InkWell(
                  onTap: _openLink,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (imageUrl.isNotEmpty)
                        Image.network(
                          imageUrl,
                          height: 150,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 15, 48, 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Color(0x3330D158),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_active_rounded,
                                color: Color(0xFF43E06A),
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    subject,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tagline,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFE5E5EA),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 9),
                            const Icon(
                              Icons.open_in_new_rounded,
                              color: Color(0xFFA9C6FD),
                              size: 19,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 7,
                  right: 7,
                  child: Material(
                    color: const Color(0x990D0D0F),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Dismiss message',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(
                        _config.dismissToastBarForThisLaunch,
                      ),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
