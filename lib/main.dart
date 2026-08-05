import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart' as loc;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:record/record.dart';

// ── AdMob reklam birimi ID'leri ───────────────────────────────────────────
// ŞU AN GOOGLE TEST ID'LERİ KULLANILIYOR (gerçek para kazandırmaz, güvenle
// test edebilirsin). AdMob hesabını açıp kendi reklam birimlerini
// oluşturunca AŞAĞIDAKİ 3 değeri kendi ID'lerinle değiştir + AndroidManifest
// içindeki APPLICATION_ID'yi de güncelle (build.yml'de).
const String _kBannerAdUnit = 'ca-app-pub-3092168413729990/5053559271';   // hopp banner
const String _kRewardedAdUnit = 'ca-app-pub-3092168413729990/2876998241'; // hopp odullu

// ── Uygulama sürümü (güncelleme bannerı için) ───────────────────────────────
// Play Store'a YENİ bir AAB yüklediğinde bu sayıyı +1 artır VE web tarafındaki
// config.jsx → latestAppBuild değerini AYNI sayı yap. Böylece eski sürümdeki
// kullanıcılar uygulamayı açınca "Yeni sürüm hazır" bannerı görür.
const int kAppBuild = 1;
// Ayarlar ekranında gösterilen sürüm adı. Play Console'a yüklediğin sürüm
// adıyla AYNI yap (pubspec.yaml version ile de eşleşsin).
const String kAppVersionName = '1.0.0';

