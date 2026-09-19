# Leafy

Android / iOS / Web Flutter 앱. 기존 React 웹은 상위 디렉터리에 유지합니다.
배포나 스토어 등록은 수행하지 않습니다.

## 실행

```powershell
cd flutter_app
.\tool\flutter35.cmd pub get
.\tool\flutter35.cmd run -d chrome
```

이 작업에서 설치한 로컬 SDK는 `../.tools/flutter/bin/flutter.bat`입니다.
현재 윈도우 워크스페이스의 SDK는 맥 환경과 같은 `Flutter 3.35.0 / Dart 3.9.0 / DevTools 2.48.0`으로 고정했습니다.
revision은 `b896255557`, engine은 `6cd51c08a88e7bbe848a762c20ad3ecb8b063c0e`입니다.
`tool/flutter35.cmd`는 `APPDATA`와 `PUB_CACHE`를 `../.tools` 아래로 돌려서 전역 Flutter나 사용자 폴더 설정과 섞이지 않게 실행합니다.
SDK와 캐시는 Git에서 제외합니다.
Firebase 설정 없이도 게스트 단어장, 퀴즈, CSV 기능을 실행할 수 있습니다.

## 구현된 기능

- Leafy 브랜드와 반응형 화면, 단어 추가/수정/삭제, 검색/카테고리/즐겨찾기
- 플래시카드, 뜻 선택, 영어 입력, 뜻 입력, 예문 빈칸 퀴즈
- 복습 간격 1/3/7/14/30/60일 및 오답 10분, 오답노트, 최근 7일 기록
- 미국/영국 기기 영어 음성 선택, 답을 확인한 후 자동 듣기 ON/OFF
- 웹 CSV 형식 가져오기/내보내기, 확장 뜻/예문/유의어 필드 보존
- 이메일 회원가입/로그인, Google 로그인, 개인 및 그룹 단어장
- 게스트는 SharedPreferences의 로컬 JSON, 로그인은 Firestore. 자동 병합하지 않음
- 모바일 AdMob 배너 및 UMP 동의/개인정보 설정, 웹 광고 연결 영역 분리

기존 웹의 모든 세부 UX를 복제한 완성 출시판은 아닙니다. 웹의 의미별 단계 학습,
오타 허용·동의어 채점, 오답 누적 완료 판정, 고급 카테고리 편집은 추가 이식 대상입니다.
현재 뜻 입력은 등록된 뜻 중 하나와 정확히 일치할 때 정답입니다.
기기 TTS는 설치된 영어 음성에 따라 품질이 달라집니다. 비공식 사전 CDN은 사용하지 않습니다.

## Firebase 연결

1. 기존 웹과 **같은 Firebase 프로젝트**에 Android, iOS, Web 앱을 등록합니다.
2. `com.example.leafy`는 임시 식별자입니다. 출시용 applicationId/bundle ID를 정한 다음 등록하세요.
3. `config/example.json`을 `config/android.json`, `ios.json`, `web.json`으로 복사하고 각 플랫폼 앱 설정을 입력합니다.
4. 이메일/비밀번호 및 Google 로그인 제공자를 활성화합니다. 웹 허용 도메인, Android SHA 지문,
   iOS Google reversed client ID URL scheme 등 제공자별 네이티브 설정도 완료하세요.
   모바일 Google 로그인은 JSON의 `GOOGLE_WEB_CLIENT_ID`(웹 OAuth 클라이언트 ID),
   iOS의 `GOOGLE_IOS_CLIENT_ID`를 사용합니다. `google_sign_in` 공식 설정에 맞춰 등록하세요.
5. `flutter run --dart-define-from-file=config/android.json`처럼 실행합니다.
6. 상위 `firestore.rules`를 Firebase 프로젝트에 배포해야 접근 제어가 적용됩니다.

설정값은 클라이언트 앱 식별값이며 보안 경계는 Firestore 규칙입니다. 서비스 계정 비밀키를 앱에 넣지 마세요.
FlutterFire CLI를 사용할 경우 `flutterfire configure`로 동일 프로젝트를 고르고,
생성된 `DefaultFirebaseOptions.currentPlatform`을 `main.dart`의 초기화에 연결할 수도 있습니다.

Firebase 초기화 오류 시 조용히 게스트 저장으로 바꾸지 않습니다. 오류 화면을 표시합니다.
계정/그룹 전환 시 기존 화면 데이터를 비우고 로딩을 마칠 때까지 편집을 막습니다.
로그인 데이터와 게스트 데이터는 자동 복사하지 않으며 필요한 이동은 CSV로 명시적으로 수행합니다.
SharedPreferences는 소규모 단어장의 초기 저장 구현입니다. 큰 오프라인 단어장을 다룰 때는
`NotebookRepository`의 로컬 구현을 SQLite/IndexedDB로 교체할 수 있습니다.

