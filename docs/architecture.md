# Architecture

## 경계

`SpotifyVolume.spoon`은 Hammerspoon integration을, Swift executable은 HUD 표시만 담당합니다.

```text
F11/F12
  → hs.hotkey pressed/repeat/released callback
  → controller
  → 입력 FIFO와 비동기 adapter
  → spotify-control (PID 대상 AppleEvent, 직렬 실행)
  → Spotify sound volume

controller
  → OSD supervisor
  → persistent spotify-osd --server
  → com.apple.OSDUIHelper
```

볼륨 변경 성공 여부와 HUD 전달 성공 여부는 분리합니다. AppleScript 적용에 실패하면 controller 상태와 HUD를 커밋하지 않습니다. HUD helper가 실패하면 supervisor만 제한적으로 재시작되며 Spotify 볼륨 제어 상태를 훼손하지 않습니다.

## 생명주기

- application watcher를 초기 process snapshot보다 먼저 시작합니다.
- Spotify PID가 존재할 때만 helper의 desired state가 running입니다.
- Spotify 종료 시 stdin EOF로 정상 종료를 요청하고 250ms 이후에도 살아 있으면 종료합니다.
- helper crash는 0.25초, 1초, 4초 backoff 이후 fault 상태로 제한합니다.
- BUSY 충돌도 같은 예산을 사용하고 READY는 5초 이내에 받아야 합니다.
- 30초 안정 동작 후 failure count를 초기화합니다.
- CFMessagePort singleton이 reload 경쟁 중 두 server가 동시에 활성화되는 것을 막습니다.

## 프로토콜

```text
READY 1 <buildID>
SHOW 0
OK 0
BUSY
ERR <code> <message>
```

Lua와 helper protocol version이 다르면 supervisor는 helper를 중지하고 재시작 정책에 따라 처리합니다.

## 통신 작업자와 상태

`spotify-control`은 JSON Lines로 `get`, `set`, `write`를 처리합니다.
각 요청의 `id`, `generation`, `pid`, `operation`을 검증하며 응답에는
같은 id/generation과 `ok`, `value` 또는 `error`/`code`를 포함합니다.
Lua는 응답을 받은 뒤 다음 프레임을 전송하므로 `hs.task:setInput`의 미전송
입력 대체 동작에 의한 누락을 피합니다. 입력 FIFO는 4096건, 수신 버퍼는
64KiB로 제한하고 초과를 오류로 표시합니다.

명령별 AppleEvent 제한은 120초, 부모의 응답 watchdog은 125초입니다.
시간 초과는 Spotify의 작업 취소를 보장하지 않으므로 쓰기를 재전송하지
않습니다. 실패한 누름의 반복은 차단하고 새 누름에서 실제 값을 조회합니다.
PID 교체와 종료는 세대를 무효화하여 이전 응답이 새 상태를 덮어쓰지 못하게 합니다.

확정된 쓰기는 작업자의 별도 저장 큐에서 250ms debounce로 저장합니다.
release 저장 요청, EOF, SIGTERM에서는 마지막 확정값을 flush합니다.
파일은 O_EXCL/O_NOFOLLOW와 0600으로 생성하고 fsync/close/rename의 성공을
확인합니다. Hammerspoon 입력 콜백에서 chmod 프로세스를 실행하지 않습니다.

## 근거

- [Apple NSEvent keyRepeatDelay](https://developer.apple.com/documentation/appkit/nsevent/keyrepeatdelay)
- [Hammerspoon 1.1.1 hotkey 구현](https://github.com/Hammerspoon/hammerspoon/blob/1.1.1/extensions/hotkey/libhotkey.m)
- [hs.task 입력과 streaming callback](https://www.hammerspoon.org/docs/hs.task.html)
- [Apple PID descriptor](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/init(processidentifier:))
- [AppleEvent 전송](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/sendevent(options:timeout:))
- [AppleScript 제한 시간과 취소의 차이](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_control_statements.html)
