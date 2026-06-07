import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HoppApp());
}

class HoppApp extends StatelessWidget {
  const HoppApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebScreen(),
    );
  }
}

class WebScreen extends StatefulWidget {
  const WebScreen({super.key});
  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  @override
  void initState() {
    super.initState();
    _askPermissions();
  }

  Future<void> _askPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1220),
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest:
              URLRequest(url: WebUri('https://hoppapk.netlify.app/')),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            iframeAllow: "camera; microphone",
            iframeAllowFullscreen: true,
            geolocationEnabled: true,
            useHybridComposition: true,
            supportZoom: false,
          ),
          // Kamera / mikrofon istekleri → otomatik izin ver
          onPermissionRequest: (controller, request) async {
            return PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.GRANT,
            );
          },
          // Konum izni (harita)
          onGeolocationPermissionsShowPrompt: (controller, origin) async {
            return GeolocationPermissionShowPromptResponse(
              origin: origin,
              allow: true,
              retain: true,
            );
          },
        ),
      ),
    );
  }
}
