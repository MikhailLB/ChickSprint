# Chick Sprint

Chick Sprint is a casual memory arcade game for Android built with Flutter.
The player helps a little chick cross a grid of cells: memorize the layout of
coins, safe tiles and fire, then tap adjacent tiles to guide the chick to the
nest without stepping on fire.

- Bundle: `com.chicksprint.chicksprintgame`
- Version: 1.0.0 (build 1)

## Features

- Memorize-and-solve grid gameplay with growing difficulty
- Coins, streaks, best-score persistence
- Adaptive launcher icon and Android 12+ SplashScreen
- Built-in WebView pages for Privacy Policy and Support
- Portrait-locked game with landscape-aware loading screen

## Build

```bash
flutter pub get
flutter build apk --release
flutter build appbundle --release
```

Release signing uses `android/key.properties` and the keystore under
`android/keystore/`, both of which are excluded from source control.

## Links

- Privacy Policy: https://chicksprint.com/privacy-policy.html
- Support: https://chicksprint.com/support.html
