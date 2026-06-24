import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart' as loc;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// â”€â”€ AdMob reklam birimi ID'leri â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// ÅU AN GOOGLE TEST ID'LERÄ° KULLANILIYOR (gerÃ§ek para kazandÄ±rmaz, gÃ¼venle
// test edebilirsin). AdMob hesabÄ±nÄ± aÃ§Ä±p kendi reklam birimlerini
// oluÅŸturunca AÅAÄIDAKÄ° 3 deÄŸeri kendi ID'lerinle deÄŸiÅŸtir + AndroidManifest
// iÃ§indeki APPLICATION_ID'yi de gÃ¼ncelle (build.yml'de).
const String _kBannerAdUnit = 'ca-app-pub-3092168413729990/5053559271';   // hopp banner
const String _kRewardedAdUnit = 'ca-app-pub-3092168413729990/2876998241'; // hopp odullu

// â”€â”€ Uygulama sÃ¼rÃ¼mÃ¼ (gÃ¼ncelleme bannerÄ± iÃ§in) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Play Store'a YENÄ° bir AAB yÃ¼klediÄŸinde bu sayÄ±yÄ± +1 artÄ±r VE web tarafÄ±ndaki
// config.jsx â†’ latestAppBuild deÄŸerini AYNI sayÄ± yap. BÃ¶ylece eski sÃ¼rÃ¼mdeki
// kullanÄ±cÄ±lar uygulamayÄ± aÃ§Ä±nca "Yeni sÃ¼rÃ¼m hazÄ±r" bannerÄ± gÃ¶rÃ¼r.
const int kAppBuild = 1;

// Telefona GERÃ‡EK bildirim dÃ¼ÅŸÃ¼rmek iÃ§in yerel bildirim eklentisi.
// Web katmanÄ± (notifications.jsx) kÃ¶prÃ¼den 'hoppNotify' Ã§aÄŸÄ±rÄ±r â†’ burada OS
// bildirimi gÃ¶sterilir. Android WebView Web Notification API'sini desteklemediÄŸi
// iÃ§in bu kÃ¶prÃ¼ ÅŸarttÄ±r.
final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'hopp_default', 'hopp Bildirimleri',
  description: 'Mesaj, beÄŸeni ve yol kesiÅŸme bildirimleri',
  importance: Importance.high,
);

Future<void> _initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notif.initialize(const InitializationSettings(android: android));
  await _notif
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);
}