// Telefona GERÇEK bildirim düşürmek için yerel bildirim eklentisi.
// Web katmanı (notifications.jsx) köprüden 'hoppNotify' çağırır → burada OS
// bildirimi gösterilir. Android WebView Web Notification API'sini desteklemediği
// için bu köprü şarttır.
final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'hopp_default', 'hopp Bildirimleri',
  description: 'Mesaj, beğeni ve yol kesişme bildirimleri',
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
        channelDescription: 'Mesaj, beğeni ve yol kesişme bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize(); // AdMob başlat
  // tam ekran (edge-to-edge) + şeffaf durum çubuğu → üstte siyah şerit kalmaz
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFF6F3EE),
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
  // uygulamanın kendi native ses kaydedicisi (WebView'e bağlı değil)
  final AudioRecorder _rec = AudioRecorder();
  String? _recPath;

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

  // ── Banner (alt menünün altında, ekran dibinde) ──
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

  // ── Ödüllü reklam (kilitli profili açmak için) ──
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

  // Reklamı göster; ödül kazanılırsa true döner (web bunu bekler)
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
    // açılışta kamera/mikrofon/konum + (Android 13+) bildirim izinlerini iste
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.notification,
    ].request();
    // GPS kapalıysa, Google'ın "Konum Doğruluğu / Etkinleştir" sistem
    // penceresini aç — kullanıcı tek dokunuşla konumu açar (manuel
    // kontrol panelinden açmaya gerek kalmaz).
    await _ensureLocationService();
  }

  Future<void> _ensureLocationService() async {
    try {
      final location = loc.Location();
      bool enabled = await location.serviceEnabled();
      if (!enabled) {
        // → "Devam etmek için cihazınızın Konum Doğruluğu'nu kullanması gerekiyor"
        enabled = await location.requestService();
      }
    } catch (_) {
      // konum servisi sorgulanamazsa sessizce geç (uygulama yine de açılır)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: InAppWebView(
        initialUrlRequest:
            URLRequest(url: WebUri('https://hopp.destek-hopptr.workers.dev/')),
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
        // Uygulamanın sürümünü web'e bildir (güncelleme bannerı için).
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: "window.hoppNativeBuild = $kAppBuild; window.hoppNativeVersion = '$kAppVersionName';",
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        onWebViewCreated: (controller) {
          // ── Web ↔ Native köprüsü ──────────────────────────────────────
          // 1) Web 'hoppNotify' çağırınca telefona gerçek bildirim düşür
          controller.addJavaScriptHandler(
            handlerName: 'hoppNotify',
            callback: (args) async {
              final title = args.isNotEmpty ? args[0].toString() : 'hopp';
              final body = args.length > 1 ? args[1].toString() : '';
              await _showNotif(title, body);
              return true;
            },
          );
          // 2) Web 'hoppRequestNotif' → Android 13+ bildirim iznini iste
          controller.addJavaScriptHandler(
            handlerName: 'hoppRequestNotif',
            callback: (args) async {
              final st = await Permission.notification.request();
              return st.isGranted;
            },
          );
          // 3) Web 'hoppRequestLocation' → konum iznini iste
          controller.addJavaScriptHandler(
            handlerName: 'hoppRequestLocation',
            callback: (args) async {
              final st = await Permission.location.request();
              // izinden sonra GPS kapalıysa sistem "Konum Doğruluğu" penceresini aç
              if (st.isGranted) await _ensureLocationService();
              return st.isGranted;
            },
          );
          // 4) Web 'hoppOpenExternal' → bilet linkini SİSTEM TARAYICISINDA aç
          //    (uygulama açık kalır; kullanıcı geri dönebilir)
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
          // 5) Web 'hoppShowRewarded' → ödüllü reklam göster; ödül kazanılırsa
          //    true döner → web kilitli profili açar
          controller.addJavaScriptHandler(
            handlerName: 'hoppShowRewarded',
            callback: (args) async {
              return await _showRewarded();
            },
          );
          // 6) UYGULAMANIN KENDİ MİKROFONU — native ses kaydı (record eklentisi).
          //    WebView getUserMedia'ya HİÇ bağlı değil; telefon donanımıyla
          //    doğrudan kaydeder. hoppRecordStart → true, hoppRecordStop →
          //    'data:audio/mp4;base64,...' döner (web bunu mesaj olarak gönderir).
          controller.addJavaScriptHandler(
            handlerName: 'hoppRecordStart',
            callback: (args) async {
              try {
                if (!await _rec.hasPermission()) {
                  final st = await Permission.microphone.request();
                  if (!st.isGranted) return false;
                  if (!await _rec.hasPermission()) return false;
                }
                final dir = Directory.systemTemp.path;
                _recPath = '$dir/hopp_${DateTime.now().millisecondsSinceEpoch}.m4a';
                await _rec.start(
                  const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000, sampleRate: 44100),
                  path: _recPath!,
                );
                return true;
              } catch (e) {
                return false;
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'hoppRecordStop',
            callback: (args) async {
              try {
                final path = await _rec.stop();
                final p = path ?? _recPath;
                if (p == null) return null;
                final f = File(p);
                if (!await f.exists()) return null;
                final bytes = await f.readAsBytes();
                try { await f.delete(); } catch (_) {}
                if (bytes.isEmpty) return null;
                return 'data:audio/mp4;base64,${base64Encode(bytes)}';
              } catch (e) {
                return null;
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'hoppRecordCancel',
            callback: (args) async {
              try { await _rec.stop(); } catch (_) {}
              try { if (_recPath != null) await File(_recPath!).delete(); } catch (_) {}
              return true;
            },
          );
        },
        // WebView içinde yeni pencere/sekme açma isteği (target=_blank) →
        // SİSTEM TARAYICISINDA aç, böylece ana uygulama açık kalır.
        onCreateWindow: (controller, createWindowAction) async {
          final req = createWindowAction.request;
          if (req.url != null) {
            try { await launchUrl(req.url!, mode: LaunchMode.externalApplication); } catch (e) {}
          }
          return false;
        },
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
            // ── Banner: alt menünün altında, ekran dibinde (krem zemin) ──
            if (_bannerReady && _banner != null)
              Container(
                color: const Color(0xFFF6F3EE),
                alignment: Alignment.center,
                width: double.infinity,
                height: _banner!.size.height.toDouble(),
                child: AdWidget(ad: _banner!),
              ),
          ],
        ),
      ),
    );
  }
}

