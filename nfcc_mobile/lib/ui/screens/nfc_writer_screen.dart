import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import 'package:nfc_manager/ndef_record.dart';
import '../../services/nfc_service.dart';
import '../theme/app_theme.dart';

class NfcWriterScreen extends StatefulWidget {
  const NfcWriterScreen({super.key});

  @override
  State<NfcWriterScreen> createState() => _NfcWriterScreenState();
}

class _NfcWriterScreenState extends State<NfcWriterScreen> {
  String? _statusMsg;
  bool _busy = false;

  void _setStatus(String msg, {bool busy = false}) {
    final wasBusy = _busy;
    if (mounted) setState(() { _statusMsg = msg; _busy = busy; });
    if (wasBusy && !busy) _feedbackForResult(msg);
  }

  void _feedbackForResult(String msg) {
    final lower = msg.toLowerCase();
    final success = lower.contains('success') || lower.contains('written');
    final failure = lower.contains('fail') ||
        lower.contains('error') ||
        lower.contains('not available');
    if (success) {
      // Long vibration + one notification beep
      HapticFeedback.vibrate();
      Future.delayed(const Duration(milliseconds: 120),
          () => HapticFeedback.vibrate());
      SystemSound.play(SystemSoundType.alert);
    } else if (failure) {
      // Short vibration, no sound
      HapticFeedback.lightImpact();
    }
  }

  void _cancel() {
    context.read<NfcService>().stopSession();
    if (mounted) setState(() { _statusMsg = null; _busy = false; });
  }

  // ── Write helpers ─────────────────────────────────────────────────────

  Future<void> _writeNdef(List<NdefRecord> records, String label) async {
    final nfc = context.read<NfcService>();
    if (!await nfc.isAvailable()) {
      _setStatus('NFC not available');
      return;
    }
    _setStatus('Hold NFC tag near device...', busy: true);

    await nfc.startRawWriteSession(
      records: records,
      onResult: (success, msg) {
        if (success) {
          _setStatus('$label written successfully!');
        } else {
          _setStatus('Write failed: $msg');
        }
      },
    );
  }

  Future<void> _readTag() async {
    final nfc = context.read<NfcService>();
    if (!await nfc.isAvailable()) {
      _setStatus('NFC not available');
      return;
    }
    _setStatus('Hold NFC tag near device...', busy: true);

    await nfc.startReadSession(
      onDiscovered: (result) {
        final lines = <String>[];
        lines.add('UID: ${result.uid}');
        lines.add('Type: ${result.tagType ?? "Unknown"}');
        lines.add('Tech: ${result.technology ?? "Unknown"}');
        if (result.ndefText != null) lines.add('Data: ${result.ndefText}');
        _setStatus(lines.join('\n'));
      },
      onError: (e) => _setStatus('Error: $e'),
    );
  }

  Future<void> _formatTag() async {
    final nfc = context.read<NfcService>();
    if (!await nfc.isAvailable()) {
      _setStatus('NFC not available');
      return;
    }
    _setStatus('Hold tag to erase...', busy: true);

    await nfc.startFormatSession(
      onResult: (ok, msg) => _setStatus(msg),
    );
  }

  // ── Record builders ───────────────────────────────────────────────────

