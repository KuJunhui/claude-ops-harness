# /pipeline — 배포 파이프라인

커밋된 변경사항을 dev PR → CI → main 머지 → CD 배포까지 자동화한다.
`/problem`, `/ship`에서 공통으로 사용하는 배포 파이프라인이다.
브랜치명에 `#`이 포함되므로, 모든 git/gh 명령에서 브랜치명은 반드시 따옴표로 감싼다.

## Preflight: 워크플로우 탐색

파이프라인 실행 전, `.github/workflows/` 디렉토리를 탐색하여 다음을 파악한다:

- **CI 워크플로우**: dev 브랜치 push/PR 시 트리거되는 워크플로우 파일명과 job/check 이름
- **CD 워크플로우**: main 브랜치 push 시 트리거되는 워크플로우 파일명과 job 이름
- **PR 체크**: 배포 PR에서 통과해야 하는 체크 이름 목록 (CI job, 코드 분석 도구 등)

이 정보를 이후 Step에서 사용한다.

## Step 1-2: 커밋 → PR 체크 (Sonnet 서브에이전트 1)

**Agent tool로 서브에이전트를 호출**하여 아래를 위임한다 (모델: 파이프라인 실패 전이면 `"sonnet"`, 실패 후이면 `"opus"` — 「실패 시 Opus 전환 규칙」 참조).
서브에이전트 prompt에는 반드시 다음 정보를 포함한다:
- 브랜치명, 타입, 이슈번호
- 변경사항 요약
- Preflight에서 파악한 CI/CD 워크플로우 정보 (파일명, check 이름)
- 아래 Step 1 ~ Step 2의 전체 절차
- 모든 `gh`/`git` 명령 실패 시 에러 내용을 반환하고 서브에이전트 종료
- 이슈/PR 생성 시 GitHub 템플릿 형식 준수

### Step 1: 커밋 & PR & 머지 (dev)

1. `git status --short`로 커밋되지 않은 변경사항이 있는지 확인한다.
   - **변경사항이 있으면**: `git add -A` → 커밋 (메시지: 변경 내용 간결 요약, 끝에 `Co-Authored-By: Claude <사용 모델명> <noreply@anthropic.com>` — 예: Sonnet 사용 시 `Claude Sonnet 4.6`, Opus 사용 시 `Claude Opus 4.6`)
     - 커밋 메시지 작성을 위해 `git diff --cached --stat`과 `git diff --cached`로 변경 내용 파악
   - **변경사항이 없으면** (이미 커밋 완료): 커밋 스킵
2. `git pull origin dev --rebase` — 최신 dev와 동기화 (충돌 시 `git rebase --abort` 실행 후 에러 내용을 반환하고 **서브에이전트 종료**)
3. `git push --force-with-lease -u origin "<브랜치명>"`
4. `.github/PULL_REQUEST_TEMPLATE.md`를 읽어서 placeholder를 채운 뒤 → `gh pr create` — base: `dev`, head: `"<브랜치명>"`
   - 제목: `[TYPE/#이슈번호] 설명`
   - 출력 URL 끝의 숫자가 PR 번호 → 이후 단계에서 `<dev PR 번호>`로 사용
5. 머지 가능 여부 및 CI 체크 확인 (30초 간격, 최대 10분):
   - `gh pr checks`로 dev PR의 CI 체크 상태를 폴링한다
   - 전달받은 CI check 이름으로 성공 여부를 판단한다
   - `MERGEABLE` + CI 통과 → `gh pr merge <dev PR 번호> --squash` (--auto 사용 금지)
   - `CONFLICTING` → 에러 내용을 반환하고 **서브에이전트 종료**
   - CI 실패 → 실패 로그를 반환하고 **서브에이전트 종료**
   - 타임아웃 → 에러 내용을 반환하고 **서브에이전트 종료**
