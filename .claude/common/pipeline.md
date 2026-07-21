# /pipeline — 배포 파이프라인

커밋된 변경사항을 dev PR → CI → main 머지 → CD 배포까지 자동화한다. `/problem`, `/ship`에서 공통으로 사용한다.
브랜치명에 `#`이 포함되므로 모든 git/gh 명령에서 브랜치명은 따옴표로 감싼다.

**실행 주체**: 전 과정(Step 1~4)을 메인 세션이 직접 수행한다. 서브에이전트에 위임하지 않는다 — 파이프라인은 "액션 → CI/체크 폴링 → 다음 액션"의 반복인데, 서브에이전트 안에서 백그라운드 폴링을 돌리면 완료 후 재개가 안 돼 대기 지점에서 멈춘다(실측). 메인 세션의 `run_in_background` Bash는 완료 시 세션을 확실히 재호출한다.

> **브랜치 전략 전제**: 이 파이프라인은 `dev` → `main` **단방향 플로우** + default branch가 `dev`인 환경을 전제로 한다. dev PR(작업 브랜치→dev, squash merge) → CI → 배포 PR(dev→main, merge) → CD 순서다. 브랜치 이름이나 흐름이 다르면 프로젝트에 맞게 조정한다.

## Preflight: 워크플로우 탐색

파이프라인 실행 전, `.github/workflows/` 디렉토리를 탐색하여 다음을 파악하고 이후 Step에서 사용한다:

- **CI 워크플로우**: dev 브랜치 push/PR 시 트리거되는 워크플로우 **파일명**과 dev PR에 뜨는 **CI check 이름**
- **CD 워크플로우**: main 브랜치 push 시 트리거되는 워크플로우 **파일명**과 job 이름
- **배포 PR 필수 체크**: 배포 PR(dev→main)에서 통과해야 하는 **체크 이름 목록** (CI 빌드 job, 코드 분석 도구 등)
- **이슈/PR 템플릿**: `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md` 존재 여부와 형식

아래 절차의 워크플로우 파일명·체크명 placeholder는 여기서 파악한 실제 값으로 치환한다.

## 폴링 실행 규칙

CI/CD·PR 체크 대기는 모두 **`run_in_background: true` Bash + `while` 루프**로 실행한다 (포그라운드 `sleep` 차단, Monitor 도구 금지 — 단일 완료 대기에 부적합).
- 루프는 성공·실패·타임아웃 **모든 종료 상태에서 exit**하고, 종료 직전 결과 마커 1줄을 `echo`한다. 완료 알림을 받은 뒤 출력 파일의 마커·종료코드로 분기한다.
- 루프 내 `gh`/`git`은 `2>/dev/null || true`로 감싼다. 폴링 간격은 30초 이상.
- **알림이 애매하거나 오래 소식이 없으면 추측·무한 대기 말고 즉시 `gh pr view/checks`·`gh run list`로 실제 상태를 확인**한 뒤 분기한다.

## Step 1: 커밋 & PR & 머지 (dev)

1. `git status --short` — 커밋 안 된 변경이 있으면 `git diff --cached`로 내용 파악 후 `git add -A` → 커밋 (메시지 끝에 `Co-Authored-By: Claude <모델명> <noreply@anthropic.com>`). 이미 커밋됐으면 스킵.
2. `git pull origin dev --rebase` — 충돌 시 `git rebase --abort` 후 보고하고 중단.
3. `git push --force-with-lease -u origin "<브랜치명>"`
4. `.github/PULL_REQUEST_TEMPLATE.md` placeholder를 채워 `gh pr create --base dev --head "<브랜치명>" --title "[TYPE/#이슈번호] 설명"`. 출력 URL 끝 숫자가 `<dev PR 번호>`.
5. 머지 가능 + CI 확인 폴링 (30초 간격, 최대 10분) → `DEVCI_DONE` 마커로 판단 (`<CI check 이름>`은 Preflight에서 파악한 값):
   ```bash
   SECONDS=0
   while :; do
     MERGEABLE=$(gh pr view <dev PR 번호> --json mergeable --jq '.mergeable' 2>/dev/null || true)
     CI_STATE=$(gh pr checks <dev PR 번호> --json name,state --jq '[.[] | select(.name == "<CI check 이름>")][0].state' 2>/dev/null || true)
     if [ "$MERGEABLE" = "MERGEABLE" ] && [ "$CI_STATE" = "SUCCESS" ]; then break; fi
     if [ "$CI_STATE" = "FAILURE" ] || [ "$MERGEABLE" = "CONFLICTING" ]; then break; fi
     if [ $SECONDS -ge 600 ]; then MERGEABLE="TIMEOUT"; break; fi
     sleep 30
   done
   echo "DEVCI_DONE mergeable=$MERGEABLE ci=$CI_STATE"
   ```
   - `MERGEABLE` + `SUCCESS` → `gh pr merge <dev PR 번호> --squash` (--auto 금지)
   - `CONFLICTING` / CI `FAILURE` / `TIMEOUT` → 에러·로그 요약을 보고하고 중단
