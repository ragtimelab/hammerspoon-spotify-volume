# Changelog

## 0.2.0

- Add verified source installation for native Intel and Apple Silicon.
- Let each user choose their own two global shortcuts.
- Validate the actual release before activation or rollback.

## 0.1.1 - 2026-09-09

- Preserve native hotkey repeat timing, segment mapping, HUD and sound while moving Spotify Apple events into a persistent serial worker.
- Reject stale repeats after synchronization failure and ignore old process generations.
- Bound READY/BUSY recovery, use atomic checked state writes, and flush confirmed state on worker termination.
- Verify running build identity and worker ownership; serialize lifecycle operations and preserve other configuration after uninstall.

이 프로젝트는 Semantic Versioning을 사용합니다.

## 0.1.0 - 2026-09-05

- 16단계 AppleScript Spotify 볼륨 컨트롤러
- Hammerspoon native key repeat 처리
- Spotify PID 기반 HUD helper 생명주기
- versioned stdin protocol과 helper singleton
- Hammerspoon Spoon 패키징
- 원자적 install, rollback, uninstall
- Lua runtime 및 Swift protocol 회귀 테스트