6. 머지 후: `git checkout dev && git pull origin dev`
7. 머지 커밋 SHA 저장: `MERGE_SHA=$(gh pr view <dev PR 번호> --json mergeCommit --jq '.mergeCommit.oid')` — 이후 CI 폴링에 사용

### Step 2: CI & 배포 PR & 체크 대기

1. dev push → CI 자동 트리거
2. CI 폴링 (60초 간격, 최대 15분):
   - 전달받은 CI 워크플로우 파일명으로 `gh run list --branch dev --workflow <CI워크플로우> --commit $MERGE_SHA`를 폴링한다
   - timeout 시 에러 내용을 반환하고 **서브에이전트 종료**
3. CI 결과:
   - 성공:
     - `<배포 이슈 번호>`가 전달된 경우 → 해당 번호를 재사용
     - 전달되지 않은 경우 → 배포 이슈 생성: `gh issue create --title "[CHORE] 배포" --label "🔩 CHORE"` (본문: `.github/ISSUE_TEMPLATE/기타-수정.md`를 읽어서 그 구조를 따르되 PR 내용 요약으로 채움) → 출력 URL 끝의 숫자를 이후 단계에서 `<배포 이슈 번호>`로 사용
   - 실패 → `gh run view <run-id> --log-failed` 로그 요약을 반환하고 **서브에이전트 종료**
4. 배포 PR 생성:
   - `<배포 PR 번호>`가 전달된 경우 → 해당 번호를 재사용
   - 전달되지 않은 경우 → `.github/PULL_REQUEST_TEMPLATE.md`를 읽어서 placeholder를 채운 뒤 → `gh pr create --base main --head dev --title "[CHORE/#배포이슈번호] 배포"` (본문에 `close #<배포이슈번호>` 포함) → 출력 URL 끝의 숫자를 이후 단계에서 `<배포 PR 번호>`로 사용
5. 배포 PR 체크 폴링 (60초 간격, 최대 15분):
   - 전달받은 PR 체크 이름 목록으로 모든 체크의 성공 여부를 폴링한다
   - `gh pr checks <배포 PR 번호>`로 확인
6. 체크 결과:
   - 모두 통과 → 배포 PR 번호와 배포 이슈 번호를 반환하고 **서브에이전트 종료**
   - 실패 → 실패한 체크 이름과 상세 내용, **배포 이슈 번호와 배포 PR 번호**를 반환하고 **서브에이전트 종료**

---

## Opus 검토: main 머지 승인

서브에이전트 1이 반환한 결과를 메인 에이전트가 검토한다.
- 실패 시 → **「실패 시 Opus 전환 규칙」 적용**: 실패 내용을 분석하고, 해당 섹션의 재시작 전략에 따라 진행한다.
- 체크 통과 시 → CI/PR 체크 결과를 확인하고 Step 3-4로 진행한다 (사용자 대기 없음)

## Step 3-4: main 머지 → 배포 (Sonnet 서브에이전트 2)

검토 완료 후, **Agent tool로 서브에이전트를 호출**하여 아래를 위임한다 (모델: 파이프라인 실패 전이면 `"sonnet"`, 실패 후이면 `"opus"` — 「실패 시 Opus 전환 규칙」 참조).
서브에이전트 prompt에는 반드시 다음 정보를 포함한다:
- 배포 PR 번호, 배포 이슈 번호, 브랜치명
- Preflight에서 파악한 CD 워크플로우 정보
- 아래 Step 3 ~ Step 4의 전체 절차
- 모든 `gh`/`git` 명령 실패 시 에러 내용을 반환하고 서브에이전트 종료
- 이슈/PR 생성 시 GitHub 템플릿 형식 준수

### Step 3: main 머지

1. `gh pr merge <배포PR번호> --merge`
   - 충돌(`CONFLICTING`) 발생 시 — **단방향 플로우 전제 위반 신호** (dev→main에서 충돌은 main에 dev에 없는 커밋이 존재한다는 의미). 에러 내용과 함께 "main 브랜치에 직접 커밋이 추가된 것으로 보입니다. main 히스토리를 확인해주세요."를 반환하고 **서브에이전트 종료** (메인 에이전트도 자동 해결을 시도하지 않고 사용자에게 보고한다)