int _notifId = 0;
Future<void> _showNotif(String title, String body) async {
  await _notif.show(
    _notifId++, title, body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'hopp_default', 'hopp Bildirimleri',
        channelDescription: 'Mesaj, beÄŸeni ve yol kesiÅŸme bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize(); // AdMob baÅŸlat
  // tam ekran (edge-to-edge) + ÅŸeffaf durum Ã§ubuÄŸu â†’ Ã¼stte siyah ÅŸerit kalmaz
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D1220),
  ));
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
  BannerAd? _banner;
  bool _bannerReady = false;
  RewardedAd? _rewarded;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _loadBanner();
    _loadRewarded();
  }

  @override
  void dispose() {
    _banner?.dispose();
    _rewarded?.dispose();
    super.dispose();
  }

  // â”€â”€ Banner (alt menÃ¼nÃ¼n altÄ±nda, ekran dibinde) â”€â”€
  void _loadBanner() {
    _banner = BannerAd(
      adUnitId: _kBannerAdUnit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) { if (mounted) setState(() => _bannerReady = true); },
        onAdFailedToLoad: (ad, err) { ad.dispose(); _banner = null; },
      ),
    )..load();
  }

  // â”€â”€ Ã–dÃ¼llÃ¼ reklam (kilitli profili aÃ§mak iÃ§in) â”€â”€
  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: _kRewardedAdUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) { _rewarded = ad; },
        onAdFailedToLoad: (err) { _rewarded = null; },
      ),
    );
  }

  // ReklamÄ± gÃ¶ster; Ã¶dÃ¼l kazanÄ±lÄ±rsa true dÃ¶ner (web bunu bekler)
  Future<bool> _showRewarded() async {
    final ad = _rewarded;
    if (ad == null) { _loadRewarded(); return false; }
    final completer = Completer<bool>();
    bool earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose(); _rewarded = null; _loadRewarded();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose(); _rewarded = null; _loadRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (_, __) { earned = true; });
    return completer.future;
  }

  Future<void> _bootstrap() async {
    await _initNotifications();
    // aÃ§Ä±lÄ±ÅŸta kamera/mikrofon/konum + (Android 13+) bildirim izinlerini iste
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.notification,
    ].request();
    // GPS kapalÄ±ysa, Google'Ä±n "Konum DoÄŸruluÄŸu / EtkinleÅŸtir" sistem
    // penceresini aÃ§ â€” kullanÄ±cÄ± tek dokunuÅŸla konumu aÃ§ar (manuel
    // kontrol panelinden aÃ§maya gerek kalmaz).
    await _ensureLocationService();
  }

  Future<void> _ensureLocationService() async {
    try {
      final location = loc.Location();
      bool enabled = await location.serviceEnabled();
      if (!enabled) {
        // â†’ "Devam etmek iÃ§in cihazÄ±nÄ±zÄ±n Konum DoÄŸruluÄŸu'nu kullanmasÄ± gerekiyor"
        enabled = await location.requestService();
      }
    } catch (_) {
      // konum servisi sorgulanamazsa sessizce geÃ§ (uygulama yine de aÃ§Ä±lÄ±r)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1220),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: InAppWebView(
        initialUrlRequest:
            URLRequest(url: WebUri('https://hopptrapp.netlify.app/')),
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
        // UygulamanÄ±n sÃ¼rÃ¼mÃ¼nÃ¼ web'e bildir (gÃ¼ncelleme bannerÄ± iÃ§in).
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: "window.hoppNativeBuild = $kAppBuild;",
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        onWebViewCreated: (controller) {
          // â”€â”€ Web â†” Native kÃ¶prÃ¼sÃ¼ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          // 1) Web 'hoppNotify' Ã§aÄŸÄ±rÄ±nca telefona gerÃ§ek bildirim dÃ¼ÅŸÃ¼r
          controller.addJavaScriptHandler(
            handlerName: 'hoppNotify',
            callback: (args) async {
              final title = args.isNotEmpty ? args[0].toString() : 'hopp';
              final body = args.length > 1 ? args[1].toString() : '';
              await _showNotif(title, body);
              return true;
            },
          );
          // 2) Web 'hoppRequestNotif' â†’ Android 13+ bildirim iznini iste
          controller.addJavaScriptHandler(
            handlerName: 'hoppRequestNotif',
            callback: (args) async {
              final st = await Permission.notification.request();
              return st.isGranted;
            },
          );
          // 3) Web 'hoppRequestLocation' â†’ konum iznini iste
          controller.addJavaScriptHandler(
            handlerName: 'hoppRequestLocation',
            callback: (args) async {
              final st = await Permission.location.request();
              // izinden sonra GPS kapalÄ±ysa sistem "Konum DoÄŸruluÄŸu" penceresini aÃ§
              if (st.isGranted) await _ensureLocationService();
              return st.isGranted;
            },
          );
          // 4) Web 'hoppOpenExternal' â†’ bilet linkini SÄ°STEM TARAYICISINDA aÃ§
          //    (uygulama aÃ§Ä±k kalÄ±r; kullanÄ±cÄ± geri dÃ¶nebilir)
          controller.addJavaScriptHandler(
            handlerName: 'hoppOpenExternal',
            callback: (args) async {
              if (args.isEmpty) return false;
              final url = args[0].toString();
              try {
                await launchUrl(WebUri(url), mode: LaunchMode.externalApplication);
                return true;
              } catch (e) {
                return false;
              }
            },
          );
          // 5) Web 'hoppShowRewarded' â†’ Ã¶dÃ¼llÃ¼ reklam gÃ¶ster; Ã¶dÃ¼l kazanÄ±lÄ±rsa
          //    true dÃ¶ner â†’ web kilitli profili aÃ§ar
          controller.addJavaScriptHandler(
            handlerName: 'hoppShowRewarded',
            callback: (args) async {
              return await _showRewarded();
            },
          );
        },
        // WebView iÃ§inde yeni pencere/sekme aÃ§ma isteÄŸi (target=_blank) â†’
        // SÄ°STEM TARAYICISINDA aÃ§, bÃ¶ylece ana uygulama aÃ§Ä±k kalÄ±r.
        onCreateWindow: (controller, createWindowAction) async {
          final req = createWindowAction.request;
          if (req.url != null) {
            try { await launchUrl(req.url!, mode: LaunchMode.externalApplication); } catch (e) {}
          }
          return false;
        },
        // Kamera / mikrofon istekleri â†’ otomatik izin ver
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
            // â”€â”€ Banner: alt menÃ¼nÃ¼n altÄ±nda, ekran dibinde â”€â”€
            if (_bannerReady && _banner != null)
              Container(
                color: const Color(0xFF0D1220),
                width: _banner!.size.width.toDouble(),
                height: _banner!.size.height.toDouble(),
                child: AdWidget(ad: _banner!),
              ),
          ],
        ),
      ),
    );
  }
}import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart' as loc;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// â”€â”€ AdMob reklam birimi ID'leri â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// ÅU AN GOOGLE TEST ID'LERÄ° KULLANILIYOR (gerÃ§ek para kazandÄ±rmaz, gÃ¼venle
// test edebilirsin). AdMob hesabÄ±nÄ± aÃ§Ä±p kendi reklam birimlerini
// oluÅŸturunca AÅAÄIDAKÄ° 3 deÄŸeri kendi ID'lerinle deÄŸiÅŸtir + AndroidManifest
// iÃ§indeki APPLICATION_ID'yi de gÃ¼ncelle (build.yml'de).
const String _kBannerAdUnit = 'ca-app-pub-3092168413729990/5053559271';   // hopp banner
const String _kRewardedAdUnit = 'ca-app-pub-3092168413729990/2876998241'; // hopp odullu