## 데이터 호환과 비용

- 웹과 동일한 `users/{uid}/words/{id}`, `users/{uid}/reviews/{id}` 및
  `groups/{groupId}/words/{id}`, `groups/{groupId}/reviews/{id}` 경로를 사용합니다.
- 단어 필드와 밀리초 시간, `version: 1`을 유지합니다. 확장 배열은 손실 없이 보존합니다.
- 전체 단어장을 매 입력마다 저장하지 않습니다. 단어 저장/삭제는 해당 문서만 쓰며,
  퀴즈 정답 확인은 단어 1건 + 복습 1건을 하나의 배치로 저장합니다.
- 실시간 리스너 없이 로그인/범위 전환/명시적 새로고침 시 읽습니다.
- 단어는 200개 페이지로 읽고, 복습 기록은 최근 2,000건만 표시합니다.
- 현재 웹 스키마에 맞춰 그룹 단어장의 숙련도와 기록도 그룹 공유입니다.
  개인별 그룹 학습 진도는 별도 스키마 변경을 통해 웹과 함께 적용해야 합니다.
- 그룹 소유자가 멤버 UID를 추가한 뒤 그룹 ID를 공유합니다. ID만 안다고 가입되지는 않습니다.
- 상위 React 웹의 기존 전체 저장 방식은 별도 개선 대상입니다. 이 Flutter 쓰기 최적화가
  기존 웹에 자동 적용되는 것은 아닙니다.
- CSV 가져오기는 행별 저장입니다. 중간 실패 시 완료 건수를 표시하며 이미 저장된 행은 유지됩니다.

## 광고

앱은 AdMob, 웹은 AdSense 등 웹 전용 광고를 사용합니다. AdMob Flutter 플러그인은 웹을 지원하지 않습니다.
기본값은 광고 OFF이며, Android/iOS 네이티브 설정에는 공식 테스트 App ID를 넣습니다.

```powershell
.\tool\flutter35.cmd run --dart-define=ADS_ENABLED=true
```

테스트 배너만 사용됩니다. 실제 배포 시:

1. AdMob에서 Android/iOS 앱과 배너 광고 단위를 각각 만듭니다.
2. Android `AndroidManifest.xml`의 `com.google.android.gms.ads.APPLICATION_ID`,
   iOS `Info.plist`의 `GADApplicationIdentifier`를 실제 **앱 ID(~)**로 바꿉니다.
3. JSON의 `ADMOB_ANDROID_BANNER_ID`, `ADMOB_IOS_BANNER_ID`는 실제 **광고 단위 ID(/)**로 설정합니다.
4. `ADS_ENABLED=true`, `ADS_PRODUCTION=true`를 설정합니다.
5. AdMob Privacy & messaging에서 메시지를 구성하고 기기에서 동의 흐름을 확인합니다.
6. iOS SKAdNetwork 항목, 개인정보처리방침, 스토어 개인정보 표기,
   추적을 사용하는 경우 ATT 등 실제 SDK/광고 구성에 필요한 출시 설정을 완료합니다.

광고 요청 전에 UMP `canRequestAds()`를 확인합니다. 필요한 경우 설정 화면에 동의 변경 버튼이 나옵니다.
광고는 퀴즈 화면 밖에만 표시하며 로딩 실패 시 학습 기능에 영향을 주지 않습니다.
전면 광고/보상형 광고는 아직 구현하지 않았습니다.
Flutter Web의 `web/index.html`에는 호스트 HTML 광고 연결 위치를 두며,
실제 웹 광고는 승인된 게시자 ID와 CMP 설정 후 연결합니다. 현재 광고 요청을 보내지 않습니다.

## 검증 및 출시 준비

```powershell
.\tool\flutter35.cmd analyze
.\tool\flutter35.cmd test
.\tool\flutter35.cmd build web
```

Android 빌드는 Android SDK/JDK, iOS 빌드는 macOS/Xcode 및 서명이 필요합니다.
실계정 Firebase/AdMob 통합은 앱 등록과 설정값을 받은 뒤 실기기에서 검증해야 합니다.
앱 삭제 시 게스트 데이터가 사라질 수 있으므로 CSV 내보내기를 제공합니다.

공식 문서: [Firebase](https://firebase.google.com/docs/flutter/setup),
[AdMob](https://developers.google.com/admob/flutter/quick-start),
[광고 동의](https://developers.google.com/admob/flutter/privacy).
