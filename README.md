# SpotifyVolume

**다른 앱을 쓰는 중에도, 직접 정한 전역 단축키로 Spotify 데스크톱 앱의 볼륨만 조절할 수 있습니다.** macOS 시스템 볼륨과 다른 앱의 소리는 그대로입니다. 브라우저를 보거나 문서를 쓰면서 Spotify 창으로 전환할 필요 없이 음악 소리를 줄일 수 있습니다.

## 지원 환경

- macOS 15, Hammerspoon 1.1.1, Spotify 데스크톱 앱
- Mac의 지원 아키텍처는 Intel (`x86_64`)입니다. Apple Silicon은 자동 빌드·설치 검증을 통과했으며, Hammerspoon·Spotify 실사용 검증이 남아 있습니다.
- Apple Command Line Tools. 처음 한 번은 터미널에서 `xcode-select --install`로 설치할 수 있습니다.

## 설치

[공식 릴리스](https://github.com/ragtimelab/spotify-volume-spoon/releases)에서 원하는 버전의 `Install-v<버전>.txt`를 엽니다. 그 안의 명령 블록을 터미널에 한 번 붙여 넣으면 해당 버전의 소스를 내려받아 SHA-256을 확인한 후 이 Mac에서 빌드하고 설치합니다.

## 단축키 설정

설치 직후 설정하거나 나중에 `configure`로 재개할 수 있습니다. 내리기와 올리기 조합을 한 번씩 누르고, 제안된 Hammerspoon 설정을 확인한 뒤 적용합니다. Hammerspoon 메뉴에서 **Reload Config**를 선택하고 `status --after-reload`로 활성화를 확인한 후 두 단축키를 시험하세요.

기본 단축키는 비어 있습니다. 숫자 키패드가 있는 Apple Magic Keyboard의 한 설정 예에서는 `fn`+F11 / `fn`+F12를 Spotify에 할당하고, 같은 키를 그냥 눌러 macOS 시스템 볼륨을 조절합니다. 실제 동작은 키보드와 macOS의 기능 키 설정에 따라 달라집니다.

Spotify 볼륨은 16단계입니다. 길게 누르면 한 단계씩 반복해서 바뀝니다. 지원 환경에서는 화면에 HUD를 표시합니다. Spotify 제어에 필요한 Automation 권한은 macOS 설정에서 사용자가 부여합니다.

## 운영

```sh
"$HOME/Library/Application Support/Hammerspoon/SpotifyVolume/spotify-volume" status
"$HOME/Library/Application Support/Hammerspoon/SpotifyVolume/spotify-volume" configure
"$HOME/Library/Application Support/Hammerspoon/SpotifyVolume/spotify-volume" rollback
"$HOME/Library/Application Support/Hammerspoon/SpotifyVolume/spotify-volume" uninstall
```

업데이트는 새 릴리스의 설치 명령을 실행합니다. 제거 후에도 상태와 검증된 릴리스는 보관됩니다. 상태 삭제는 `uninstall --purge-state`로 요청합니다.

## 개발

개발·CI 검증에는 Command Line Tools, Lua 또는 LuaJIT와 ripgrep이 필요합니다. `make verify`로 검증하고, `make package`로 커밋된 소스의 배포물을 생성합니다.

[아키텍처](docs/architecture.md) · [배포](docs/deployment.md) · [호환성](docs/compatibility.md) · [문제 해결](docs/troubleshooting.md) · [MIT](LICENSE)
