# /problem — 문제 분석부터 배포까지 원스톱 처리

문제 상황을 분석하여 해결책을 제시하고, 사용자가 선택한 해결책을 실행하여 배포까지 완료한다.
브랜치명에 `#`이 포함되므로, 모든 git/gh 명령에서 브랜치명은 반드시 따옴표로 감싼다.

## Preflight

1. `gh auth status` — 인증 실패 시 **중단**
2. `git status --short` — 비어 있지 않으면 기존 변경사항을 임시 보관한다:
   - `git stash push -u -m "problem-preflight-stash"` (untracked 파일 포함)
   - `HAS_STASH=true` 플래그 설정 (비어 있으면 `HAS_STASH=false`)
3. `git checkout dev && git pull origin dev` — 항상 최신 dev에서 시작
4. `HAS_STASH=true`이면 기존 변경사항을 dev 위에 복원한다:
   - `git stash pop` — 충돌 발생 시 충돌 파일을 분석하여 자체 해결한 뒤 진행
   - 이후 Phase 1~8은 기존 변경사항이 워킹 트리에 있는 상태에서 진행된다

## Phase 1: 문제 분석 & 해결책 제시

> **단순 변경 스킵**: 사용자가 구체적인 변경 내용을 직접 명시한 경우 (예: "토큰 만료 시간 30분으로 변경해줘") Phase 1을 스킵하고 해당 내용을 단일 작업으로 구성하여 Phase 2로 직행한다.

1. 사용자가 제시한 에러 로그 / 문제 상황을 분석한다.
2. 관련 코드를 탐색하여 원인을 파악한다.
3. 해결책을 번호와 함께 제시한다. 하나의 해결책 안에 API 변경과 비API 변경이 섞일 수 있으므로, **해결책 내부를 작업(task) 단위로 분리**하여 제시한다.

   각 해결책의 구조:

   ```
   해결책 N: [한 줄 요약]
   ├─ 작업 N-a [API]    변경 내용 설명    | 영향 파일: ...
   ├─ 작업 N-b [비API]  변경 내용 설명    | 영향 파일: ...
   └─ 작업 N-c [API]    변경 내용 설명    | 영향 파일: ...
   위험도: 낮음 / 중간 / 높음
   ```

   작업 분류 기준:
   - `[API]`: Controller / Service / Repository / DTO / Entity 레이어 변경 포함 (WebSocket·Kafka 등 메시징 핸들러에서 분리된 Service 포함, 해당 레이어를 직접 지원하는 Mapper·Validator·Helper·Factory·Enum 포함) → Test-First 절차
   - `[비API]`: 설정, 문서, 인프라, 유틸, 메시징 핸들러 라우팅/설정 등 → 일반 코드 변경 절차

4. **사용자 확인 대기** — 적용할 해결책 번호 선택 요청 (예: "1, 3번 적용")

## Phase 2: 의존성 분석 & 실행 계획

사용자가 해결책을 선택하면:

1. 선택된 해결책의 모든 작업을 평탄화(flatten)하여 작업 목록을 만든다.
2. 작업 간 의존성을 분석한다:
   - **같은 파일을 수정**하는 작업 → 순차 처리
   - **같은 도메인의 연관 로직을 변경**하는 작업 → 순차 처리
   - **서로 다른 도메인/파일을 독립적으로 변경**하는 작업 → 병렬 처리 가능

3. 실행 계획을 보고한다:

   ```
   실행 계획:

   [병렬 그룹 A]
   - 작업 1-a [API]   AuthService 만료 검증 로직 수정     → Test-First
   - 작업 1-b [비API] application.yml 토큰 만료 시간 변경  → 코드 변경

   [병렬 그룹 B]
   - 작업 3-a [API]   NotificationService 재시도 로직 추가 → Test-First

   [순차 그룹 C] (같은 도메인 변경)
   - 작업 2-a [API]   RefreshTokenService 갱신 메서드 추가 → Test-First [1순위]
   - 작업 2-b [API]   AuthController 갱신 엔드포인트 추가  → Test-First [2순위]

   실행 방식: 그룹 A, B, C를 병렬 실행 / 그룹 C 내부는 순차 실행
   ```

4. 실행 계획 보고 후 사용자 확인 없이 즉시 Phase 3으로 진행한다.

