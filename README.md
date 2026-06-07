# hopp — Android APK (WebView + GitHub Actions)

Bu repo, `hoppapk.netlify.app` adresini açan bir Flutter WebView uygulamasıdır.
Kamera (yüz doğrulama) ve konum (harita) izinleri açıktır. APK'yı GitHub bulutta
otomatik derler — kendi bilgisayarına Flutter/Android kurmana gerek yok.

## APK nasıl alınır
1. Bu dosyaları GitHub'da yeni bir repoya yükle (aşağıdaki "Yükleme" adımları).
2. GitHub otomatik derlemeyi başlatır (**Actions** sekmesi).
3. Yeşil ✓ olunca → **Actions → en üstteki çalışma → Artifacts → `hopp-apk`** indir.
4. ZIP içinden `app-release.apk` çıkar, telefona kur.

## Dosya yapısı
```
.github/workflows/build.yml      → otomatik APK derleme
pubspec.yaml                     → bağımlılıklar
lib/main.dart                    → WebView + izinler
android/app/src/main/AndroidManifest.xml → izinler (derleme sırasında flutter create üretir)
```

> Not: `android/` klasörünü GitHub Actions `flutter create .` ile otomatik üretir,
> sonra workflow AndroidManifest'e izinleri ekler. Sen sadece kök dosyaları koy.