  NdefRecord _urlRecord(String url) {
    int prefix = 0;
    String stripped = url;
    const prefixes = {
      'http://www.': 1, 'https://www.': 2,
      'http://': 3, 'https://': 4,
      'tel:': 5, 'mailto:': 6,
    };
    for (final entry in prefixes.entries) {
      if (url.startsWith(entry.key)) {
        prefix = entry.value;
        stripped = url.substring(entry.key.length);
        break;
      }
    }
    final payload = Uint8List(1 + stripped.length);
    payload[0] = prefix;
    payload.setRange(1, payload.length, utf8.encode(stripped));

    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x55]),
      identifier: Uint8List(0),
      payload: payload,
    );
  }

  NdefRecord _textRecord(String text) {
    const lang = 'en';
    final langBytes = utf8.encode(lang);
    final textBytes = utf8.encode(text);
    final payload = Uint8List(1 + langBytes.length + textBytes.length);
    payload[0] = langBytes.length & 0x3f;
    payload.setRange(1, 1 + langBytes.length, langBytes);
    payload.setRange(1 + langBytes.length, payload.length, textBytes);

    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x54]),
      identifier: Uint8List(0),
      payload: payload,
    );
  }

  NdefRecord _wifiRecord(String ssid, String password, String auth) {
    final config = 'WIFI:T:$auth;S:$ssid;P:$password;;';
    return NdefRecord(
      typeNameFormat: TypeNameFormat.media,
      type: Uint8List.fromList(utf8.encode('application/vnd.wfa.wsc')),
      identifier: Uint8List(0),
      payload: Uint8List.fromList(utf8.encode(config)),
    );
  }

  NdefRecord _phoneRecord(String number) => _urlRecord('tel:$number');

  NdefRecord _smsRecord(String number, String body) {
    final uri = 'sms:$number${body.isNotEmpty ? '?body=${Uri.encodeComponent(body)}' : ''}';
    return _urlRecord(uri);
  }

  NdefRecord _emailRecord(String email, String subject, String body) {
    final uri = 'mailto:$email?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
    return _urlRecord(uri);
  }

  NdefRecord _locationRecord(double lat, double lng) => _urlRecord('geo:$lat,$lng');

  NdefRecord _launchAppRecord(String packageName) {
    return NdefRecord(
      typeNameFormat: TypeNameFormat.external,
      type: Uint8List.fromList(utf8.encode('android.com:pkg')),
      identifier: Uint8List(0),
      payload: Uint8List.fromList(utf8.encode(packageName)),
    );
  }

  // ── UPI Records ────────────────────────────────────────────────────────

  /// Build NDEF records for UPI payment.
  /// Uses our custom MIME type with payload: UPI:<package>:<upi_uri>
  /// Native handler detects UPI: prefix and launches ACTION_VIEW intent
  /// with the URI + package — directly opens the payment page.
  List<NdefRecord> _upiRecords({
    required String upiId,
    required String name,
    required _UpiApp app,
    String? amount,
    String? note,
  }) {
    // Build standard UPI URI
    final parts = <String>['pa=$upiId', 'pn=${_upiEncode(name)}', 'cu=INR'];
    if (amount != null && amount.isNotEmpty) {
      parts.add('am=$amount');
    }
    if (note != null && note.isNotEmpty) {
      parts.add('tn=${_upiEncode(note)}');
    }
    final upiUri = 'upi://pay?${parts.join('&')}';

    // Payload: UPI:<package_name>:<upi_uri>
    final payload = 'UPI:${app.packageName}:$upiUri';

    // Write as our custom MIME type so our native handler catches it
    const mimeType = 'application/com.nfccontrol.nfcc';
    final record = NdefRecord(
      typeNameFormat: TypeNameFormat.media,
      type: Uint8List.fromList(utf8.encode(mimeType)),
      identifier: Uint8List(0),
      payload: Uint8List.fromList(utf8.encode(payload)),
    );

    return [record];
  }

  /// Minimal URL encoding for UPI — only encode spaces and &
  String _upiEncode(String value) {
    return value.replaceAll('&', '%26').replaceAll(' ', '%20');
  }

  // ── Dialogs ───────────────────────────────────────────────────────────

  Future<void> _writeUrl() async {
    final url = await _inputDialog('Write URL', 'https://example.com',
        icon: Icons.language_rounded, color: AppColors.accentCyan);
    if (url == null || url.isEmpty) return;
    await _writeNdef([_urlRecord(url)], 'URL');
  }

  Future<void> _writeText() async {
    final text = await _inputDialog('Write Text', 'Enter any text...',
        icon: Icons.text_fields_rounded, color: AppColors.accentBlue);
    if (text == null || text.isEmpty) return;
    await _writeNdef([_textRecord(text)], 'Text');
  }

  Future<void> _writePhone() async {
    final num = await _inputDialog('Phone Number', '+91 98765 43210',
        icon: Icons.phone_rounded, color: AppColors.success);
    if (num == null || num.isEmpty) return;
    await _writeNdef([_phoneRecord(num)], 'Phone');
  }

  Future<void> _writeSms() async {
    final num = await _inputDialog('SMS - Number', '+91 98765 43210',
        icon: Icons.sms_rounded, color: AppColors.accentPurple);
    if (num == null || num.isEmpty) return;
    final body = await _inputDialog('SMS - Message', 'Hello!',
        icon: Icons.sms_rounded, color: AppColors.accentPurple);
    await _writeNdef([_smsRecord(num, body ?? '')], 'SMS');
  }

  Future<void> _writeEmail() async {
    final email = await _inputDialog('Email Address', 'name@example.com',
        icon: Icons.email_rounded, color: AppColors.accentOrange);
    if (email == null || email.isEmpty) return;
    final subject = await _inputDialog('Subject', 'Hello',
        icon: Icons.email_rounded, color: AppColors.accentOrange);
    final body = await _inputDialog('Body', 'Message...',
        icon: Icons.email_rounded, color: AppColors.accentOrange);
    await _writeNdef([_emailRecord(email, subject ?? '', body ?? '')], 'Email');
  }

  Future<void> _writeWifi() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        final ssidCtrl = TextEditingController();
        final passCtrl = TextEditingController();
        String auth = 'WPA';
        return StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppColors.surfaceHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.wifi_rounded, color: AppColors.accentBlue, size: 20),
            SizedBox(width: 8),
            Text('WiFi Network', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(ssidCtrl, 'Network name (SSID)'),
              const SizedBox(height: 10),
              _dialogField(passCtrl, 'Password', obscure: true),
              const SizedBox(height: 10),
              Row(children: [
                const Text('Security: ', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(width: 8),
                ...['WPA', 'WEP', 'Open'].map((t) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t, style: TextStyle(fontSize: 12, color: auth == t ? Colors.black : AppColors.textSecondary)),
                    selected: auth == t,
                    selectedColor: AppColors.accentBlue,
                    backgroundColor: AppColors.surfaceElevated,
                    onSelected: (_) => setSt(() => auth = t),
                  ),
                )),
              ]),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
            TextButton(onPressed: () => Navigator.pop(ctx, {'ssid': ssidCtrl.text, 'pass': passCtrl.text, 'auth': auth}),
                child: const Text('Write', style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.w600))),
          ],
        ));
      },
    );
    if (result == null || (result['ssid'] ?? '').isEmpty) return;
    await _writeNdef([_wifiRecord(result['ssid']!, result['pass']!, result['auth']!)], 'WiFi');
  }

  Future<void> _writeLocation() async {
    hapticLight();
    final mode = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationModeSheet(),
    );
    if (mode == null) return;

    LatLng? picked;
    if (mode == 'map') {
      picked = await Navigator.push<LatLng>(context,
          MaterialPageRoute(builder: (_) => const _MapPickerScreen()));
    } else {
      final lat = await _inputDialog('Latitude', '18.5204',
          icon: Icons.location_on_rounded, color: AppColors.error);
      if (lat == null || lat.isEmpty) return;
      final lng = await _inputDialog('Longitude', '73.8567',
          icon: Icons.location_on_rounded, color: AppColors.error);
      if (lng == null || lng.isEmpty) return;
      final la = double.tryParse(lat);
      final lo = double.tryParse(lng);
      if (la == null || lo == null) {
        _setStatus('Invalid coordinates');
        return;
      }
      picked = LatLng(la, lo);
    }

    if (picked == null) return;
    await _writeNdef(
        [_locationRecord(picked.latitude, picked.longitude)], 'Location');
  }

  Future<void> _writeLaunchApp() async {
    hapticLight();
    final pkg = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _InstalledAppsSheet(),
    );
    if (pkg == null || pkg.isEmpty) return;
    await _writeNdef([_launchAppRecord(pkg)], 'App Launch');
  }


  // ── UPI Payment Dialog ────────────────────────────────────────────────

  Future<void> _writeUpiPayment() async {
    hapticLight();
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _UpiPaymentSheet(),
    );
    if (result == null) return;
    final upiId = result['upiId'] ?? '';
    final name = result['name'] ?? '';
    final appId = result['app'] ?? 'phonepe';
    if (upiId.isEmpty || name.isEmpty) return;

    final app = _upiApps.firstWhere((a) => a.id == appId, orElse: () => _upiApps[0]);

    await _writeNdef(
      _upiRecords(
        upiId: upiId,
        name: name,
        app: app,
        amount: result['amount'],
        note: result['note'],
      ),
      'UPI Payment (${app.name})',
    );
  }

  Future<String?> _inputDialog(String title, String hint,
      {required IconData icon, required Color color}) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ]),
        content: _dialogField(ctrl, hint),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text('OK', style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String hint, {bool obscure = false}) {
    return TextField(
      controller: ctrl, autofocus: true, obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.textTertiary),
        filled: true, fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildContent(context),
        if (_statusMsg != null || _busy)
          _NfcStatusOverlay(
            message: _statusMsg ?? '',
            busy: _busy,
            onCancel: _cancel,
            onDismiss: () {
              if (mounted) {
                setState(() { _statusMsg = null; _busy = false; });
              }
            },
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      children: [
        // ── Read & Manage ──
        _CategoryCard(
          title: 'READ & MANAGE',
          children: [
            _WriterTile(
              icon: Icons.contactless_rounded,
              color: AppColors.nfcGlow,
              title: 'Read Tag',
              subtitle: 'Scan tag info, UID, data',
              onTap: _busy ? null : _readTag,
            ),
            _WriterTile(
              icon: Icons.delete_sweep_rounded,
              color: AppColors.error,
              title: 'Erase Tag',
              subtitle: 'Clear all data from tag',
              onTap: _busy ? null : _formatTag,
              isLast: true,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Payments (NEW — prominent placement) ──
        _CategoryCard(
          title: 'PAYMENTS',
          accentColor: AppColors.upiGreen,
          children: [
            _WriterTile(
              icon: Icons.currency_rupee_rounded,
              color: AppColors.upiGreen,
              title: 'UPI Payment',
              subtitle: 'PhonePe, GPay, Paytm — tap to pay',
              onTap: _busy ? null : _writeUpiPayment,
              badge: 'NEW',
              isLast: true,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Business Card ──
        _CategoryCard(
          title: 'BUSINESS CARD',
          accentColor: AppColors.accentCyan,
          children: [
            _WriterTile(
              icon: Icons.badge_rounded,
              color: AppColors.accentCyan,
              title: 'Digital Business Card',
              subtitle: 'Design a card — anyone can tap & view',
              onTap: () {
                hapticLight();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Digital Business Card — coming soon'),
                  backgroundColor: AppColors.surfaceHigh,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                ));
              },
              badge: 'SOON',
              isLast: true,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Messages ──
        _CategoryCard(
          title: 'MESSAGES',
          children: [
            _WriterTile(
              icon: Icons.language_rounded,
              color: AppColors.accentCyan,
              title: 'URL / Website',
              subtitle: 'Open a link when tapped',
              onTap: _busy ? null : _writeUrl,
            ),
            _WriterTile(
              icon: Icons.text_fields_rounded,
              color: AppColors.accentBlue,
              title: 'Plain Text',
              subtitle: 'Store any text on the tag',
              onTap: _busy ? null : _writeText,
            ),
            _WriterTile(
              icon: Icons.phone_rounded,
              color: AppColors.success,
              title: 'Phone Number',
              subtitle: 'Dial a number when tapped',
              onTap: _busy ? null : _writePhone,
            ),
            _WriterTile(
              icon: Icons.sms_rounded,
              color: AppColors.accentPurple,
              title: 'SMS Message',
              subtitle: 'Pre-fill an SMS',
              onTap: _busy ? null : _writeSms,
            ),
            _WriterTile(
              icon: Icons.email_rounded,
              color: AppColors.accentOrange,
              title: 'Email',
              subtitle: 'Compose an email',
              onTap: _busy ? null : _writeEmail,
              isLast: true,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Connectivity ──
        _CategoryCard(
          title: 'CONNECTIVITY',
          children: [
            _WriterTile(
              icon: Icons.wifi_rounded,
              color: AppColors.accentBlue,
              title: 'WiFi Network',
              subtitle: 'Connect to WiFi (SSID + password)',
              onTap: _busy ? null : _writeWifi,
              isLast: true,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ── Utilities ──
        _CategoryCard(
          title: 'UTILITIES',
          children: [
            _WriterTile(
              icon: Icons.location_on_rounded,
              color: AppColors.error,
              title: 'Location',
              subtitle: 'Open map coordinates',
              onTap: _busy ? null : _writeLocation,
            ),
            _WriterTile(
              icon: Icons.launch_rounded,
              color: AppColors.success,
              title: 'Launch App',
              subtitle: 'Open an app by package name',
              onTap: _busy ? null : _writeLaunchApp,
              isLast: true,
            ),
          ],
        ),

      ],
    );
  }
}

// ── Full-screen NFC status overlay ──────────────────────────────────────────

class _NfcStatusOverlay extends StatefulWidget {
  final String message;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  const _NfcStatusOverlay({
    required this.message,
    required this.busy,
    required this.onCancel,
    required this.onDismiss,
  });

  @override
  State<_NfcStatusOverlay> createState() => _NfcStatusOverlayState();
}

class _NfcStatusOverlayState extends State<_NfcStatusOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = !widget.busy && widget.message.toLowerCase().contains('success');
    final isError = !widget.busy &&
        (widget.message.toLowerCase().contains('fail') ||
            widget.message.toLowerCase().contains('error') ||
            widget.message.toLowerCase().contains('not available'));
    final accent = isSuccess
        ? AppColors.success
        : isError
            ? AppColors.error
            : AppColors.nfcGlow;

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fadeCtrl,
        child: Stack(
          children: [
            // Backdrop
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.88),
              ),
            ),
            // Centered modal card
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.25),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.15),
                        blurRadius: 40,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulse icon
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (widget.busy) ...[
                              _Pulse(controller: _pulseCtrl, color: accent, delay: 0.0),
                              _Pulse(controller: _pulseCtrl, color: accent, delay: 0.33),
                              _Pulse(controller: _pulseCtrl, color: accent, delay: 0.66),
                            ],
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    accent,
                                    accent.withValues(alpha: 0.7),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.5),
                                    blurRadius: 24,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isSuccess
                                    ? Icons.check_rounded
                                    : isError
                                        ? Icons.error_outline_rounded
                                        : Icons.nfc_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        widget.busy
                            ? 'Scanning…'
                            : isSuccess
                                ? 'Success'
                                : isError
                                    ? 'Failed'
                                    : 'Status',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (widget.busy)
                        _OverlayButton(
                          label: 'Cancel',
                          color: AppColors.error,
                          onTap: widget.onCancel,
                        )
                      else
                        _OverlayButton(
                          label: 'Done',
                          color: AppColors.accentWhite,
                          textColor: Colors.black,
                          onTap: widget.onDismiss,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pulse extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  final double delay;
  const _Pulse({required this.controller, required this.color, required this.delay});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final v = (controller.value + delay) % 1.0;
        final size = 80.0 + (60.0 * v);
        final opacity = (1.0 - v).clamp(0.0, 1.0) * 0.6;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: opacity),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

class _OverlayButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  final VoidCallback onTap;
  const _OverlayButton({
    required this.label,
    required this.color,
    this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFilled = textColor != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isFilled ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: isFilled ? 1.0 : 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor ?? color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

// ── Category Card ────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final String title;
  final Color? accentColor;
  final List<Widget> children;

  const _CategoryCard({
    required this.title,
    this.accentColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: accentColor != null
            ? Border.all(color: accentColor!.withValues(alpha: 0.2), width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                if (accentColor != null) ...[
                  Container(
                    width: 3, height: 12,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(title,
                    style: TextStyle(
                        color: accentColor ?? AppColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

// ── Writer Tile ──────────────────────────────────────────────────────────────

class _WriterTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? badge;
  final bool isLast;

  const _WriterTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              hapticLight();
              onTap?.call();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Accent dot
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500)),
                            if (badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(badge!,
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
                                color: AppColors.textTertiary, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 66),
            child: Container(height: 0.5, color: AppColors.divider),
          ),
      ],
    );
  }
}

// ── UPI App Model ────────────────────────────────────────────────────────────

class _UpiApp {
  final String id;
  final String name;
  final String packageName;
  final Color color;
  final IconData icon;

  const _UpiApp({
    required this.id,
    required this.name,
    required this.packageName,
    required this.color,
    required this.icon,
  });
}

const _upiApps = <_UpiApp>[
  _UpiApp(
    id: 'phonepe',
    name: 'PhonePe',
    packageName: 'com.phonepe.app',
    color: Color(0xFF5F259F),
    icon: Icons.currency_rupee_rounded,
  ),
  _UpiApp(
    id: 'gpay',
    name: 'Google Pay',
    packageName: 'com.google.android.apps.nbu.paisa.user',
    color: Color(0xFF4285F4),
    icon: Icons.g_mobiledata_rounded,
  ),
  _UpiApp(
    id: 'paytm',
    name: 'Paytm',
    packageName: 'net.one97.paytm',
    color: Color(0xFF00BAF2),
    icon: Icons.account_balance_wallet_rounded,
  ),
  _UpiApp(
    id: 'bhim',
    name: 'BHIM',
    packageName: 'in.org.npci.upiapp',
    color: Color(0xFF00796B),
    icon: Icons.account_balance_rounded,
  ),
  _UpiApp(
    id: 'amazonpay',
    name: 'Amazon Pay',
    packageName: 'in.amazon.mShop.android.shopping',
    color: Color(0xFFFF9900),
    icon: Icons.shopping_bag_rounded,
  ),
];

// ── UPI Payment Sheet ────────────────────────────────────────────────────────

class _UpiPaymentSheet extends StatefulWidget {
  const _UpiPaymentSheet();

  @override
  State<_UpiPaymentSheet> createState() => _UpiPaymentSheetState();
}

class _UpiPaymentSheetState extends State<_UpiPaymentSheet> {
  final _upiIdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _selectedAppId = 'phonepe'; // default
  bool _showPreview = false;

  @override
  void dispose() {
    _upiIdCtrl.dispose();
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  _UpiApp get _selectedApp =>
      _upiApps.firstWhere((a) => a.id == _selectedAppId);

  void _submit() {
    final upiId = _upiIdCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (upiId.isEmpty || name.isEmpty) return;
    Navigator.pop(context, {
      'upiId': upiId,
      'name': name,
      'amount': _amountCtrl.text.trim(),
      'note': _noteCtrl.text.trim(),
      'app': _selectedAppId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _upiIdCtrl.text.trim().isNotEmpty &&
        _nameCtrl.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLit,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientUpi,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.currency_rupee_rounded,
                          size: 22, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('UPI Payment',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 2),
                          Text('Write UPI payment link to NFC tag',
                              style: TextStyle(
                                  color: AppColors.textTertiary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── App Selection ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Open with',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _upiApps.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (ctx, i) {
                          final app = _upiApps[i];
                          final selected = app.id == _selectedAppId;
                          return GestureDetector(
                            onTap: () {
                              hapticLight();
                              setState(() => _selectedAppId = app.id);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              width: 80,
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? LinearGradient(
                                        colors: [
                                          app.color.withValues(alpha: 0.18),
                                          app.color.withValues(alpha: 0.06),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: selected ? null : AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? app.color.withValues(alpha: 0.55)
                                      : AppColors.border,
                                  width: selected ? 1.5 : 1,
                                ),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: app.color.withValues(alpha: 0.25),
                                          blurRadius: 14,
                                          spreadRadius: -2,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedScale(
                                    duration: const Duration(milliseconds: 220),
                                    scale: selected ? 1.05 : 1.0,
                                    child: _UpiBrandLogo(
                                      id: app.id,
                                      size: 38,
                                      dim: !selected,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(app.name,
                                      style: TextStyle(
                                          color: selected
                                              ? AppColors.textPrimary
                                              : AppColors.textSecondary,
                                          fontSize: 10,
                                          letterSpacing: 0.1,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Info banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedApp.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _selectedApp.color.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 14, color: _selectedApp.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tag will open ${_selectedApp.name} directly for payment',
                          style: TextStyle(
                              color: _selectedApp.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Form fields
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _UpiField(
                      controller: _upiIdCtrl,
                      label: 'UPI ID',
                      hint: 'name@upi, name@ybl, 9876543210@paytm',
                      icon: Icons.account_balance_wallet_rounded,
                      required: true,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _UpiField(
                      controller: _nameCtrl,
                      label: 'Payee Name',
                      hint: 'Shop name or person',
                      icon: Icons.person_rounded,
                      required: true,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _UpiField(
                      controller: _amountCtrl,
                      label: 'Amount (optional)',
                      hint: 'Leave empty for user to enter',
                      icon: Icons.currency_rupee_rounded,
                      keyboardType: TextInputType.number,
                      prefix: '\u20b9 ',
                    ),
                    const SizedBox(height: 12),
                    _UpiField(
                      controller: _noteCtrl,
                      label: 'Note (optional)',
                      hint: 'Payment for...',
                      icon: Icons.note_rounded,
                    ),
                  ],
                ),
              ),

              // Preview
              if (_upiIdCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: () => setState(() => _showPreview = !_showPreview),
                    child: Row(
                      children: [
                        Icon(
                          _showPreview ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 14, color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Text(_showPreview ? 'Hide preview' : 'Show UPI link preview',
                            style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                if (_showPreview) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _buildPreviewUri(),
                            style: const TextStyle(
                                color: AppColors.accentCyan,
                                fontSize: 11,
                                fontFamily: 'monospace',
                                height: 1.5),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'AAR: ${_selectedApp.packageName}',
                            style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                                fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 20),

              // Write button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: canSubmit ? _submit : null,
                    icon: const Icon(Icons.nfc_rounded, size: 20),
                    label: Text('Write to Tag via ${_selectedApp.name}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _selectedApp.color,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.surfaceElevated,
                      disabledForegroundColor: AppColors.textTertiary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildPreviewUri() {
    final parts = <String>['pa=${_upiIdCtrl.text.trim()}'];
    if (_nameCtrl.text.trim().isNotEmpty) {
      parts.add('pn=${_nameCtrl.text.trim()}');
    }
    if (_amountCtrl.text.trim().isNotEmpty) {
      parts.add('am=${_amountCtrl.text.trim()}');
    }
    if (_noteCtrl.text.trim().isNotEmpty) {
      parts.add('tn=${_noteCtrl.text.trim()}');
    }
    parts.add('cu=INR');
    return 'upi://pay?${parts.join('&')}';
  }
}

// ── UPI Form Field ───────────────────────────────────────────────────────────

class _UpiField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool required;
  final TextInputType? keyboardType;
  final String? prefix;
  final ValueChanged<String>? onChanged;

  const _UpiField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.required = false,
    this.keyboardType,
    this.prefix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            if (required)
              const Text(' *',
                  style: TextStyle(color: AppColors.error, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
            prefixIcon: Icon(icon, size: 18, color: AppColors.textTertiary),
            prefixIconConstraints: const BoxConstraints(minWidth: 44),
            prefixText: prefix,
            prefixStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            filled: true,
            fillColor: AppColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.upiGreen, width: 1),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}

// ── UPI Brand Logos ────────────────────────────────────────────────────────

class _UpiBrandLogo extends StatelessWidget {
  final String id;
  final double size;
  final bool dim;
  const _UpiBrandLogo({required this.id, this.size = 38, this.dim = false});

  @override
  Widget build(BuildContext context) {
    Widget logo;
    switch (id) {
      case 'phonepe':
        logo = _brandTile(
          gradient: const LinearGradient(
            colors: [Color(0xFF6F2DA8), Color(0xFF4A1D7A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Text(
            'pe',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
              height: 1.0,
            ),
          ),
        );
        break;
      case 'gpay':
        logo = _brandTile(
          color: Colors.white,
          child: ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [
                Color(0xFF4285F4),
                Color(0xFFEA4335),
                Color(0xFFFBBC04),
                Color(0xFF34A853),
              ],
              stops: [0.0, 0.35, 0.65, 1.0],
            ).createShader(b),
            child: Text(
              'G',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.68,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ),
        );
        break;
      case 'paytm':
        logo = _brandTile(
          gradient: const LinearGradient(
            colors: [Color(0xFF00BAF2), Color(0xFF002E6E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.08),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Paytm',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
        );
        break;
      case 'bhim':
        logo = _brandTile(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9933), Color(0xFFE96125)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Text(
            '₹',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.58,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        );
        break;
      case 'amazonpay':
        logo = _brandTile(
          color: const Color(0xFF232F3E),
          child: Padding(
            padding: EdgeInsets.only(bottom: size * 0.08),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'a',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.48,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: size * 0.03),
                  child: CustomPaint(
                    size: Size(size * 0.48, size * 0.08),
                    painter: _SmilePainter(color: const Color(0xFFFF9900)),
                  ),
                ),
              ],
            ),
          ),
        );
        break;
      default:
        logo = _brandTile(
          color: AppColors.surfaceElevated,
          child: Icon(Icons.currency_rupee_rounded,
              size: size * 0.5, color: AppColors.textSecondary),
        );
    }

    if (dim) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.4, 0.4, 0.4, 0, 0,
          0.4, 0.4, 0.4, 0, 0,
          0.4, 0.4, 0.4, 0, 0,
          0,   0,   0,   1, 0,
        ]),
        child: Opacity(opacity: 0.75, child: logo),
      );
    }
    return logo;
  }

  Widget _brandTile({
    Color? color,
    Gradient? gradient,
    required Widget child,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SmilePainter extends CustomPainter {
  final Color color;
  _SmilePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(size.width / 2, size.height * 2.4, size.width, 0);
    canvas.drawPath(path, paint);
    // Arrow tip
    final tip = Paint()..color = color;
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.6), size.height * 0.7, tip);
  }

  @override
  bool shouldRepaint(_SmilePainter oldDelegate) => oldDelegate.color != color;
}

// ── Location mode sheet ────────────────────────────────────────────────────

class _LocationModeSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLit,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Choose how',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            _modeTile(context,
                icon: Icons.map_rounded,
                color: AppColors.accentBlue,
                title: 'Pick on Map',
                subtitle: 'Tap a point on the world map',
                value: 'map'),
            _modeTile(context,
                icon: Icons.keyboard_rounded,
                color: AppColors.textSecondary,
                title: 'Enter manually',
                subtitle: 'Type latitude and longitude',
                value: 'manual',
                isLast: true),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Widget _modeTile(BuildContext context,
      {required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      required String value,
      bool isLast = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          hapticLight();
          Navigator.pop(context, value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textTertiary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Map picker ─────────────────────────────────────────────────────────────

class _MapPickerScreen extends StatefulWidget {
  const _MapPickerScreen();

  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<_MapPickerScreen> {
  final _mapController = MapController();
  LatLng _picked = const LatLng(18.5204, 73.8567); // Pune default

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Pick Location',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _picked,
              initialZoom: 13,
              onTap: (tap, point) {
                hapticLight();
                setState(() => _picked = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nfccontrol.nfcc',
              ),
              MarkerLayer(markers: [
                Marker(
                  point: _picked,
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on_rounded,
                      size: 44, color: AppColors.error),
                ),
              ]),
            ],
          ),
          // Coordinate pill (top)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.my_location_rounded,
                      size: 16, color: AppColors.accentBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_picked.latitude.toStringAsFixed(5)}, ${_picked.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom confirm bar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('Tap anywhere on the map to move the pin',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 12)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        hapticMedium();
                        Navigator.pop(context, _picked);
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Use this location',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentWhite,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Installed apps picker sheet ────────────────────────────────────────────

class _InstalledAppsSheet extends StatefulWidget {
  const _InstalledAppsSheet();

  @override
  State<_InstalledAppsSheet> createState() => _InstalledAppsSheetState();
}

class _InstalledAppsSheetState extends State<_InstalledAppsSheet> {
  List<AppInfo> _apps = [];
  List<AppInfo> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final apps = await InstalledApps.getInstalledApps(true, true, '');
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() { _apps = apps; _filtered = apps; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String q) {
    setState(() {
      _filtered = _apps
          .where((a) => a.name.toLowerCase().contains(q.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLit,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Choose an app',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _filter,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search apps...',
                  hintStyle: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.textTertiary),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentBlue, strokeWidth: 2.5))
                  : _filtered.isEmpty
                      ? const Center(
                          child: Text('No apps found',
                              style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 13)))
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.only(bottom: 20),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final app = _filtered[i];
                            return InkWell(
                              onTap: () {
                                hapticLight();
                                Navigator.pop(context, app.packageName);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    app.icon != null
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Image.memory(app.icon!,
                                                width: 40, height: 40))
                                        : Container(
                                            width: 40, height: 40,
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceElevated,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                                Icons.android_rounded,
                                                color: AppColors.success,
                                                size: 22)),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(app.name,
                                              style: const TextStyle(
                                                  color:
                                                      AppColors.textPrimary,
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w500)),
                                          const SizedBox(height: 2),
                                          Text(app.packageName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color:
                                                      AppColors.textTertiary,
                                                  fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded,
                                        size: 18,
                                        color: AppColors.textTertiary),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