## Phase 3: 이슈 & 브랜치

실행 계획 보고 후, 코드 변경 전에 이슈와 브랜치를 먼저 생성한다.

1. 변경 성격에 맞는 타입 선택:

| 타입 | label | 브랜치 prefix | 이슈 템플릿 |
|------|-------|---------------|-------------|
| `[FEAT]` | `✨ FEAT` | `feat/` | `기능-구현.md` |
| `[FIX]` | `🔧 FIX` | `fix/` | `기능-수정.md` |
| `[BUG]` | `🕷️ BUG` | `bug/` | `오류-수정.md` |
| `[CHORE]` | `🔩 CHORE` | `chore/` | `기타-수정.md` |
| `[REFACT]` | `♻️ REFACT` | `refact/` | `리팩토링.md` |
| `[DOCS]` | `📜 DOC` | `docs/` | `문서-작업.md` |

2. `gh issue create` — 제목: `[TYPE] 설명` (선택된 해결책들을 요약), 본문: 위 이슈 템플릿의 구조를 따르되 Phase 2의 실행 계획 기반으로 내용 채움
3. 브랜치 생성 `"<prefix>#<이슈번호>"` → checkout (기존 변경사항은 워킹 트리에 그대로 유지됨)

## Phase 4: 코드 변경 실행

이슈 브랜치에서 코드 변경을 실행한다.

### 병렬 실행

독립적인 그룹들을 **Agent tool로 동시에 호출**한다.
- 각 에이전트는 `isolation: "worktree"`로 독립된 워크트리에서 작업한다.
- 각 에이전트 prompt에는 다음을 포함한다:
  - 해당 그룹에 속한 작업들의 상세 내용 (변경 대상, 변경 방법)
  - 각 작업의 타입에 따른 실행 절차 (아래 `[API] Test-First 절차` 또는 `[비API] 일반 절차` 전문)
  - 그룹 내에 순차 작업이 있으면 순서를 명시
  - 단, PR 생성이나 push는 하지 않는다 — 변경사항은 로컬 커밋까지만 수행한다
- 모든 에이전트 완료 후 각 워크트리의 변경 커밋을 현재 브랜치에 **cherry-pick**으로 통합한다. cherry-pick 충돌 발생 시 메인 에이전트가 충돌을 해결한 뒤 진행한다.

### 순차 실행

의존성이 있는 작업들을 **순서대로 현재 세션에서 실행**한다.
- 각 작업의 타입에 따른 절차를 따른다 (아래 참조).
- 각 작업 적용 후 빌드 검증(`./gradlew clean bootJar`)을 실행하여 이전 작업과의 호환성을 확인한다.
- 단, 커밋/PR은 하지 않는다 (변경사항만 적용).

### 혼합 (병렬 + 순차)

- 독립적인 그룹은 병렬로, 그룹 내 의존적인 작업은 순차로 실행한다.

---

### `[API]` Test-First 절차

1. **변경 대상 분석**: 변경이 필요한 도메인과 레이어(Controller / Service / Repository) 파악

2. **테스트 코드 먼저 작성** — 기존 테스트 패턴을 따른다:

   **Controller 테스트** (`@WebMvcTest` 기반 단위 테스트):
   - Service를 `@MockitoBean`으로 Mock
   - Security 필터 비활성화 (`@AutoConfigureMockMvc(addFilters = false)`)
   - `CurrentUserArgumentResolver`를 Mock하여 인증 사용자 주입
   - HTTP 매핑, 요청/응답 직렬화, 상태코드 검증
   - BDDMockito 스타일 (`given`, `willDoNothing`, `verify`)

   **Service 테스트** (`@DataJpaTest` + Testcontainers 기반 통합 테스트):
   - `@Import({ TestContainersConfig.class, ...ServiceImpl.class, ...MapperImpl.class })`
   - Repository는 실제 빈 사용 (`@Autowired`)
   - 외부 경계(Kafka, 외부 API 등)만 `@MockitoBean`으로 Mock
   - `@AfterEach`에서 관계 테이블부터 순서대로 `deleteAll()`
   - Helper 메서드로 테스트 데이터 생성 (`persistXxx`, `cu`)
   - `@Nested` + `@DisplayName`으로 메서드별 그룹화

