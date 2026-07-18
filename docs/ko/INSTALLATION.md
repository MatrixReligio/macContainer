---
source_revision: f94970774a25e899b7fb4a623d35c555d11f12e2
language: ko
document_id: installation
---

<a id="installation"></a>
# 설치

[영문 소스](../en/INSTALLATION.md) · 소스 리비전 `f94970774a25e899b7fb4a623d35c555d11f12e2`

MacContainer는 Apple Silicon과 macOS 26 이상이 필요합니다. Apple container 런타임이 없어도 앱은 열리지만 설치 전까지 컨테이너 작업을 사용할 수 없습니다.

<a id="before-installing"></a>
## 설치 전

정식 GitHub Release에서만 다운로드하고 macOS가 앱을 서명 및 공증된 것으로 인식하는지 확인하십시오. 응용 프로그램 폴더로 옮긴 후 정상적으로 여십시오. Gatekeeper 경고를 우회하지 말고 검증할 수 없으면 해당 복사본을 제거한 뒤 다시 다운로드하십시오.

런타임은 몰래 설치되지 않습니다. **설정 → 런타임**에서 권한 작업 전에 후보 버전, 출처, 서명자, SHA-256, 디스크 영향, 호환성 상태를 확인할 수 있습니다.

<a id="runtime-package"></a>
## 런타임 패키지 검증

포함된 카탈로그는 현재 MacContainer 0.1.x에서 Apple container 1.1.0을 승인합니다. 검토된 ID는 자산 `container-1.1.0-installer-signed.pkg`, 팀 `UPBK2H6LZM`, 서명자 `Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)`, 영수증 `com.apple.container-installer`, SHA-256 `0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714`입니다.

다운로드는 비공개 스테이징 디렉터리에 저장됩니다. 링크와 예상치 못한 파일 형식을 거부하고 크기, 다이제스트, 설치 프로그램 서명, 영수증을 검증한 후에만 **검토 후 설치**를 활성화합니다. 메타데이터 일치만으로는 충분하지 않습니다.

<a id="administrator-approval"></a>
## 관리자 승인

관리자 승인은 다운로드, 검증, 최종 검토가 끝나고 설치를 실제로 시작할 때만 요청합니다. 권한 있는 도우미는 고정된 형식화 작업과 검토된 경로만 받고 임의 셸 텍스트를 받지 않습니다. 승인을 취소하면 현재 런타임을 유지하고 스테이징을 정리합니다. 활동 센터는 영구 트랜잭션 단계를 기록하며 중단 후에는 검증된 복구 작업만 제공합니다.

처음 사용할 때 macOS의 **시스템 설정 → 일반 → 로그인 항목**에서 MacContainer 도우미를 별도로 허용해야 할 수 있습니다. 런타임 화면은 이 상태를 명확히 표시하고 올바른 설정 화면을 엽니다. 한 번 허용한 뒤 MacContainer로 돌아와 **승인 확인**을 선택하고 설치를 다시 시도하십시오.

<a id="post-install"></a>
## 설치 후 호환성

설치 프로그램 성공만으로 완료되지 않습니다. 런타임 상태와 컨테이너, 이미지, 빌더, 네트워크, 볼륨, 레지스트리, 머신, 디스크 사용량, 구성, 기능을 검증합니다. 모두 통과해야 **준비됨**으로 표시합니다. 업그레이드 후 검사 실패 시 롤백 지점을 복원하고 이전 런타임을 다시 검증합니다. 첫 설치의 사후 검사 실패는 미완료와 복구 작업을 표시합니다.

<a id="app-updates"></a>
## MacContainer 업데이트

앱 업데이트와 Apple container 런타임 업데이트는 별개입니다. 앱은 서명된 Sparkle 피드로 설정을 유지하며 업데이트하고 런타임은 더 엄격한 [런타임 업데이트](RUNTIME_UPDATES.md) 정책을 따릅니다. 제거는 [완전 제거](COMPLETE_UNINSTALLATION.md), 서명 또는 승인 문제는 [문제 해결](TROUBLESHOOTING.md)을 참조하십시오.