6. `git checkout dev && git pull origin dev`
7. `MERGE_SHA=$(gh pr view <dev PR 번호> --json mergeCommit --jq '.mergeCommit.oid')`

## Step 2: CI & 배포 PR & 체크 대기

1. dev push → CI 워크플로우 자동 트리거 (Preflight에서 파악한 `<CI 워크플로우 파일>`).
2. CI 폴링 (60초 간격, 최대 15분) → `CI_RESULT` 마커:
   ```bash
   SECONDS=0
   while :; do
     STATUS=$(gh run list --branch dev --workflow <CI 워크플로우 파일> --commit $MERGE_SHA --limit 1 --json status --jq '.[0].status' 2>/dev/null || true)
     [ "$STATUS" = "completed" ] && break
     if [ $SECONDS -ge 900 ]; then echo "CI_RESULT TIMEOUT"; exit 0; fi
     sleep 60
   done
   CONCLUSION=$(gh run list --branch dev --workflow <CI 워크플로우 파일> --commit $MERGE_SHA --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || true)
   echo "CI_RESULT conclusion=$CONCLUSION"
   ```
   - `conclusion=success`가 아니거나 `TIMEOUT`이면 실패 처리: run-id(`... --json databaseId --jq '.[0].databaseId'`) → `gh run view <run-id> --log-failed` 요약을 보고하고 중단.
3. CI 성공 → 배포 이슈: 이미 있으면 재사용, 없으면 이슈 템플릿(예: `.github/ISSUE_TEMPLATE/기타-수정.md`) 구조로 `gh issue create --title "[CHORE] 배포" --label "🔩 CHORE"`. 출력 URL 끝 숫자가 `<배포 이슈 번호>`.
4. 배포 PR: 이미 있으면 재사용, 없으면 `.github/PULL_REQUEST_TEMPLATE.md`를 채워 `gh pr create --base main --head dev --title "[CHORE/#배포이슈번호] 배포"` (본문에 `close #<배포이슈번호>`). 출력 URL 끝 숫자가 `<배포 PR 번호>`.
5. 배포 PR 체크 폴링 (60초 간격, 최대 15분) — Preflight에서 파악한 **배포 PR 필수 체크가 모두 SUCCESS**여야 함 → `DEPLOYPR_DONE` 마커 (아래는 필수 체크가 2개인 예시; `select` 조건과 `length == N`을 실제 체크 수에 맞게 조정):
   ```bash
   SECONDS=0
   while :; do
     S=$(gh pr checks <배포 PR 번호> --json name,state --jq '[.[] | select(.name == "<체크1>" or .name == "<체크2>")]' 2>/dev/null || true)
     PASS=$(echo "$S" | jq '(length == 2 and all(.[]; .state == "SUCCESS"))' 2>/dev/null || true)
     FAIL=$(echo "$S" | jq 'any(.[]; .state != "PENDING" and .state != "SUCCESS")' 2>/dev/null || true)
     [ "$PASS" = "true" ] && { echo "DEPLOYPR_DONE result=PASS"; break; }
     [ "$FAIL" = "true" ] && { echo "DEPLOYPR_DONE result=FAIL"; break; }
     if [ $SECONDS -ge 900 ]; then echo "DEPLOYPR_DONE result=TIMEOUT"; break; fi
     sleep 60
   done
   ```
   - `PASS` → Step 3 진행 / `FAIL`·`TIMEOUT` → 실패한 체크와 배포 PR·이슈 번호를 보고하고 중단.