3. **구현 코드 작성**: 테스트가 기대하는 동작을 만족하도록 구현

4. **테스트 실행 & 검증**:
   - `./gradlew test --tests "변경된 도메인의 테스트 클래스"` 실행
   - Controller, Service 테스트가 모두 있으면 둘 다 실행
   - 테스트 실패 시 → 구현 코드 수정 후 재실행 (테스트 코드가 아닌 구현 코드를 수정)

5. **빌드 검증**: `./gradlew clean bootJar`

### `[비API]` 일반 절차

1. 변경사항 코드에 적용
2. `./gradlew clean bootJar` 실행하여 빌드 검증
3. **기존 테스트 영향 검증**:
   - 변경된 클래스를 의존하는 기존 테스트가 있는지 확인한다 (특히 `@WebMvcTest`에서 자동 로딩되는 `@RestControllerAdvice`, `@ControllerAdvice`, `Filter`, `Interceptor` 등의 변경 시 주의)
   - 영향받는 테스트가 있으면 해당 테스트를 실행한다: `./gradlew test --tests "영향받는 테스트 클래스"`
   - 테스트 실패 시 테스트 코드를 수정한다 (예: 새 의존성 추가로 인한 `@MockitoBean` 누락 등)
   - 영향받는 테스트가 없으면 스킵한다
4. 모든 변경 파일 재검토: 문법/컴파일 에러, import 누락, 호환성, 보안 취약점

---

## Phase 5: 통합 & 검토

1. 모든 작업 적용 완료 후 전체 변경사항을 보고한다:
   - 작업별 변경 파일 목록
   - 테스트 결과 요약 (`[API]` 작업의 경우)
2. `./gradlew clean bootJar` 전체 빌드 검증
3. **병렬 작업이 있었던 경우** 또는 **`[비API]` 작업에서 기존 테스트를 수정한 경우** `./gradlew test` 전체 테스트를 실행한다 (워크트리 통합 후 호환성 검증 및 테스트 수정의 부작용 확인 목적). 해당하지 않으면 Phase 4에서 이미 검증 완료이므로 스킵한다.
4. **사용자 확인 대기** — 추가 수정 요청 시 반복, OK 시 다음 단계

## Phase 6-7a: 커밋 → PR 체크 (Sonnet 서브에이전트 1)

사용자 확인 완료 시, **Agent tool로 서브에이전트를 호출**하여 아래를 위임한다 (모델: CI/CD 실패 전이면 `"sonnet"`, 실패 후이면 `"opus"` — 「파이프라인 실패 시 Opus 전환 규칙」 참조).
서브에이전트 prompt에는 반드시 다음 정보를 포함한다:
- 브랜치명, 타입, 이슈번호
- 변경사항 요약
- 아래 Phase 6 ~ Phase 7a의 전체 절차
- 모든 `gh`/`git` 명령 실패 시 에러 내용을 반환하고 서브에이전트 종료
- 이슈/PR 생성 시 GitHub 템플릿 형식 준수
### Phase 6: 커밋 & PR & 머지 (dev)

1. `git status --short`로 커밋되지 않은 변경사항이 있는지 확인한다.
   - **변경사항이 있으면**: `git add -A` → 커밋 (메시지: 변경 내용 간결 요약, 끝에 `Co-Authored-By: Claude <사용 모델명> <noreply@anthropic.com>` — 예: Sonnet 사용 시 `Claude Sonnet 4.6`, Opus 사용 시 `Claude Opus 4.6`)
     - 커밋 메시지 작성을 위해 `git diff --cached --stat`과 `git diff --cached`로 변경 내용 파악
   - **변경사항이 없으면** (순수 병렬 실행으로 cherry-pick 완료): 커밋 스킵
2. `git pull origin dev --rebase` — 최신 dev와 동기화 (충돌 시 `git rebase --abort` 실행 후 에러 내용을 반환하고 **서브에이전트 종료**)
3. `git push --force-with-lease -u origin "<브랜치명>"`
4. `.github/PULL_REQUEST_TEMPLATE.md`를 읽어서 placeholder를 채운 뒤 → `gh pr create` — base: `dev`, head: `"<브랜치명>"`
   - 제목: `[TYPE/#이슈번호] 설명`
   - 출력 URL 끝의 숫자가 PR 번호 → 이후 단계에서 `<dev PR 번호>`로 사용