### Step 4: CD & 정리

1. main push → CD 자동 트리거
2. 머지 커밋 SHA 확인: `CD_SHA=$(gh pr view <배포PR번호> --json mergeCommit --jq '.mergeCommit.oid')`
3. CD 폴링 (60초 간격, 최대 20분):
   - 전달받은 CD 워크플로우 파일명으로 `gh run list --branch main --workflow <CD워크플로우> --commit $CD_SHA`를 폴링한다
   - timeout 시 에러 내용을 반환하고 **서브에이전트 종료**
4. CD 결과:
   - 성공 → 아래 cleanup을 순서대로 시도하되, **각 명령이 실패해도 중단하지 않고 계속 진행**한다 (실패 내역만 기록):
     1. `gh issue close <배포이슈번호>` (default branch가 dev라 자동 완료 안 됨)
     2. `git branch -D "<브랜치명>"`
     3. `git push origin --delete "<브랜치명>"` (이미 삭제된 경우 무시 — GitHub auto-delete head branches 설정 대응)
     4. 사용된 워크트리 정리: `.claude/worktrees/` 내 에이전트 디렉토리를 `git worktree remove <path> --force`로 제거 후 `git worktree prune` 실행. 이후 빈 디렉토리가 남아 있으면 `rm -rf .claude/worktrees/agent-*`로 삭제하고, `.claude/worktrees/` 자체가 비어 있으면 `rmdir .claude/worktrees`로 제거한다.
   - 실패 → `gh run view <run-id> --log-failed`로 workflow 로그 요약과 **배포 이슈 번호**를 반환하고 **서브에이전트 종료**
5. 최종 결과 보고: 배포 성공 여부와 함께 **cleanup 실패 내역이 있으면 포함**하여 반환 (배포 성공 + cleanup 실패는 파이프라인 실패로 취급하지 않는다)

## 실패 시 Opus 전환 규칙

파이프라인 실패가 발생하면:

1. 이후 모든 서브에이전트를 `model: "opus"`로 호출한다 (워크플로우 종료까지 유지)
2. 아래 재시작 매핑에 따라 재시작 Step을 결정한다. **코드 수정 또는 dev push가 수반되면 반드시 Step 2 (CI + PR 체크 대기)를 다시 거쳐야 한다 — CI 검증 없는 배포는 금지한다.**

   | 실패 시점 | 원인 | 재시작 Step | 비고 |
   |-----------|------|-----------|------|
   | Step 1-5 | dev PR CI 실패 | 코드 수정 → **Step 1**부터 | 새 커밋 필요, 새 dev PR 생성 |
   | Step 1-5 | dev PR 충돌 (`CONFLICTING`) | 충돌 해결 → **Step 1-5**부터 | dev PR 재머지 시도 |
   | Step 2-2 | CI 실패 | 코드 수정 → **Step 1**부터 | 새 커밋 필요, 새 dev PR 생성 |
   | Step 2-5/6 | 배포 PR 체크 실패 | 코드 수정 → **Step 1**부터 | 새 커밋 필요, 새 dev PR 생성 |
   | Step 3-1 | 배포 PR 충돌 (`CONFLICTING`) | **즉시 중단** → 사용자에게 보고 | 단방향 플로우 전제 위반 — main에 dev에 없는 커밋 존재. AI 자율 해결 금지, 사용자가 main 히스토리 확인 필요 |
   | Step 4-3/4 | CD 실패 | 코드 수정 → **Step 1**부터 | 새 커밋 필요, 배포 이슈/PR 재사용 |

3. 재시작 시 새 브랜치가 필요하면 `fix/#원본번호`를 사용한다 (기존 로컬 브랜치가 있으면 삭제 후 생성)
4. default branch가 dev이므로 main에 머지된 PR의 `close #N`은 이슈를 자동으로 닫지 않는다 — 배포 이슈는 명시적으로 닫아야 한다

