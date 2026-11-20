# 빌드 환경

이 프로젝트를 빌드하는 데 필요한 엔진과 툴체인 정보, 그리고 엔진에 직접 적용한 로컬 패치를 기록합니다. 엔진을 새로 받거나 Visual Studio를 업데이트한 뒤에는 이 문서를 먼저 확인합니다.

---

## 1. 엔진

| 항목 | 값 |
|---|---|
| 종류 | 소스 빌드 엔진 (`Tango.uproject`의 `EngineAssociation`이 GUID로 연결됨) |
| 버전 | Unreal Engine 5.8.4 |
| 브랜치 / 커밋 | `release` / `f45729c0b6f0` (5.8.4 release) |

`EngineAssociation` GUID는 PC마다 다르게 등록됩니다. 다른 PC에서는 `.uproject` 파일을 우클릭하고 **Switch Unreal Engine version**으로 해당 PC의 소스 빌드 엔진을 다시 연결합니다.

---

## 2. 툴체인

| 항목 | 값 |
|---|---|
| IDE | Visual Studio 2026 (18) Community |
| MSVC 툴셋 | VS 업데이트에 따라 바뀝니다. 아래 이력 참고 |
| Windows SDK | 10.0.26100.0 |

**MSVC 툴셋 변경 이력**

| 시점 | 툴셋 | 비고 |
|---|---|---|
| ~2026-11-19 | 14.50.35730 | |
| 2026-11-19 | 14.51.36263 | 엔진 Editor 전체를 다시 빌드. 이때 아래 패치가 필요해짐 (PR #10) |
| 2026-11-20 | 14.52.37025 | VS 업데이트로 14.51 툴셋이 제거됨. 다음 빌드 때 엔진 전체를 다시 빌드할 수 있음 |

MSVC 툴셋이 바뀌면 UBT가 엔진 모듈 전체를 다시 빌드합니다. 툴셋 버전을 고정하는 방안(`BuildConfiguration.xml`의 `CompilerVersion`)은 M5에서 검토합니다.

---

## 3. 엔진 로컬 패치

엔진 리포지토리에 커밋하지 않은 수정입니다. **엔진을 다시 받거나 업데이트하면 다시 적용해야 합니다.**

### 3.1 `nvtess.h`: `<hash_map>` 제거 대응

- **파일:** `Engine/Source/ThirdParty/nvtesslib/inc/nvtess.h` (154행 근처)
- **증상:** MSVC 14.51 이상에서 엔진을 빌드하면 `<hash_map>`을 찾지 못해 컴파일 오류가 납니다. MSVC STL에서 비표준 헤더 `<hash_map>`이 삭제되었기 때문입니다.
- **수정:**

  ```diff
   #if PLATFORM_MAC || PLATFORM_LINUX
   #include <unordered_map>
   #include <vector>
   #else
  -#include <hash_map>
  +#include <unordered_map>
   #endif
  ```

- **동작 영향 없음:** 같은 파일에서 `#define NO_STL 1`이 켜져 있어서 `EdgeDict`, `PositionDict`는 엔진의 `FHashMap`을 씁니다. `stdext::hash_map`을 쓰는 분기는 컴파일되지 않습니다.
- **적용 확인:** 엔진 폴더에서 다음을 실행해 이 파일 하나만 수정되어 있는지 확인합니다.

  ```powershell
  git -C <엔진 경로> status --short Engine/Source
  ```