5. 머지 가능 여부 및 CI 체크 확인 (30초 간격, 최대 10분):
   ```bash
   SECONDS=0
   until [ "$(gh pr view <dev PR 번호> --json mergeable --jq '.mergeable')" != "UNKNOWN" ] && \
         [ "$(gh pr checks <dev PR 번호> --json name,state --jq '[.[] | select(.name == "ci")] | (length == 1 and all(.[]; .state == "SUCCESS"))')" = "true" ]; do
     if [ "$(gh pr checks <dev PR 번호> --json name,state --jq '[.[] | select(.name == "ci")] | any(.[]; .state == "FAILURE")')" = "true" ]; then echo "CI FAILED"; break; fi
     if [ $SECONDS -ge 600 ]; then echo "TIMEOUT"; exit 1; fi
     sleep 30
   done
   MERGEABLE=$(gh pr view <dev PR 번호> --json mergeable --jq '.mergeable')
   CI_STATE=$(gh pr checks <dev PR 번호> --json name,state --jq '[.[] | select(.name == "ci")][0].state')
   ```
   - `MERGEABLE` + `CI_STATE == SUCCESS` → `gh pr merge <dev PR 번호> --squash` (--auto 사용 금지)
   - `CONFLICTING` → 에러 내용을 반환하고 **서브에이전트 종료**
   - CI 실패 → 실패 로그를 반환하고 **서브에이전트 종료**
   - 타임아웃 → 에러 내용을 반환하고 **서브에이전트 종료**
6. 머지 후: `git checkout dev && git pull origin dev`
7. 머지 커밋 SHA 저장: `MERGE_SHA=$(gh pr view <dev PR 번호> --json mergeCommit --jq '.mergeCommit.oid')` — 이후 CI 폴링에 사용

### Phase 7a: CI & 배포 PR & 체크 대기

1. dev push → CI(`CI - GHCR Build & Push`) 자동 트리거
2. CI 폴링 (60초 간격, 최대 15분):
   ```bash
   SECONDS=0
   until [ "$(gh run list --branch dev --workflow ci-ghcr.yml --commit $MERGE_SHA --limit 1 --json status --jq '.[0].status')" = "completed" ]; do
     if [ $SECONDS -ge 900 ]; then echo "CI TIMEOUT"; exit 1; fi
     sleep 60
   done
   gh run list --branch dev --workflow ci-ghcr.yml --commit $MERGE_SHA --limit 1 --json conclusion --jq '.[0].conclusion'
   ```
   - timeout 시 에러 내용을 반환하고 **서브에이전트 종료**
3. CI 결과:
   - 성공:
     - `<배포 이슈 번호>`가 전달된 경우 → 해당 번호를 재사용
     - 전달되지 않은 경우 → 배포 이슈 생성: `gh issue create --title "[CHORE] 배포" --label "🔩 CHORE"` (본문: `.github/ISSUE_TEMPLATE/기타-수정.md`를 읽어서 그 구조를 따르되 PR 내용 요약으로 채움) → 출력 URL 끝의 숫자를 이후 단계에서 `<배포 이슈 번호>`로 사용
   - 실패 → run-id 확인: `gh run list --branch dev --workflow ci-ghcr.yml --commit $MERGE_SHA --limit 1 --json databaseId --jq '.[0].databaseId'` → `gh run view <run-id> --log-failed` 로그 요약을 반환하고 **서브에이전트 종료**
4. 배포 PR 생성:
   - `<배포 PR 번호>`가 전달된 경우 → 해당 번호를 재사용
   - 전달되지 않은 경우 → `.github/PULL_REQUEST_TEMPLATE.md`를 읽어서 placeholder를 채운 뒤 → `gh pr create --base main --head dev --title "[CHORE/#배포이슈번호] 배포"` (본문에 `close #<배포이슈번호>` 포함) → 출력 URL 끝의 숫자를 이후 단계에서 `<배포 PR 번호>`로 사용
