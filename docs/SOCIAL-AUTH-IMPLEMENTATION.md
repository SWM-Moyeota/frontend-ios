# Google·Apple 로그인과 계정 연결

2026-11-14 구현. 운영 배포·PR 생성·스토어 제출은 수행하지 않았다.

## 구현

- 앱 계층 `NativeSocialSignIn`이 GoogleSignIn 10.1.0과 AuthenticationServices를 실행하고 `NativeSocialAuthentication`으로 UI에 주입한다. Google iOS ID와 웹 서버 ID를 함께 지정한다.
- Apple 로그인 전 공개 challenge, 연결 전 인증된 LINK challenge를 요청하고 서버 nonce를 수정 없이 SDK에 전달한다. 이름이 없으면 기존 실명 입력을 사용한다. 비공개 릴레이 이메일을 정상 이메일로 취급하며 앱이 이메일을 만들어 내지 않는다.
- 로그인 성공은 기존 `SessionManager`·FCM 등록 경로를 사용한다. `SIGNUP_REQUIRED`는 세션을 만들지 않고 메모리의 `SignupDraft`에 대기표만 보관한다. 기존 가입 화면의 프로필·문자 인증·매너 서약을 재사용하고 아이디·비밀번호·이메일 입력을 숨긴다.
- 마이페이지의 로그인 수단 관리에서 등록된 번호로 문자 재인증 후 Google·Apple을 추가한다. 발송 성공과 429 `USER202` 양쪽에서 발송 버튼을 잠그고 남은 초를 보여 준다(`Retry-After`가 없으면 60초). 모르는 provider 항목은 건너뛰고 `hasPassword`와 아는 수단만 읽는다. 연결 성공 후 수단 목록을 새로 읽는다. 자동 병합·연결 삭제 기능은 제공하지 않는다.
- 탈퇴 진입 시 `hasPassword`를 읽어 비밀번호 입력 또는 본문 없는 요청을 선택한다. 조회 실패를 소셜 전용 회원으로 추측하지 않고 재시도를 제공한다. 기존 앱에는 비밀번호 변경 메뉴가 없다.
- SDK 취소는 오류 없이 종료한다. Google SDK 저장 자격증명은 매 인증 시도 전후 `signOut`으로 정리한다. 가입 대기표와 문자 재인증 증표는 영구 저장하지 않는다.
- `USER401`~`USER407`를 구분하고 연결 증표·challenge의 401을 세션 재발급으로 처리하지 않는다. `USER404`(503)는 인증 거절과 합치지 않고 일시 장애로 안내한다. Apple 로그인의 `USER401`에는 이메일 공유가 필요할 수 있다는 안내를 덧붙인다(원인을 단정하지 않는다). 인증/연결 요청·응답 본문과 Authorization/Cookie 헤더를 디버그 로그에 남기지 않는다.

## 설정

번들 ID는 `com.moyeota`. `Config/Base.xcconfig`에 공개 OAuth 식별자 `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_SERVER_CLIENT_ID`, `GOOGLE_REVERSED_CLIENT_ID`가 있으며 `Info.plist`의 `GIDClientID`, `GIDServerClientID`, URL scheme에 연결된다. 비밀 서버 키는 앱에 포함하지 않는다.

`Moyeota.entitlements`와 프로젝트에 Sign in with Apple capability를 선언했다. Apple Developer의 같은 App ID에 기능 활성화, 개발팀·프로비저닝 서명 설정은 별도로 필요하다. 실제 Apple 키 발급 및 서명 권한은 이 구현에서 확인하지 못했다.

서버 전용 환경변수 예시(값은 별도 비밀 저장소에 보관):

```text
APPLE_CLIENT_IDS=com.moyeota
APPLE_TEAM_ID=<Apple 개발팀 ID>
APPLE_KEY_ID=<Sign in with Apple 키 ID>
APPLE_PRIVATE_KEY=<서버 전용 .p8 개인키 내용>
```

개인키를 xcconfig·Info.plist·앱 번들에 넣지 않는다. 알림 URL과 키 발급·회전 절차는 백엔드 운영 문서를 따른다.

## 검증