## Step 3: main 머지

1. `gh pr merge <배포PR번호> --merge`
   - 충돌(`CONFLICTING`) 발생 시 — **단방향 플로우 전제 위반 신호** (main에 dev에 없는 커밋 존재). "main에 직접 커밋이 추가된 것으로 보입니다. main 히스토리를 확인해주세요."를 보고하고 **즉시 중단**한다 (AI 자동 해결 금지).

## Step 4: CD & 정리

1. main push → CD 워크플로우 자동 트리거 (Preflight에서 파악한 `<CD 워크플로우 파일>`).
2. `CD_SHA=$(gh pr view <배포PR번호> --json mergeCommit --jq '.mergeCommit.oid')`
3. CD 폴링 (60초 간격, 최대 20분) → `CD_RESULT` 마커:
   ```bash
   SECONDS=0
   while :; do
     STATUS=$(gh run list --branch main --workflow <CD 워크플로우 파일> --commit $CD_SHA --limit 1 --json status --jq '.[0].status' 2>/dev/null || true)
     [ "$STATUS" = "completed" ] && break
     if [ $SECONDS -ge 1200 ]; then echo "CD_RESULT TIMEOUT"; exit 0; fi
     sleep 60
   done
   CONCLUSION=$(gh run list --branch main --workflow <CD 워크플로우 파일> --commit $CD_SHA --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || true)
   echo "CD_RESULT conclusion=$CONCLUSION"
   ```
   - `TIMEOUT`이거나 `conclusion=success`가 아니면 아래 4의 실패 분기로 처리.
4. CD 결과:
   - 성공 → 아래 cleanup을 순서대로 시도하되 **각 명령이 실패해도 중단하지 않고 계속 진행**(실패 내역만 기록):
     1. `gh issue close <배포이슈번호>` (default branch가 dev라 자동 완료 안 됨)
     2. `git branch -D "<브랜치명>"`
     3. `git push origin --delete "<브랜치명>"` (이미 삭제됐으면 무시)
     4. 워크트리 정리: `.claude/worktrees/` 내 디렉토리를 `git worktree remove <path> --force` 후 `git worktree prune`. 빈 디렉토리가 남으면 `rm -rf .claude/worktrees/agent-*`, `.claude/worktrees/`가 비면 `rmdir`.
   - 실패 → run-id(`... --json databaseId --jq '.[0].databaseId'`) → `gh run view <run-id> --log-failed` 요약과 배포 이슈 번호를 보고하고 중단.
5. 최종 보고: 배포 성공 여부 + cleanup 실패 내역(있으면). 배포 성공 + cleanup 실패는 파이프라인 실패로 취급하지 않는다.

## 실패 시 재시작 규칙

재시작 지점은 아래 매핑을 따른다. **코드 수정·dev push가 수반되면 반드시 Step 2(CI + PR 체크)를 다시 거친다 — CI 검증 없는 배포 금지.**

| 실패 시점 | 원인 | 재시작 | 비고 |
|-----------|------|--------|------|
| Step 1-5 | dev PR CI 실패 | 코드 수정 → **Step 1** | 새 커밋, 새 dev PR |
| Step 1-5 | dev PR 충돌 | 충돌 해결 → **Step 1-5** | dev PR 재머지 |
| Step 2-2 | CI(빌드) 실패 | 코드 수정 → **Step 1** | 새 커밋, 새 dev PR |
| Step 2-5 | 배포 PR 체크 실패 | 코드 수정 → **Step 1** | 새 커밋, 새 dev PR |
| Step 3-1 | 배포 PR 충돌 | **즉시 중단 → 사용자 보고** | 단방향 전제 위반, AI 자율 해결 금지 |
| Step 4 | CD 실패 | 코드 수정 → **Step 1** | 배포 이슈/PR 재사용 |