5. 배포 PR 체크 폴링 (60초 간격, 최대 15분) — 다음 2개 체크 모두 통과 필요:
   - `build-and-push` (CI - GHCR Build & Push)
   - `SonarCloud Code Analysis` (SonarCloud GitHub App)
   - 확인 명령어: `gh pr checks <배포 PR 번호> --json name,state --jq '[.[] | select(.name == "build-and-push" or .name == "SonarCloud Code Analysis")] | (length == 2 and all(.[]; .state == "SUCCESS"))'` → `true`이면 통과
   - 폴링 방법:
     ```bash
     SECONDS=0
     until [ "$(gh pr checks <배포 PR 번호> --json name,state --jq '[.[] | select(.name == "build-and-push" or .name == "SonarCloud Code Analysis")] | (length == 2 and all(.[]; .state == "SUCCESS"))')" = "true" ]; do
       if [ "$(gh pr checks <배포 PR 번호> --json name,state --jq '[.[] | select(.name == "build-and-push" or .name == "SonarCloud Code Analysis")] | any(.[]; .state != "PENDING" and .state != "SUCCESS")')" = "true" ]; then echo "CHECK FAILED"; break; fi
       if [ $SECONDS -ge 900 ]; then echo "PR CHECKS TIMEOUT"; exit 1; fi
       sleep 60
     done
     ```
6. 체크 결과:
   - 모두 통과 → 배포 PR 번호와 배포 이슈 번호를 반환하고 **서브에이전트 종료**
   - 실패 → 실패한 체크 이름과 상세 내용, **배포 이슈 번호와 배포 PR 번호**를 반환하고 **서브에이전트 종료**

---

## Opus 검토: main 머지 승인

서브에이전트 1이 반환한 결과를 Opus(메인 에이전트)가 검토한다.
- 실패 시 → **「파이프라인 실패 시 Opus 전환 규칙」 적용**: 실패 내용을 Opus로 분석하고, 해당 섹션의 재시작 전략에 따라 진행한다.
- 체크 통과 시 → CI/PR 체크 결과를 확인하고 Phase 7b-8로 진행한다 (사용자 대기 없음)

## Phase 7b-8: main 머지 → 배포 (Sonnet 서브에이전트 2)

Opus 검토 완료 후, **Agent tool로 서브에이전트를 호출**하여 아래를 위임한다 (모델: CI/CD 실패 전이면 `"sonnet"`, 실패 후이면 `"opus"` — 「파이프라인 실패 시 Opus 전환 규칙」 참조).
서브에이전트 prompt에는 반드시 다음 정보를 포함한다:
- 배포 PR 번호, 배포 이슈 번호, 브랜치명
- 아래 Phase 7b ~ Phase 8의 전체 절차
- 모든 `gh`/`git` 명령 실패 시 에러 내용을 반환하고 서브에이전트 종료
- 이슈/PR 생성 시 GitHub 템플릿 형식 준수
### Phase 7b: main 머지

1. `gh pr merge <배포PR번호> --merge`
   - 충돌(`CONFLICTING`) 발생 시 에러 내용을 반환하고 **서브에이전트 종료** (메인 에이전트가 충돌을 해결한다)

### Phase 8: CD & 정리

1. main push → CD(`CD - OCI A1.Flex Deploy (Main)`) 자동 트리거
2. 머지 커밋 SHA 확인: `CD_SHA=$(gh pr view <배포PR번호> --json mergeCommit --jq '.mergeCommit.oid')`
3. CD 폴링 (60초 간격, 최대 20분):
   ```bash
   SECONDS=0
   until [ "$(gh run list --branch main --workflow cd-oci-a1-main.yml --commit $CD_SHA --limit 1 --json status --jq '.[0].status')" = "completed" ]; do
     if [ $SECONDS -ge 1200 ]; then echo "CD TIMEOUT"; exit 1; fi
     sleep 60
   done
   gh run list --branch main --workflow cd-oci-a1-main.yml --commit $CD_SHA --limit 1 --json conclusion --jq '.[0].conclusion'
   ```
   - timeout 시 에러 내용을 반환하고 **서브에이전트 종료**