## 파괴적 DB 마이그레이션 2단계 배포 원칙

DB 마이그레이션 도구가 적용한 스키마 변경은 앱 롤백 시 되돌아가지 않으므로, 파괴적 변경이 포함되면 롤백된 앱이 시작 불가 상태가 될 수 있다.

**파괴적 변경 판단 기준**:
- 2단계 필수: `DROP TABLE/COLUMN`, `ALTER TYPE 축소`, `RENAME COLUMN`, `ADD NOT NULL` (기존 데이터에 영향)
- 1단계로 충분: `CREATE TABLE`, `ADD COLUMN`, `ALTER TYPE 확장`, CHECK 제약조건 값 추가

**적용 방법**:

- 파괴적 마이그레이션이 포함된 변경사항은 반드시 2단계로 분리하여 배포한다:
  - **1차 배포**: 앱 코드에서 기존 스키마 참조 제거 + additive 마이그레이션 (있는 경우)
  - **2차 배포**: 파괴적 마이그레이션 (1차 안정 확인 후 별도 워크플로우)
- 호출자(`/problem`, `/ship`)는 코드 변경/검증 단계에서 파괴적 마이그레이션을 감지하고, 1차 배포 범위만 파이프라인에 전달해야 한다.
- 파이프라인 완료 후, 2차 배포 작업 내용을 구체적으로 안내한다:
  ```
  1차 배포 완료. 안정 확인 후 2차 배포(파괴적 마이그레이션)가 필요합니다.

  2차 배포 작업:
  - 파괴적 마이그레이션 파일 추가

  /problem 또는 /ship 실행 후 위 내용을 전달해주세요.
  ```

## 환경변수 추가 체크리스트

작업 중 **새 환경변수**를 도입하는 경우, 배포 전에 아래 경로를 모두 확인한다. 하나라도 누락되면 프로덕션 앱이 시작 시 실패할 수 있다.

### 확인 항목

1. **앱 설정 파일**: 환경변수 참조 추가 (프로젝트의 설정 파일 탐색)
2. **로컬 환경변수 파일**: `.env` 등 로컬 개발용 값 추가
3. **CD 워크플로우**: `.github/workflows/` 내 CD 워크플로우 파일에 시크릿 매핑 추가
4. **배포 구성 파일**: Docker Compose 등 배포 구성 파일의 environment 섹션에 추가
5. **GitHub Secrets**: `gh secret list`로 시크릿 등록 여부를 확인하고, 미등록 시 사용자에게 등록을 요청한다

> 환경변수 전달 경로는 프로젝트마다 다르다. CD 워크플로우를 읽어서 시크릿이 컨테이너까지 전달되는 경로를 파악한 뒤, 모든 경유 지점에 누락 없이 추가한다.

## 규칙

- 모든 `gh`/`git` 명령 실패 시 에러 내용 사용자에게 보고
- 이슈/PR 생성 시 GitHub 템플릿 형식 준수
- **실패 시 Opus 전환 규칙을 반드시 따른다**
- **`dev` 브랜치에서 `git pull origin main`, `git merge main`, `git merge origin/main` 등 main을 dev로 merge하는 행위는 절대 금지한다.** 이 프로젝트는 dev → main 단방향 플로우이므로 main에 dev에 없는 커밋이 존재하지 않는다. squash merge 환경에서 main을 dev로 끌어오면 커밋 중복, 불필요한 merge 커밋, 충돌이 발생한다. 어떤 Step에서도 자의적으로 브랜치 동기화를 시도하지 않는다. **이 전제의 역도 적용된다: 배포 PR(dev→main)에서 `CONFLICTING`이 발생하면 전제 위반 신호이므로 즉시 중단하고 사용자에게 main 히스토리 확인을 요청한다.**
