# PR 초안

제목: Google 로그인과 기존 계정 연결 지원

기존 아이디 로그인에 Google 네이티브 로그인을 추가한다. iOS도 Google 로그인만 제공한다. Apple 로그인 UI는 제품 결정으로 제외했다(2026-11-15). 신규 회원은 기존 문자 인증과 프로필 입력 후 가입하며, 로그인 수단 관리에서 등록된 번호 재인증을 거쳐 Google 계정을 기존 회원에 연결한다. Google을 연결한 회원은 Android에서 같은 계정을 사용할 수 있다.

App Store 심사 지침 4.8(Login Services)은 Google 로그인 같은 외부 로그인으로 주 계정을 만들면 개인정보 보호 요건을 갖춘 다른 로그인 서비스를 동등한 선택지로 함께 제공하라고 요구한다. Apple 로그인을 제외한 것은 이 위험을 알고 내린 제품 결정이다.

앱 계층 SDK 주입, 공개/인증 API 분리, 메모리 전용 가입 증표, hasPassword 기반 탈퇴, 인증 로그 비노출을 포함한다. 기존 회원의 비밀번호와 아이디 로그인은 유지한다.

검증: Core 885개, FeatureAuth 173개, FeatureMyPage 188개, AppNavigation 101개 테스트 통과. arm64·x86_64 시뮬레이터 앱 빌드와 Release 무서명 아카이브 성공. 상세는 `SOCIAL-AUTH-IMPLEMENTATION.md`를 확인한다. 실제 Google 계정 인증과 배포 서명은 미검증이다.

병합 순서: 백엔드 API 배포 및 Google 허용 audience 준비 → 앱 변경. Sign in with Apple capability를 쓰지 않으므로 Apple Developer 설정 변경과 서명 프로필 재발급은 필요 없다.