- Core 전체: 885개, 51개 suite 통과.
- 추가 계약 테스트: 가입 대기 시 세션 미생성, Apple 이름 누락·비공개 이메일, 정상 세션 저장, 깨진 토큰 거절, challenge 경로와 nonce, 본문 없는 탈퇴, 가입 필드 제한, 인증 로그 비노출, 증표 만료 시 세션 유지.
- 시뮬레이터 앱 빌드: arm64·x86_64 성공.
- UI 회귀 테스트: FeatureAuth 173개/19 suite, FeatureMyPage 188개/17 suite 통과. AppNavigation 101개/6 suite 통과. 소셜 전용 탈퇴 성공·실패 테스트 포함.
- Release 아카이브: 무서명 생성 성공 (`/private/tmp/Moyeota-social-auth.xcarchive`). 번들 ID·Google 설정·URL scheme 일치 및 Release ATS 평문 비허용 확인. 서명된 배포 산출물은 아니다.
- 실제 Google·Apple 계정 인증, Apple 가입 → Google 연결 → Android 동일 회원 로그인, App Store 서명·배포: 미검증. 모의 테스트 통과와 구분한다.

## 공식 근거

- [Google iOS 설정](https://developers.google.com/identity/sign-in/ios/start-integrating)
- [Google 서버 인증](https://developers.google.com/identity/sign-in/ios/backend-auth)
- [GoogleSignIn 10.1.0 의존성](https://github.com/google/GoogleSignIn-iOS/blob/10.1.0/Package.swift): 기존 Firebase 13.1.1의 app-check 12와 호환된다. 가이드의 예시 9.0.0은 app-check 11 제약으로 빌드할 수 없어 정식 10.1.0을 고정했다.
- [Apple nonce](https://developer.apple.com/documentation/authenticationservices/asauthorizationopenidrequest/nonce)

## 재현 명령과 산출물

```sh
swift test --package-path Packages/MoyeotaCore
xcodebuild -project Moyeota.xcodeproj -scheme Moyeota -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/moyeota-ios-social-derived -clonedSourcePackagesDirPath /private/tmp/moyeota-ios-social-app-packages CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Moyeota.xcodeproj -scheme Moyeota -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/moyeota-ios-social-archive-derived -clonedSourcePackagesDirPath /private/tmp/moyeota-ios-social-app-packages -archivePath /private/tmp/Moyeota-social-auth.xcarchive CODE_SIGNING_ALLOWED=NO archive
```

UI 테스트는 `Packages/MoyeotaUI`에서 `MoyeotaUI-Package` 스킴으로 iPhone 17/iOS 26.5 시뮬레이터에서 실행했다. `-only-testing:FeatureAuthTests`, `-only-testing:FeatureMyPageTests`, `-only-testing:AppNavigationTests`를 사용했다. 앱과 패키지 테스트의 SourcePackages 경로를 분리해야 패키지 해석 중 앱 전용 바이너리가 정리되는 충돌을 피할 수 있다.

최종 로그: `/private/tmp/ios-core-tests-final.log`, `/private/tmp/ios-social-feature-tests-final.log`, `/private/tmp/ios-social-nav-tests.log`, `/private/tmp/ios-social-build.log`, `/private/tmp/ios-social-archive-final.log`.

검증 중 로그인폼의 외부 safeAreaInset이 하단 여백을 바꾸는 문제가 발견되어 소셜 진입 버튼을 기존 폼 스크롤 안으로 옮겼다. 내비게이션 101개 재검증으로 수정 확인했다. 기존 탈퇴 성공 알림의 소스 검사도 분기 구문을 수용하게 갱신하고, 실제 소셜 탈퇴 성공·실패 콜백 테스트 2개를 추가했다.

## 2026-11-15 보완

계약 대조에서 나온 결함 세 건(연결용 문자 쿨다운 표시, `USER404`·Apple `USER401` 문구, 모르는 provider 디코딩)을 고치고 경로·메서드·본문 필드명·오류 코드 계약 테스트를 더했다.

- Core 전체: 896개, 51개 suite 통과.
- FeatureAuth 177개/20 suite, FeatureMyPage 195개/18 suite 통과.
- AppNavigation 101개/6 suite 통과(`-parallel-testing-enabled NO`, CI와 `scripts/check.sh`가 쓰는 직렬 실행). 처음에는 이 옵션 없이 돌려 `BackHandlerStackTest`의 「덮여 있는 동안 켜져도 등록되지 않고 돌아오면 등록된다」와 `MainNavGraphRuntimeTest`의 「복귀는 한 번뿐이다 …」 2건이 실패했다. 같은 조건에서는 `develop`도 똑같이 실패하고, 직렬로 돌리면 통과한다. 창을 띄우는 런타임 테스트라 병렬 실행에서 서로 간섭하는 것으로 보이며 이번 변경과 무관하다.
- 시뮬레이터 화면 확인, 앱 타깃 빌드, 실제 계정 인증은 이번에 하지 않았다.
