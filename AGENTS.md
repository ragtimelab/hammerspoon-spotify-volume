# SpotifyVolume 작업 지침

이 저장소의 소스와 스크립트를 기준으로 수정한다. 설치된 Spoon, 관리 도구, 개인 Hammerspoon 설정에 직접 패치하지 않는다. 문서와 명령의 동작이 어긋나면 정의와 테스트를 확인해 원인을 해결한다. 시각을 확인하거나 기록할 때는 `date`로 검증한다.

## 코드 검증

- 루트에서 `make verify`를 실행한다. 소스 검사, Lua·Swift 테스트, 경고를 오류로 처리하는 네이티브 빌드, 임시 경로의 설치 수명주기 테스트를 포함한다. CI는 Intel과 Apple Silicon에서 이 검증과 `./Tests/Shell/source_release_test.zsh`를 실행한다. [Makefile](Makefile) · [테스트 진입점](scripts/test) · [CI](.github/workflows/verify.yml)
- 키 반복은 Hammerspoon의 press/repeat/release 콜백과 비동기 FIFO를 사용한다. Lua 반복 타이머를 추가하지 않는다. Spotify 쓰기가 확인된 뒤 볼륨 변경을 상태와 HUD에 반영하고, PID가 바뀌면 이전 세대의 응답을 폐기한다. HUD 실패는 볼륨 제어와 독립적으로 처리한다. [아키텍처](docs/architecture.md) · [컨트롤러 테스트](Tests/Lua/controller_test.lua)

## 릴리스 패키징

- 승인된 커밋의 전체 SHA와 해당 SHA의 양쪽 아키텍처 CI 결과를 확인한 뒤 `./scripts/package <commit>`을 실행한다. `make package`는 현재 `HEAD`를 사용한다. 패키지는 지정한 Git 트리의 허용 경로에서 생성된다. 릴리스에 올리기 전에 아카이브 멤버 목록, 내부 `SOURCE-COMMIT`과 `SOURCE-SHA256SUMS`, 외부 SHA-256과 `Install-v<버전>.txt`의 다이제스트를 대조한다. 배포물은 검토한 소스 아카이브, 외부 체크섬, 버전별 설치 안내 세 가지다. [배포](docs/deployment.md) · [패키징](scripts/package) · [부트스트랩](scripts/bootstrap)

## 설치와 활성화

- 격리 검증에서는 `HSV_INSTALL_ROOT`와 `HSV_HAMMERSPOON_DIR`를 각각 임시 경로로 지정하고 `./scripts/install --files-only`를 사용한다. 소스 배포물 검증은 아카이브를 풀어 네이티브로 빌드하고 `installed, inactive`와 제거 후 `Not installed.`를 확인한다. `--files-only`도 설치 위치와 Spoon 링크에 쓰므로 두 경로를 지정한다. CI의 Apple Silicon 빌드·파일 설치 결과와 실제 Hammerspoon·Spotify 지원 여부는 [호환성 문서](docs/compatibility.md)의 검증 범위를 따른다. [설치 테스트](Tests/Lua/install_test.zsh) · [소스 배포물 테스트](Tests/Shell/source_release_test.zsh)
- 운영 설치·설정 변경·재로드는 사용자 승인 범위에서 수행한다. [README](README.md)의 설치된 `spotify-volume` 관리 도구를 사용하고, **Reload Config** 후 `status --after-reload`에서 대상 빌드의 활성화를 확인한다. 일반 `status`도 보류 변경을 확정할 수 있고, `--after-reload`는 새 런타임이 보고되지 않으면 이전 구성을 복원할 수 있다. Spotify를 실행해 제어 준비 상태를 확인하고, 실제 키의 짧은 누름·길게 누름, HUD와 시스템 볼륨을 확인해 실사용 검증을 마친다. 필요한 경우 관리 도구의 `rollback`으로 보류 변경을 취소하거나 직전 등록 릴리스를 선택한다. [설치 관리자](scripts/lifecycle.rb) · [문제 해결](docs/troubleshooting.md)

## 공개 저장소 경계

- 개인 설정, 단축키·볼륨 상태, 로컬 백업·복구본, 이전 비공개 설치 이력은 공개 Git 이력과 배포물 밖에 보관한다. 공개 소스·테스트에는 개인 절대 경로 대신 임시 경로와 합성 데이터를 사용한다. 운영 복구는 로컬의 등록된 릴리스와 백업을 사용한다. [배포](docs/deployment.md) · [소스 검사](scripts/check-source) · [설치 관리자](scripts/lifecycle.rb)
