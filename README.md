# TheosDylib — لوحة تشخيص عائمة (FPS / CPU / Network / Touch / Console)

مكتبة Dylib بلغة Objective-C++ تعرض لوحة تشخيص فوق **تطبيق تملكه أو مصرّح لك باختباره**.
لا تعدّل منطق اللعبة ولا الذاكرة ولا النتائج ولا بيانات اللاعبين ولا الخوادم، ولا تتجاوز أي حماية أو Anti-Cheat.
تستخدم واجهات Apple العامة فقط.

## هيكل المشروع
```
TheosDylib/
├── Makefile              (اختياري) بناء Theos، غير مطلوب


├── build.sh              بناء مستقل (بدون Theos) → build/TheosDylib.dylib
├── .github/workflows/   بناء تلقائي على GitHub بدون Mac
├── Headers/              واجهات الأصناف (TDSettings, TDPerformance, ...)
├── Sources/
│   ├── Main.mm           الإقلاع، حارس الانهيار، تشغيل/إيقاف الميزات حسب الإعدادات
│   ├── FloatingMenu.mm   كل الواجهة: النافذة، الزر العائم، HUD، اللوحة، الشريط الجانبي والصفحات
│   ├── Performance.mm    FPS + CPU + الذاكرة
│   ├── NetworkMonitor.mm حالة الشبكة + زمن الاستجابة (HTTP RTT) + IP المحلي
│   ├── TouchVisualizer.mm إظهار نقاط اللمس
│   ├── DebugConsole.mm   سجل تشخيصي (500 سطر) مع نسخ ومسح
│   └── Settings.mm       حفظ/استعادة الإعدادات + Safe Mode التلقائي
└── Resources/Assets/     (فارغ حالياً، للأيقونات مستقبلاً)
```

## البناء
المتطلبات: Theos مثبت (`$THEOS` معرّف) + Xcode/iOS SDK 14 أو أحدث.

```bash
# 1) عدّل TheosDylib.plist: ضع Bundle ID لتطبيق الاختبار الخاص بك
# 2) بناء الـ dylib فقط
make                 # arm64 + arm64e
make ARCHS=arm64     # arm64 فقط (مطلوب غالباً للتثبيت بدون جيلبريك)
# الناتج: .theos/obj/debug/TheosDylib.dylib

# 3) بناء حزمة deb (جهاز بجيلبريك)
make package         # للـ rootless أزل التعليق عن THEOS_PACKAGE_SCHEME في Makefile
```

## التثبيت على جهاز اختبار
- **جهاز بجيلبريك:** `make package install THEOS_DEVICE_IP=<ip>` أو انقل ملف deb من `packages/` وثبّته عبر Filza/dpkg ثم أعد تشغيل التطبيق.
- **بدون جيلبريك (تطبيقك أنت):** ابنِ بـ `make ARCHS=arm64` ثم احقن `TheosDylib.dylib` في نسخة IPA من تطبيقك عبر أداة توقيع تدعم حقن dylib (مثل Sideloadly) أو أضفه كـ embedded library في مشروع Xcode.

## خطوات اختبار كل ميزة
1. **القائمة العائمة:** افتح التطبيق، سيظهر زر دائري. اسحبه (يلتصق بالحافة). اضغطه لفتح اللوحة، اسحب الترويسة لتحريكها، زر ✕ للإغلاق.
2. **Custom UI / الثيم:** صفحة Design: بدّل System/Dark/Light، غيّر لون التمييز والشفافية، ثم أعد تشغيل التطبيق وتأكد أن الإعدادات بقيت.
3. **FPS Monitor:** فعّله من Dashboard؛ يظهر HUD أعلى الشاشة. مرّر قائمة أو انيميشن وراقب الرقم (يقارب 60/120 عند السلاسة).
4. **Performance Monitor:** فعّله وافتح صفحة Performance؛ نفّذ عملاً ثقيلاً في التطبيق وراقب ارتفاع CPU وMEM.
5. **Network Diagnostics:** فعّله، افتح Network: حالة الاتصال، النوع، IP، وزمن الاستجابة. اضغط Ping now. فعّل وضع الطيران لترى Offline وارتفاع Failed.
6. **Device Information:** افتح صفحة Device وقارن القيم بإعدادات الجهاز.
7. **Touch Visualizer:** فعّله، أغلق اللوحة، المس الشاشة بإصبع ثم عدة أصابع؛ تظهر دوائر بإحداثياتها، والتطبيق يستجيب للمس بشكل طبيعي.
8. **Debug Console:** صفحة Console، اضغط Test فتظهر 4 مستويات؛ جرّب Copy ثم Clear.
9. **Settings Manager:** غيّر عدة إعدادات، أغلق التطبيق نهائياً وافتحه، وتأكد أنها محفوظة؛ زر Reset يعيد الافتراضي.
10. **Safe Mode:** فعّله من Dashboard: تتوقف كل الميزات وتختفي اللوحة ويصير الزر باهتاً؛ اضغطه لإيقاف Safe Mode. تلقائياً: بعد 3 إغلاقات/انهيارات متتالية خلال 15 ثانية من التشغيل يُعطَّل الـ UI لتشغيلة واحدة ثم يعود طبيعياً.

## أخطاء البناء الشائعة
| الخطأ | الحل |
|---|---|
| `THEOS not set` / `No rule to make target` | `export THEOS=~/theos` ثم أعد المحاولة |
| `framework not found Network` أو `UIWindowScene unavailable` | استخدم SDK 14+ (حمّله من theos-sdks) وتأكد من `TARGET := iphone:clang:latest:14.0` |
| `unsupported architecture arm64e` | استخدم Xcode حديثاً أو ابنِ بـ `make ARCHS=arm64` |
| لا تظهر اللوحة | تأكد من Bundle ID في `TheosDylib.plist`، وراجع سجل `[TheosDylib]` في Console.app |
| `ld: library not found` | تحقق من وجود الأطر في `TheosDylib_FRAMEWORKS` وأن SDK صحيح |

## حدود تقنية (بصراحة)
- **FPS:** يقيس وتيرة الـ run loop الرئيسي (CADisplayLink)، وليس بالضرورة معدل رسم Metal/OpenGL في خيط آخر.
- **Ping:** لا يمكن إرسال ICMP من تطبيق iOS؛ القياس هو زمن طلب HTTP HEAD إلى عنوان قابل للتغيير (افتراضياً Apple)، ولا يمس خوادم اللعبة.
- **CPU/MEM:** للعملية الحالية فقط، ولا يمكن قراءة عمليات التطبيقات الأخرى.
- **SSID/اسم الشبكة** يحتاج صلاحية خاصة (Entitlement)، لذا لم يُضمَّن؛ البديل: نوع الاتصال + IP المحلي.