// â”€â”€ Uygulama sÃ¼rÃ¼mÃ¼ (gÃ¼ncelleme bannerÄ± iÃ§in) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Play Store'a YENÄ° bir AAB yÃ¼klediÄŸinde bu sayÄ±yÄ± +1 artÄ±r VE web tarafÄ±ndaki
// config.jsx â†’ latestAppBuild deÄŸerini AYNI sayÄ± yap. BÃ¶ylece eski sÃ¼rÃ¼mdeki
// kullanÄ±cÄ±lar uygulamayÄ± aÃ§Ä±nca "Yeni sÃ¼rÃ¼m hazÄ±r" bannerÄ± gÃ¶rÃ¼r.
const int kAppBuild = 1;

// Telefona GERÃ‡EK bildirim dÃ¼ÅŸÃ¼rmek iÃ§in yerel bildirim eklentisi.
// Web katmanÄ± (notifications.jsx) kÃ¶prÃ¼den 'hoppNotify' Ã§aÄŸÄ±rÄ±r â†’ burada OS
// bildirimi gÃ¶sterilir. Android WebView Web Notification API'sini desteklemediÄŸi
// iÃ§in bu kÃ¶prÃ¼ ÅŸarttÄ±r.
final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'hopp_default', 'hopp Bildirimleri',
  description: 'Mesaj, beÄŸeni ve yol kesiÅŸme bildirimleri',
  importance: Importance.high,
);

Future<void> _initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notif.initialize(const InitializationSettings(android: android));
  await _notif
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);
}