- 재시작에 새 브랜치가 필요하면 `fix/#원본번호` 사용 (기존 로컬 브랜치는 삭제 후 생성).
- default branch가 dev이므로 main 머지 PR의 `close #N`은 이슈를 자동으로 닫지 않는다 — 배포 이슈는 명시적으로 닫는다.

## 파괴적 DB 마이그레이션 2단계 배포 원칙

파괴적 마이그레이션은 앱 이미지 롤백 시 DB 마이그레이션 도구가 적용한 스키마는 되돌아가지 않아, 스키마 검증 실패로 롤백된 앱도 시작 불가가 된다.

- **2단계 필수**: `DROP TABLE/COLUMN`, `ALTER TYPE 축소`, `RENAME COLUMN`, `ADD NOT NULL`
- **1단계로 충분**: `CREATE TABLE`, `ADD COLUMN`, `ALTER TYPE 확장`, CHECK 값 추가

파괴적 변경은 2단계로 분리 배포한다:
- **1차**: 앱 코드에서 기존 스키마 참조 제거 + additive 마이그레이션(있으면)
- **2차**: 파괴적 마이그레이션 (1차 안정 확인 후 별도 워크플로우)

호출자(`/problem`, `/ship`)는 검증 단계에서 파괴적 마이그레이션을 감지해 1차 범위만 파이프라인에 넘기고, 완료 후 2차 작업을 사용자에게 안내한다.

## 환경변수 추가 체크리스트

**새 환경변수** 도입 시 배포 전 전달 경로 전체를 확인한다 (누락 시 프로덕션 앱 시작 실패). 전달 경로는 프로젝트마다 다르므로, CD 워크플로우를 읽어 시크릿이 컨테이너까지 전달되는 경로를 파악한 뒤 모든 경유 지점에 누락 없이 추가한다.

일반적인 경로: `GitHub Secrets → CD workflow env → (SSH/배포 스크립트 envs) → 배포 구성(Compose 등) environment → 컨테이너 → 앱 설정 참조`.

확인 항목:
1. **앱 설정 파일**: 환경변수 참조 추가 (예: Spring `application.yml`의 `${NEW_VAR}`)
2. **로컬 로딩 지점**: 로컬에서 `.env` 등을 읽어 시스템 프로퍼티로 주입하는 부트스트랩 코드가 있으면 추가
3. **로컬 환경변수 파일**: `.env` 등에 로컬 값 추가
4. **CD 워크플로우**: `.github/workflows/`의 각 CD 워크플로우 `env`에 `NEW_VAR: ${{ secrets.NEW_VAR }}` + (SSH/배포 스텝이 있으면) envs 전달 목록에 `NEW_VAR` 추가
5. **배포 구성 파일**: Docker Compose 등 각 배포 구성의 app `environment`에 `NEW_VAR: ${NEW_VAR}` 추가
6. **GitHub Secrets**: `gh secret list`로 등록 여부 확인, 미등록 시 사용자에게 요청

> 앱이 아닌 부가 서비스(모니터링·로그·데이터 등)만 배포하는 워크플로우/Compose에는 앱 환경변수가 불필요하다 — 대상에서 제외한다.

## 규칙

- 모든 `gh`/`git` 실패 시 에러 내용을 사용자에게 보고한다.
- 이슈/PR 생성 시 GitHub 템플릿 형식을 준수한다.
- **실패 시 재시작 규칙을 반드시 따른다.**
- **`dev`에서 main을 dev로 merge/pull 하는 행위 절대 금지** (`git pull origin main`, `git merge main` 등). dev → main 단방향이라 main에 dev에 없는 커밋이 없다. 역으로 배포 PR(dev→main)에서 `CONFLICTING`이 나면 전제 위반이므로 즉시 중단하고 사용자에게 main 히스토리 확인을 요청한다.
