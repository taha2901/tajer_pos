import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';

bool get cameraScanSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Scans one code (camera or manual entry). Returns the code or null.
Future<String?> scanBarcode(BuildContext context) {
  return showAppSheet<String>(
    context,
    expand: true,
    builder: (ctx) => _ScannerView(onCode: (code) async {
      Navigator.pop(ctx, code);
      return null;
    }),
  );
}

/// Continuous scanning (POS): each code goes to [onCode], which returns a
/// short feedback message ("added X") or an error. The sheet stays open.
Future<void> scanContinuous(BuildContext context, Future<(String, bool)?> Function(String code) onCode) {
  return showAppSheet<void>(
    context,
    expand: true,
    builder: (_) => _ScannerView(onCode: onCode, continuous: true),
  );
}

class _ScannerView extends StatefulWidget {
  const _ScannerView({required this.onCode, this.continuous = false});
  final Future<(String, bool)?> Function(String code) onCode;
  final bool continuous;

  @override
  State<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<_ScannerView> {
  final _manual = TextEditingController();
  MobileScannerController? _controller;
  String? _last;
  DateTime _lastAt = DateTime(2000);
  (String, bool)? _feedback;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    if (cameraScanSupported) {
      _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal, formats: const [BarcodeFormat.all]);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _handle(String code) async {
    final now = DateTime.now();
    // Ignore the same code detected repeatedly within a short window.
    if (code == _last && now.difference(_lastAt) < const Duration(milliseconds: 1500)) return;
    _last = code;
    _lastAt = now;
    HapticFeedback.mediumImpact();
    final fb = await widget.onCode(code);
    if (!mounted || fb == null) return;
    setState(() {
      _feedback = fb;
      if (fb.$2) _count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.continuous ? 'مسح متواصل' : 'مسح الباركود', style: context.text.titleLarge)),
              if (widget.continuous && _count > 0) StatusPill('تمت إضافة $_count', tone: Tone.success),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _controller == null
                  ? Container(
                      color: p.subtle,
                      child: const EmptyView(
                        icon: Icons.no_photography_outlined,
                        title: 'الكاميرا غير متاحة على هذا الجهاز',
                        message: 'أدخل الباركود يدوياً أو استخدم قارئ باركود USB في حقل البحث',
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _controller,
                          onDetect: (capture) {
                            final code = capture.barcodes.firstOrNull?.rawValue;
                            if (code != null && code.isNotEmpty) _handle(code);
                          },
                          errorBuilder: (ctx, error) => Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'تعذّر تشغيل الكاميرا (${error.errorCode.name}). امنح صلاحية الكاميرا أو أدخل الكود يدوياً.',
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            width: 260,
                            height: 150,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 2.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: IconButton.filledTonal(
                            onPressed: () => _controller?.toggleTorch(),
                            icon: const Icon(Icons.flash_on_rounded),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (_feedback != null) ...[
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Container(
                key: ValueKey(_feedback),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _feedback!.$2 ? p.successBg : p.dangerBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(_feedback!.$2 ? Icons.check_circle : Icons.error, color: _feedback!.$2 ? p.success : p.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_feedback!.$1, style: TextStyle(color: _feedback!.$2 ? p.success : p.danger))),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manual,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'إدخال الكود يدوياً', prefixIcon: Icon(Icons.keyboard_alt_outlined)),
                  onSubmitted: (v) {
                    if (v.trim().isEmpty) return;
                    _last = null;
                    _handle(v.trim());
                    _manual.clear();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () {
                  if (_manual.text.trim().isEmpty) return;
                  _last = null;
                  _handle(_manual.text.trim());
                  _manual.clear();
                },
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ],
          ),
          if (widget.continuous) ...[
            const SizedBox(height: 10),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تم')),
          ],
        ],
      ),
    );
  }
}