4. CD 결과:
   - 성공 → 아래 cleanup을 순서대로 시도하되, **각 명령이 실패해도 중단하지 않고 계속 진행**한다 (실패 내역만 기록):
     1. `gh issue close <배포이슈번호>` (default branch가 dev라 자동 완료 안 됨)
     2. `git branch -D "<브랜치명>"`
     3. `git push origin --delete "<브랜치명>"` (이미 삭제된 경우 무시 — GitHub auto-delete head branches 설정 대응)
     4. 사용된 워크트리 정리: `.claude/worktrees/` 내 에이전트 디렉토리를 `git worktree remove <path> --force`로 제거 후 `git worktree prune` 실행. 이후 빈 디렉토리가 남아 있으면 `rm -rf .claude/worktrees/agent-*`로 삭제하고, `.claude/worktrees/` 자체가 비어 있으면 `rmdir .claude/worktrees`로 제거한다.
   - 실패 → run-id 확인: `gh run list --branch main --workflow cd-oci-a1-main.yml --commit $CD_SHA --limit 1 --json databaseId --jq '.[0].databaseId'` → `gh run view <run-id> --log-failed`로 workflow 로그 요약과 **배포 이슈 번호**를 반환하고 **서브에이전트 종료**
5. 최종 결과 보고: 배포 성공 여부와 함께 **cleanup 실패 내역이 있으면 포함**하여 반환 (배포 성공 + cleanup 실패는 파이프라인 실패로 취급하지 않는다)

## 파이프라인 실패 시 Opus 전환 규칙

Phase 6~8에서 파이프라인 실패가 발생하면:

1. 이후 모든 서브에이전트를 `model: "opus"`로 호출한다 (워크플로우 종료까지 유지)
2. 아래 재시작 매핑에 따라 재시작 Phase를 결정한다. **코드 수정 또는 dev push가 수반되면 반드시 Phase 7a (CI + PR 체크 대기)를 다시 거쳐야 한다 — CI 검증 없는 배포는 금지한다.**

   | 실패 시점 | 원인 | 재시작 Phase | 비고 |
   |-----------|------|-------------|------|
   | Phase 6-5 | dev PR CI 실패 | 코드 수정 → **Phase 6**부터 | 새 커밋 필요, 새 dev PR 생성 |
   | Phase 6-5 | dev PR 충돌 (`CONFLICTING`) | 충돌 해결 → **Phase 6-5**부터 | dev PR 재머지 시도 |
   | Phase 7a-2 | CI 실패 (GHCR 빌드) | 코드 수정 → **Phase 6**부터 | 새 커밋 필요, 새 dev PR 생성 |
   | Phase 7a-5/6 | 배포 PR 체크 실패 | 코드 수정 → **Phase 6**부터 | 새 커밋 필요, 새 dev PR 생성 |
   | Phase 7b-1 | 배포 PR 충돌 (`CONFLICTING`) | 충돌 해결 → **Phase 7b**부터 | 배포 PR 재머지 시도 |
   | Phase 8-3/4 | CD 실패 | 코드 수정 → **Phase 6**부터 | 새 커밋 필요, 배포 이슈/PR 재사용 |

3. 재시작 시 새 브랜치가 필요하면 `fix/#원본번호`를 사용한다 (기존 로컬 브랜치가 있으면 삭제 후 생성)
4. default branch가 dev이므로 main에 머지된 PR의 `close #N`은 이슈를 자동으로 닫지 않는다 — 배포 이슈는 명시적으로 닫아야 한다

## 파괴적 DB 마이그레이션 2단계 배포 원칙

파괴적 마이그레이션은 앱 이미지 롤백 시 Flyway가 적용한 스키마는 되돌아가지 않으므로, Hibernate `validate` 실패로 롤백된 앱도 시작 불가 상태가 된다.

**파괴적 변경 판단 기준**:
- 2단계 필수: `DROP TABLE/COLUMN`, `ALTER TYPE 축소`, `RENAME COLUMN`, `ADD NOT NULL` (기존 데이터에 영향)
- 1단계로 충분: `CREATE TABLE`, `ADD COLUMN`, `ALTER TYPE 확장`, CHECK 제약조건 값 추가

**Phase별 적용 방법**:

- **Phase 1**: 해결책에 파괴적 마이그레이션이 포함되면, 작업을 `[1차 배포]`와 `[2차 배포]`로 분리하여 제시한다.
  ```
  해결책 N: ...
  [1차 배포 — 이번 워크플로우]
  ├─ 작업 N-a [API]   앱 코드에서 기존 스키마 참조 제거
  └─ 작업 N-b [비API] additive 마이그레이션 (있는 경우)
  [2차 배포 — 1차 안정 확인 후 별도 워크플로우]
  └─ 작업 N-c [비API] V__drop_xxx.sql 파괴적 마이그레이션
  ```