int _notifId = 0;
Future<void> _showNotif(String title, String body) async {
  await _notif.show(
    _notifId++, title, body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'hopp_default', 'hopp Bildirimleri',
        channelDescription: 'Mesaj, beÄŸeni ve yol kesiÅŸme bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize(); // AdMob baÅŸlat
  // tam ekran (edge-to-edge) + ÅŸeffaf durum Ã§ubuÄŸu â†’ Ã¼stte siyah ÅŸerit kalmaz
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D1220),
  ));
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
  BannerAd? _banner;
  bool _bannerReady = false;
  RewardedAd? _rewarded;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _loadBanner();
    _loadRewarded();
  }

  @override
  void dispose() {
    _banner?.dispose();
    _rewarded?.dispose();
    super.dispose();
  }

  // â”€â”€ Banner (alt menÃ¼nÃ¼n altÄ±nda, ekran dibinde) â”€â”€
  void _loadBanner() {
    _banner = BannerAd(
      adUnitId: _kBannerAdUnit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) { if (mounted) setState(() => _bannerReady = true); },
        onAdFailedToLoad: (ad, err) { ad.dispose(); _banner = null; },
      ),
    )..load();
  }

  // â”€â”€ Ã–dÃ¼llÃ¼ reklam (kilitli profili aÃ§mak iÃ§in) â”€â”€
  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: _kRewardedAdUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) { _rewarded = ad; },
        onAdFailedToLoad: (err) { _rewarded = null; },
      ),
    );
  }

  // ReklamÄ± gÃ¶ster; Ã¶dÃ¼l kazanÄ±lÄ±rsa true dÃ¶ner (web bunu bekler)
  Future<bool> _showRewarded() async {
    final ad = _rewarded;
    if (ad == null) { _loadRewarded(); return false; }
    final completer = Completer<bool>();
    bool earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose(); _rewarded = null; _loadRewarded();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose(); _rewarded = null; _loadRewarded();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (_, __) { earned = true; });
    return completer.future;
  }

  Future<void> _bootstrap() async {
    await _initNotifications();
    // aÃ§Ä±lÄ±ÅŸta kamera/mikrofon/konum + (Android 13+) bildirim izinlerini iste
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.notification,
    ].request();
    // GPS kapalÄ±ysa, Google'Ä±n "Konum DoÄŸruluÄŸu / EtkinleÅŸtir" sistem
    // penceresini aÃ§ â€” kullanÄ±cÄ± tek dokunuÅŸla konumu aÃ§ar (manuel
    // kontrol panelinden aÃ§maya gerek kalmaz).
    await _ensureLocationService();
  }

  Future<void> _ensureLocationService() async {
    try {
      final location = loc.Location();
      bool enabled = await location.serviceEnabled();
      if (!enabled) {
        // â†’ "Devam etmek iÃ§in cihazÄ±nÄ±zÄ±n Konum DoÄŸruluÄŸu'nu kullanmasÄ± gerekiyor"
        enabled = await location.requestService();
      }
    } catch (_) {
      // konum servisi sorgulanamazsa sessizce geÃ§ (uygulama yine de aÃ§Ä±lÄ±r)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1220),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: InAppWebView(
        initialUrlRequest:
            URLRequest(url: WebUri('https://hopptrapp.netlify.app/')),
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
        // UygulamanÄ±n sÃ¼rÃ¼mÃ¼nÃ¼ web'e bildir (gÃ¼ncelleme bannerÄ± iÃ§in).
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: "window.hoppNativeBuild = $kAppBuild;",
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        onWebViewCreated: (controller) {
          // â”€â”€ Web â†” Native kÃ¶prÃ¼sÃ¼ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          // 1) Web 'hoppNotify' Ã§aÄŸÄ±rÄ±nca telefona gerÃ§ek bildirim dÃ¼ÅŸÃ¼r
          controller.addJavaScriptHandler(
            handlerName: 'hoppNotify',
            callback: (args) async {
              final title = args.isNotEmpty ? args[0].toString() : 'hopp';
              final body = args.length > 1 ? args[1].toString() : '';
              await _showNotif(title, body);
              return true;
            },
          );
          // 2) Web 'hoppRequestNotif' â†’ Android 13+ bildirim iznini iste
          controller.addJavaScriptHandler(
            handlerName: 'hoppRequestNotif',
            callback: (args) async {
              final st = await Permission.notification.request();
              return st.isGranted;
            },
          );
          // 3) Web 'hoppRequestLocation' â†’ konum iznini iste
          controller.addJavaScriptHandler(
            handlerName: 'hoppRequestLocation',
            callback: (args) async {
              final st = await Permission.location.request();
              // izinden sonra GPS kapalÄ±ysa sistem "Konum DoÄŸruluÄŸu" penceresini aÃ§
              if (st.isGranted) await _ensureLocationService();
              return st.isGranted;
            },
          );
          // 4) Web 'hoppOpenExternal' â†’ bilet linkini SÄ°STEM TARAYICISINDA aÃ§
          //    (uygulama aÃ§Ä±k kalÄ±r; kullanÄ±cÄ± geri dÃ¶nebilir)
          controller.addJavaScriptHandler(
            handlerName: 'hoppOpenExternal',
            callback: (args) async {
              if (args.isEmpty) return false;
              final url = args[0].toString();
              try {
                await launchUrl(WebUri(url), mode: LaunchMode.externalApplication);
                return true;
              } catch (e) {
                return false;
              }
            },
          );
          // 5) Web 'hoppShowRewarded' â†’ Ã¶dÃ¼llÃ¼ reklam gÃ¶ster; Ã¶dÃ¼l kazanÄ±lÄ±rsa
          //    true dÃ¶ner â†’ web kilitli profili aÃ§ar
          controller.addJavaScriptHandler(
            handlerName: 'hoppShowRewarded',
            callback: (args) async {
              return await _showRewarded();
            },
          );
        },
        // WebView iÃ§inde yeni pencere/sekme aÃ§ma isteÄŸi (target=_blank) â†’
        // SÄ°STEM TARAYICISINDA aÃ§, bÃ¶ylece ana uygulama aÃ§Ä±k kalÄ±r.
        onCreateWindow: (controller, createWindowAction) async {
          final req = createWindowAction.request;
          if (req.url != null) {
            try { await launchUrl(req.url!, mode: LaunchMode.externalApplication); } catch (e) {}
          }
          return false;
        },
        // Kamera / mikrofon istekleri â†’ otomatik izin ver
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
            // â”€â”€ Banner: alt menÃ¼nÃ¼n altÄ±nda, ekran dibinde â”€â”€
            if (_bannerReady && _banner != null)
              Container(
                color: const Color(0xFF0D1220),
                width: _banner!.size.width.toDouble(),
                height: _banner!.size.height.toDouble(),
                child: AdWidget(ad: _banner!),
              ),
          ],
        ),
      ),
    );
  }
}
