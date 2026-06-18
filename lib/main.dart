import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => NotificationService(),
      child: const NotimeApp(),
    ),
  );
}

class NotimeApp extends StatelessWidget {
  const NotimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notime',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
      ),
      home: const HomeScreen(),
    );
  }
}

// ─── QR Scanner Screen ────────────────────────────────────────────────────────

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D27),
        title: const Text('Scan QR Code'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_scanned) return;
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.startsWith('ws://')) {
                  _scanned = true;
                  Navigator.pop(context, value);
                  return;
                }
              }
            },
          ),
          // Scan frame overlay
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF6366F1), width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: const Text(
              'Point at the QR code on\nthe Notime dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Home Screen ──────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController(text: 'ws://');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationService>().requestPermission();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _openQrScanner() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result != null && mounted) {
      _urlController.text = result;
      _connect();
    }
  }

  Future<void> _connect() async {
    final svc = context.read<NotificationService>();
    final url = _urlController.text.trim();
    if (url.isEmpty || url == 'ws://') return;

    final ok = await svc.connect(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot connect — check URL and Wi-Fi'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationService>(
      builder: (context, svc, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF1A1D27),
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.notifications, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('Notime', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            actions: [
              if (svc.connected)
                TextButton.icon(
                  onPressed: svc.disconnect,
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text('Disconnect'),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _ConnectionCard(
                controller: _urlController,
                connected: svc.connected,
                status: svc.status,
                serverUrl: svc.serverUrl,
                onConnect: _connect,
                onScanQr: _openQrScanner,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (svc.notifications.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${svc.notifications.length}',
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (svc.notifications.isEmpty)
                _EmptyState(connected: svc.connected)
              else
                ...svc.notifications.map((n) => _NotifCard(item: n)),
            ],
          ),
        );
      },
    );
  }
}

// ─── Connection Card ──────────────────────────────────────────────────────────

class _ConnectionCard extends StatelessWidget {
  final TextEditingController controller;
  final bool connected;
  final String status;
  final String? serverUrl;
  final VoidCallback onConnect;
  final VoidCallback onScanQr;

  const _ConnectionCard({
    required this.controller,
    required this.connected,
    required this.status,
    required this.serverUrl,
    required this.onConnect,
    required this.onScanQr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected ? const Color(0xFF22C55E) : const Color(0xFF2E3350),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: connected ? const Color(0xFF22C55E) : const Color(0xFF64748B),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: connected ? const Color(0xFF22C55E) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          if (connected && serverUrl != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: serverUrl!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('URL copied')),
                );
              },
              child: Text(
                serverUrl!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF818CF8),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          if (!connected) ...[
            const SizedBox(height: 16),

            // QR Scan button (primary action)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onScanQr,
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: const Text('Scan QR Code from Dashboard'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6366F1),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: Divider(color: Color(0xFF2E3350))),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or type URL', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                ),
                Expanded(child: Divider(color: Color(0xFF2E3350))),
              ],
            ),
            const SizedBox(height: 12),

            const Text(
              'WebSocket URL',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 14, color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'ws://192.168.1.x:3000',
                hintStyle: const TextStyle(color: Color(0xFF475569)),
                filled: true,
                fillColor: const Color(0xFF22263A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E3350)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF2E3350)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF6366F1)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onSubmitted: (_) => onConnect(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onConnect,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool connected;

  const _EmptyState({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E3350)),
      ),
      child: Column(
        children: [
          const Text('🔔', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 16),
          Text(
            connected ? 'Waiting for notifications...' : 'Not connected',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            connected
                ? 'Go to the web dashboard and send a notification'
                : 'Scan the QR code on the dashboard to connect',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

// ─── Notification Card ────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  final NotificationItem item;

  const _NotifCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final time =
        '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NotificationDetailScreen(item: item)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D27),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2E3350)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.imageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  item.imageUrl!,
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22263A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.notifications, color: Color(0xFF6366F1), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.body,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Notification Detail Screen ───────────────────────────────────────────────

class NotificationDetailScreen extends StatelessWidget {
  final NotificationItem item;

  const NotificationDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final ts = item.timestamp;
    final date =
        '${ts.day}/${ts.month}/${ts.year}  ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D27),
        title: const Text('Detail'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.imageUrl != null)
              Image.network(
                item.imageUrl!,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 220,
                    color: const Color(0xFF1A1D27),
                    child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                    ),
                  );
                },
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    date,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF2E3350)),
                  const SizedBox(height: 16),
                  Text(
                    item.body,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFFCBD5E1),
                      height: 1.7,
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
}