- **Phase 2~8**: `[1차 배포]` 작업만 실행한다. `[2차 배포]` 작업은 실행하지 않는다.
- **Phase 8 완료 후**: 2차 배포 작업 내용을 구체적으로 안내한다.
  ```
  1차 배포 완료. 안정 확인 후 2차 배포(파괴적 마이그레이션)가 필요합니다.

  2차 배포 작업:
  - 작업 N-c [비API] V__drop_notification_table.sql 추가
  (... Phase 1에서 제시한 [2차 배포] 작업 목록 전체)

  /problem 실행 후 위 내용을 전달해주세요.
  ```

## 환경변수 추가 체크리스트

작업 중 **새 환경변수**를 도입하는 경우, Phase 5 통합 검토에서 아래 체크리스트를 모두 확인한다. 하나라도 누락되면 프로덕션 앱이 시작 시 NPE/실패한다.

### 전달 경로

```
GitHub Secrets → CD workflow env → SSH envs 파라미터 → Docker Compose environment → 컨테이너 → Spring ${}
```

### 로컬 개발 환경

| # | 파일 | 작업 |
|---|------|------|
| 1 | `src/main/resources/application.yml` | `${NEW_VAR}` 참조 추가 |
| 2 | 메인 Application 클래스 | `System.setProperty("NEW_VAR", dotenv.get("NEW_VAR"))` 추가 (dotenv 사용 시) |
| 3 | `.env` | 로컬 개발용 값 추가 |

### 프로덕션 배포 환경

프로젝트의 CD 워크플로우와 Docker Compose 파일을 모두 확인하여 환경변수 전달 경로를 빠짐없이 추가한다.

| # | 대상 | 작업 |
|---|------|------|
| 4 | 각 CD 워크플로우 (`.github/workflows/cd-*.yml`) | `jobs.<job>.env`에 `NEW_VAR: ${{ secrets.NEW_VAR }}` 추가 |
| 5 | 위 파일 동일 | `steps[SSH].with.envs` 파라미터 목록에 `NEW_VAR` 추가 |
| 6 | 각 Docker Compose 파일 (`docker/**/compose*.yml`) | app 서비스 `environment`에 `NEW_VAR: ${NEW_VAR}` 추가 |

### GitHub Secrets 확인

`gh secret list`로 시크릿 등록 여부를 확인하고, 미등록 시 사용자에게 등록을 요청한다.

> **제외 대상**: 앱이 아닌 서비스만 배포하는 워크플로우/Compose는 앱 환경변수 불필요 — 프로젝트의 인프라 전용 워크플로우(모니터링, 로그 수집, 데이터 서비스 등)는 대상에서 제외한다.

## 규칙

- 해결책 제시 시 코드 변경 없이 분석만 수행한다
- 사용자가 선택하지 않은 해결책은 절대 적용하지 않는다
- 하나의 해결책 안에서도 `[API]`/`[비API]` 작업을 반드시 분리하여 제시한다
- `[API]` 작업의 테스트 실패 시 구현 코드를 수정한다 (테스트가 명세이므로 테스트를 수정하지 않는다)
- 기존 테스트 패턴(어노테이션, Mock 전략, Helper 구조)을 반드시 따른다
- 병렬 실행 시 각 워크트리는 완전히 독립적으로 작업한다
- 모든 `gh`/`git` 명령 실패 시 에러 내용 사용자에게 보고
- 이슈/PR 생성 시 GitHub 템플릿 형식 준수
- **파이프라인 실패 시 Opus 전환 규칙을 반드시 따른다** (위 섹션 참조)
- **`dev` 브랜치에서 `git pull origin main`, `git merge main`, `git merge origin/main` 등 main을 dev로 merge하는 행위는 절대 금지한다.** 이 프로젝트는 dev → main 단방향 플로우이므로 main에 dev에 없는 커밋이 존재하지 않는다. squash merge 환경에서 main을 dev로 끌어오면 커밋 중복, 불필요한 merge 커밋, 충돌이 발생한다. 어떤 Phase에서도 자의적으로 브랜치 동기화를 시도하지 않는다.
