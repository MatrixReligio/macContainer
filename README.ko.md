---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: ko
document_id: readme
---

<a id="maccontainer"></a>
# MacContainer

MacContainer는 Apple `container` 런타임을 위한 네이티브 macOS 제어 센터입니다. 검토된 전체 기능을 SwiftUI로 쉽게 사용할 수 있게 하면서 고급 매개변수, 명확한 안전 게이트, 정확한 복구 정보를 유지합니다.

> **시험판:** 버전 0.1.2는 Apple Silicon과 macOS 26 이상이 필요합니다. 중요한 컨테이너 데이터는 별도로 백업하고 파괴적 작업 전에 모든 값을 검토하십시오.

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

영문 소스 리비전: `f94970774a25e899b7fb4a623d35c555d11f12e2`

<a id="why"></a>
## MacContainer를 사용하는 이유

- 컨테이너, 이미지, 빌드, 머신, 네트워크, 볼륨, 레지스트리, 시스템 작업을 네이티브로 관리합니다.
- 8개의 안전한 시나리오 템플릿을 제공하고 실행 전에 모든 생성 값을 확인합니다.
- 검토된 Apple 라이브러리와 프로토콜을 형식 안전하게 직접 사용하며 프로덕션 코드는 `container` CLI를 호출하지 않습니다.
- 설치, 업그레이드, 롤백, 완전 제거에 명확한 권한 경계가 있습니다.
- 알 수 없는 런타임은 서명된 실제 기기 테스트와 모든 검사를 통과하기 전까지 자동 설치되지 않습니다.
- 기본적으로 로컬에서만 처리하며 분석 또는 원격 측정 데이터를 보내지 않습니다.
- 완전 제거는 제품이 제어하는 잔여 항목 15개 범주를 검증합니다.

<a id="requirements"></a>
## 요구 사항

- Apple Silicon Mac과 macOS 26 이상
- 런타임 설치, 업데이트, 롤백 또는 완전 제거 시 관리자 계정
- GitHub, 레지스트리 또는 승인된 업데이트 피드를 명시적으로 사용하는 작업에만 네트워크 필요

Xcode 26은 개발 시에만 필요합니다.

<a id="documentation"></a>
## 문서

- [사용 설명서](docs/ko/USER_GUIDE.md)
- [설치](docs/ko/INSTALLATION.md)
- [런타임 업데이트](docs/ko/RUNTIME_UPDATES.md)
- [완전 제거](docs/ko/COMPLETE_UNINSTALLATION.md)
- [문제 해결](docs/ko/TROUBLESHOOTING.md)
- [아키텍처](ARCHITECTURE.md), [개인정보 보호](PRIVACY.md), [보안](SECURITY.md)

일반 사용자 작업은 모두 앱에서 수행할 수 있으며 터미널이 필요하지 않습니다.

<a id="development"></a>
## 개발

저장소는 프로젝트 로컬 도구를 고정하고 생성 파일, 공급망 메타데이터, 형식, 테스트, 손쉬운 사용, 릴리스 정책을 검증합니다. [개발 안내](DEVELOPMENT.md)와 [기여 안내](CONTRIBUTING.md)를 참조하십시오. 정식 저장소는 `matrixreligio/macContainer`입니다.

<a id="security-support"></a>
## 보안 및 지원

취약점 세부 정보를 공개 Issue에 게시하지 말고 [보안 정책](SECURITY.md)에 따라 비공개로 신고하십시오. 제품 지원은 [지원 안내](SUPPORT.md) 또는 [contact@matrixreligio.com](mailto:contact@matrixreligio.com)을 이용하십시오. MacContainer는 Apache-2.0 라이선스로 제공됩니다. [LICENSE](LICENSE), [NOTICE](NOTICE), [타사 고지](THIRD_PARTY_NOTICES)를 참조하십시오.
