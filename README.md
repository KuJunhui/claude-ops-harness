# claude-ops-harness

Java/Spring 프로젝트 운영 중 발생하는 문제를 **분석부터 배포까지 자동화**하는 **멀티 LLM 하네스**입니다.

문제 분석 → 해결책 제시 → (독립 테스트 작성 우선 + 동결) 코드 변경 → 검증 → 배포까지 원스톱으로 처리합니다.
동일한 배포 워크플로우를 **Claude Code · Codex · Gemini** 세 하네스에서 공유하며, 이 중 **Claude Code가 기준(메인) 하네스**입니다 — Codex·Gemini는 같은 중립 명세를 이식한 어댑터입니다.

> **공유용 하네스**: 이 레포는 특정 프로젝트에 종속되지 않도록 빌드/테스트 명령, 테스트 프레임워크, 워크플로우 파일명, 배포 경로를 **추상화**하여 작성되었습니다. Java/Spring 계열 프로젝트라면 별도 수정 없이 설치하여 쓸 수 있고, 빌드 도구(Gradle/Maven)나 CI/CD 워크플로우가 다르면 명령을 프로젝트에 맞게 치환하면 됩니다. `dev` → `main` 단방향 플로우 + default branch가 `dev`인 브랜치 전략을 전제로 합니다.

> **구성 환경**: 이 하네스는 **IntelliJ IDEA + LLM CLI(터미널/IDE 플러그인)** 환경 기준으로 구성·검증되었습니다. IntelliJ의 JetBrains MCP 플러그인이 붙어 있는 상태를 전제로 하며, Codex 테스트 생성 호출은 IDE MCP로 인한 hang을 피하기 위해 MCP를 비운 채(`-c mcp_servers='{}'`) 실행합니다. IDE MCP를 쓰지 않으면 `.codex/config.toml`을 삭제해도 됩니다.

## 하네스별 호출 방법

| 하네스 | `/ship` (배포 자동화) | `/problem` (분석→배포) | 비고 |
|--------|----------------------|------------------------|------|
| **Claude Code** | `/ship` (네이티브 슬래시) | `/problem` (네이티브 슬래시) | PreToolUse 훅으로 민감 파일·동결 테스트 산출물 보호 |
| **Gemini** | `/ship` (네이티브 슬래시) | — | `.gemini/commands/ship.toml` 커스텀 명령 |
| **Codex** | `ship` / `배포해줘` (평문) | — | Codex엔 커스텀 슬래시 명령이 없어 `.codex/skills`의 스킬을 평문으로 호출 |

- `/ship`은 세 하네스 모두 지원합니다.
- `/problem`(분석부터 배포까지 원스톱, 병렬 워크트리 포함)은 **현재 Claude Code 전용**입니다. Codex/Gemini는 병렬 위임·백그라운드 폴링 프리미티브가 없어 `/ship`(단일 흐름 배포)만 제공합니다.
- Codex는 `/ship`처럼 슬래시로 부를 수 없습니다 — `ship` 또는 `배포해줘`처럼 **평문**으로 요청하면 `.codex/skills/ship` 스킬이 발동합니다.

## 아키텍처: 중립 명세 + 하네스 어댑터

절차의 「진실의 원천」은 하네스 중립 명세 한 벌이고, 각 하네스는 얇은 어댑터로 이를 실행합니다.

```
automation/ship.md        ← 하네스 중립 「진실의 원천」 (Preflight → Phase 1~4)
automation/pipeline.md    ← 하네스 중립 배포 파이프라인 (dev PR → CI → main → CD)
   ▲            ▲            ▲
   │            │            │  (각 어댑터가 위 명세를 읽어 실행 + 하네스별 오버라이드)
.claude/…    .codex/…     .gemini/…
```

어댑터가 지정하는 하네스별 차이는 **① 폴링 모드**(백그라운드 vs 포그라운드 블로킹)와 **② 커밋 Co-Author 트레일러**, **③ 안전 규칙 적용 방식**(훅 유무) 세 가지뿐이며, 절차 본문은 공유됩니다.

CI/CD·PR 체크 대기는 루프를 즉석에서 작성하지 않고 `automation/bin/`의 **폴링·게이트 스크립트**(`pr-gate.sh`·`run-wait.sh`)로 실행하며, 어댑터는 그 스크립트의 *실행 모드*만 지정합니다.

| 하네스 | 폴링 모드 (스크립트 실행 방식) | Co-Author 트레일러 |
|--------|-----------|--------------------|
| Claude Code | `automation/bin/` 스크립트를 `run_in_background: true` Bash로 실행 (완료 시 세션 자동 재호출) | `Co-Authored-By: Claude Code <noreply@anthropic.com>` |
| Codex | `automation/bin/` 스크립트를 포그라운드 블로킹 호출로 완료까지 대기 (한 셸 호출) | `Co-Authored-By: Codex <noreply@openai.com>` |
| Gemini | `automation/bin/` 스크립트를 포그라운드 블로킹 호출로 대기 | `Co-Authored-By: Gemini <noreply@google.com>` |

## 포함 파일

| 파일 | 하네스 | 설명 |
|------|--------|------|
| `automation/ship.md` | 공통 | `/ship` 절차 원본 (하네스 중립) |
| `automation/pipeline.md` | 공통 | 배포 파이프라인 원본 (커밋 → dev PR → CI → main 머지 → CD) |
| `automation/bin/` | 공통 | 폴링·게이트 스크립트 — `pr-gate.sh`/`pr-gate.jq`(PR 체크 게이트), `run-wait.sh`(CI/CD run 대기), `sensitive-gate.sh`(민감 파일 커밋 차단), `smoke-test.sh`(게이트 로직 검증). pipeline.md가 참조 |
| `.claude/commands/problem.md` | Claude | `/problem` — 문제 분석부터 배포까지 원스톱 (Claude 전용) |
| `.claude/commands/ship.md` | Claude | `/ship` Claude 어댑터 (→ `automation/ship.md`) |
| `.claude/common/pipeline.md` | Claude | 파이프라인 Claude 어댑터 (→ `automation/pipeline.md`) |
| `.claude/hooks/validate-git-sensitive.sh` | Claude | PreToolUse 훅 — 민감 파일(`.env`, `settings.local.json` 등) 커밋 차단 |
| `.claude/hooks/freeze-test-files.sh` | Claude | PreToolUse 훅 — 동결 테스트 소스·fixture의 Edit/Write 차단 |
| `.claude/settings.json` | Claude | 위 두 훅 등록 |
| `.codex/skills/ship/SKILL.md` | Codex | `ship` 스킬 (평문 호출) |
| `.codex/config.toml` | Codex | (선택) IDE MCP 연결 설정 |
| `.gemini/commands/ship.toml` | Gemini | `/ship` 커스텀 명령 |

> 워크플로우 상태 파일은 `.problem/`(커밋 대상 감사 기준) 및 `.problem/local/`(로컬 전용)에 저장됩니다. `.gitignore`에 `.problem/local/`을 추가하세요.

> **핵심 개념**(테스트 작성자 분리 우선 + 모드 공통 Test-First·동결, 병렬 워크트리, 메인 세션 직접 배포 파이프라인)과 그 **설계 이유**는 이 문서 하단의 [설계 의도](#설계-의도) 섹션에서 다룹니다.

## 설치 방법

### 1. 이 레포 클론

```bash
# 대상 프로젝트와 같은 상위 디렉토리에 클론하는 것을 권장합니다.
git clone https://github.com/KuJunhui/claude-ops-harness.git
```

### 2. 설치 스크립트 실행

```bash
# 대상 프로젝트 루트에서 실행
cd /path/to/your-project
../claude-ops-harness/install.sh          # 전체 하네스 설치
# 또는 특정 하네스만:
../claude-ops-harness/install.sh claude    # Claude만
../claude-ops-harness/install.sh codex     # Codex만
../claude-ops-harness/install.sh gemini    # Gemini만
```

설치가 완료되면 아래 파일들이 대상 프로젝트에 복사됩니다:

```
your-project/
├── automation/
│   ├── ship.md
│   ├── pipeline.md
│   └── bin/{pr-gate.sh, pr-gate.jq, run-wait.sh, sensitive-gate.sh, smoke-test.sh}
├── .claude/
│   ├── settings.json
│   ├── commands/{problem.md, ship.md}
│   ├── common/pipeline.md
│   └── hooks/{validate-git-sensitive.sh, freeze-test-files.sh}
├── .codex/
│   ├── config.toml
│   └── skills/ship/SKILL.md
└── .gemini/
    └── commands/ship.toml
```

### 3. 프로젝트에 맞게 조정

추상화된 명세를 프로젝트 환경에 맞게 치환합니다:

- `automation/pipeline.md`: CI/CD 워크플로우 파일명·체크 이름 (Preflight의 워크플로우 탐색으로 자동 파악되지만, 값을 고정해두면 더 안정적)
- `automation/ship.md`, `.claude/commands/problem.md`: 빌드/테스트 명령, 이슈 템플릿·라벨 컨벤션
- `.codex/config.toml`: IDE MCP 사용 시 URL (미사용이면 삭제)

### 4. 하네스 실행

```bash
cd /path/to/your-project
claude        # → /ship 또는 /problem
# 또는  codex   → 'ship' / '배포해줘'
# 또는  gemini  → /ship
```

## 업데이트 방법

```bash
cd /path/to/claude-ops-harness
git pull

cd /path/to/your-project
../claude-ops-harness/install.sh
```

설치 스크립트를 다시 실행하면 최신 설정으로 덮어씁니다. (기존 `settings.json`·`config.toml`은 `.bak`으로 백업됩니다.)

## `/problem` 사용법 (Claude Code 전용)

문제 분석부터 배포까지 원스톱으로 처리하는 커스텀 명령어입니다.

> **참고**: `/problem`은 Claude Code의 메인 에이전트 **Claude Opus** 기준으로 작성되었습니다.

### 실행 방법

**방법 1: 간단한 문제** — 에러 로그나 문제 내용을 `/problem` 뒤에 바로 붙여넣기

```
/problem [에러 로그 붙여넣기 or 문제 내용]
```

**방법 2: 복잡한 문제** — 먼저 Claude Code와 대화하며 문제와 해결책을 구체화한 뒤 `/problem` 실행

```
# 1. 먼저 대화로 문제 파악
> 로그인 후 토큰 갱신이 안 되는 것 같은데 원인이 뭘까?
> (Claude Code와 대화하며 원인 분석 및 해결 방향 정리)

# 2. 정리가 끝나면 실행
> /problem
```

### 사용자 개입 포인트

프로세스 진행 중 **항상** 사용자가 개입하는 구간은 **2곳**입니다:

1. **해결책 선택** (Phase 1) — Claude Code가 제시한 해결책 중 적용할 번호를 선택
2. **최종 확인** (Phase 5) — 모든 코드 수정 및 테스트 완료 후 결과 확인 → 추가 수정이 필요하면 요청, 문제없으면 OK로 다음 단계(커밋·PR·배포) 진행

아래 2곳은 **조건부**로만 개입이 발생합니다:

- **Codex 인증** (Phase 4) — Codex CLI가 설치돼 있으나 인증이 필요한 경우에만, Codex 모드 진행 / Claude Code 단독 모드 중 선택을 요청 (미설치면 개입 없이 자동으로 Claude Code 단독 모드). 두 모드는 **테스트 작성자만** 다르고 RED 게이트·정성 리뷰·동결·감사 절차는 동일
- **TEST-DISPUTE** (Phase 4~5, 순차 실행 시) — 구현 중 동결 테스트가 스펙을 잘못 해석했다고 판단되면 구현 수정 / 테스트 재파생 / 스펙 해석 확정을 요청 (병렬 실행 시에는 대기 없이 보고 후 통합 단계에서 처리)

위 지점을 제외한 나머지 과정(브랜치 생성, 모드별 테스트 생성·검증·동결, 코드 변경, 테스트, PR, CI/CD, 배포)은 자동으로 진행됩니다.

## `/ship` 사용법 (Claude Code · Codex · Gemini)

코드 수정이 이미 완료된 상태에서, 검증과 배포만 자동으로 처리합니다. `/problem`과 달리 문제 분석이나 코드 변경을 수행하지 않습니다.

### 실행 방법

**방법 1: 자동 분석** — 타입과 설명을 하네스가 변경사항에서 추론

```
Claude Code / Gemini →  /ship
Codex                →  ship        (또는 "배포해줘")
```

**방법 2: 타입·설명 직접 지정** — 사용자 확인 없이 바로 검증 단계로 진행

```
Claude Code / Gemini →  /ship feat 알림 설정 API 추가
Codex                →  ship feat 알림 설정 API 추가
```

### dev 브랜치 vs 이슈 브랜치

| 현재 브랜치 | 동작 |
|-------------|------|
| `dev` | 변경사항 분석 → 검증 → 이슈·브랜치 자동 생성 → 배포 (전체 흐름) |
| 이슈 브랜치 (`feat/#123` 등) | 이슈·브랜치 생성을 스킵하고 검증 → 배포로 직행 |

### 사용자 개입 포인트

dev 브랜치에서 타입·설명 없이 실행한 경우 **1곳**:

1. **변경사항 확인** (Phase 1) — 하네스가 분석한 타입과 설명을 확인하고, 필요시 수정 요청

타입·설명을 인자로 전달하거나, 이슈 브랜치에서 실행하면 사용자 개입 없이 자동으로 진행됩니다.

---

## 설계 의도

### `/problem` 워크플로우 설계 결정

#### 1. API / 비API 작업 분류

하나의 해결책 안에서도 작업을 `[API]`(Controller/Service/Repository 레이어)와 `[비API]`(설정, 인프라, 유틸)로 분류합니다.

**이유**: API 레이어 변경은 비즈니스 로직에 직접 영향을 주므로 반드시 Test-First로 검증해야 합니다. 반면 설정 변경이나 인프라 수정에 불필요한 테스트를 강제하면 오버헤드만 늘어납니다. 작업 성격에 따라 절차를 분리함으로써 **안전성과 속도를 동시에 확보**합니다.

#### 2. 테스트 작성자 분리 우선 & 모드 공통 동결(freeze)

`[API]` 작업은 구현 전에 **Claude Code가 신규 계약에 필요한 최소 스텁을 준비하고 Codex가 테스트를 독립 작성**합니다. 이후 Discovery·컴파일 GREEN을 확인하고, 신규·변경 테스트 메서드별로 구현 전 기준선에서 RED인지 또는 구현과 독립적인 GREEN인지 근거를 기록합니다. 정성 리뷰 후 생성·수정된 테스트 소스·fixture와 스텁(있는 경우)을 함께 커밋합니다. Codex를 쓸 수 없으면 Claude Code가 테스트도 작성하지만, 같은 게이트·동결·감사 절차를 적용합니다. PreToolUse 훅이 동결 테스트 산출물의 편집을 차단하고, Phase 5의 `git diff` 사후 감사가 우회 편집까지 잡습니다.

**이유**: AI가 코드를 작성할 때 가장 큰 위험은 "돌아가는 것 같지만 실제로는 스펙과 다른 코드"입니다. **테스트 작성자(Codex)와 구현자(Claude Code)를 분리**하면 테스트가 독립 명세(spec)가 되어 구현을 더 강하게 검증합니다. Codex가 없더라도 테스트를 먼저 RED로 검증·동결하면 구현 루프에서 테스트를 고쳐 통과시키는 우회를 막을 수 있습니다. 스텁 설계권을 구현측에 두고 Codex의 수정 범위를 테스트·fixture로 제한해, 코드베이스 컨텍스트가 적은 테스트 작성자에게 아키텍처 결정을 넘기지 않습니다.

> Codex 테스트 생성 호출은 stdin/stdout 파이프 상속으로 인한 프로세스 hang 위험이 있어, ① 프롬프트 stdin 리다이렉트 ② 출력 파일 리다이렉트 ③ 프롬프트 내 빌드 실행 금지 ④ `timeout` 상한의 **4중 방어**로 이를 원천 차단합니다.

#### 3. 병렬 워크트리 실행 & cherry-pick 통합

독립적인 작업 그룹을 Agent tool로 동시에 실행(각자 git worktree에서 로컬 커밋)하고, 각 에이전트가 보고한 커밋 SHA를 메인 세션이 cherry-pick으로 통합합니다.

**이유**: 서로 다른 도메인의 변경을 순차 처리하면 불필요하게 시간이 늘어납니다. worktree로 **각 작업을 완전히 격리된 환경에서 병렬 실행**하고, 통합은 커밋 SHA 기반 cherry-pick으로 선택적으로 가져오므로 충돌 시 메인 세션이 컨텍스트를 보고 판단할 수 있습니다. 무거운 통합 테스트(DB 컨테이너 등)는 로컬 자원 경합을 피해 워크트리에서 실행하지 않고, 통합 후 메인 세션에서 일괄 실행합니다. (병렬 위임 프리미티브가 없는 Codex/Gemini는 이 모드 대신 `/ship`의 단일 흐름을 사용합니다.)

#### 4. 메인 세션 직접 배포 파이프라인

배포 파이프라인(커밋 → PR → CI → 머지 → CD)을 서브에이전트에 위임하지 않고 **메인 세션이 직접** 수행하며, CI/CD·PR 체크 대기는 `automation/bin/`의 폴링·게이트 스크립트(`pr-gate.sh`·`run-wait.sh`)를 `run_in_background` Bash(Codex/Gemini는 포그라운드 블로킹 호출)로 실행합니다.

**이유**: 파이프라인은 "액션 → 폴링 → 다음 액션"의 반복인데, 서브에이전트 안에서 백그라운드 폴링을 돌리면 완료 후 세션 재개가 안 돼 대기 지점에서 멈추는 문제가 실측되었습니다. 메인 세션의 `run_in_background` Bash는 완료 시 세션을 확실히 재호출하므로, 긴 대기가 섞인 파이프라인을 안정적으로 이어갈 수 있습니다. 대기 로직을 명세에 인라인 루프로 두지 않고 `automation/bin/` 스크립트로 추출해, 게이트 판정(PR 전수 체크·앵커 존재·fail-closed)을 스모크 테스트로 검증하고 세 하네스가 동일 코드를 공유합니다. 스크립트는 GitHub API 조회 실패를 pending으로 삼키지 않고 3회 연속 실패 시 `API_ERROR`로 중단하여, 네트워크 장애를 CI 대기로 오판하지 않습니다.

#### 5. CI 검증 없는 배포 금지

코드 수정이 포함된 재시작은 반드시 CI(Step 2)를 다시 거치도록 강제합니다.

**이유**: 파이프라인 실패 후 "빠르게 고쳐서 바로 배포"하는 유혹이 있지만, 이는 2차 장애의 원인이 됩니다. 자동화된 워크플로우일수록 **안전 게이트를 건너뛰지 않는 것**이 중요합니다. 재시작 매핑 테이블은 어떤 실패 시점에서든 어디로 돌아가야 하는지 명확하게 정의하여 혼란을 방지합니다.

#### 6. 파괴적 DB 마이그레이션 2단계 배포

파괴적 스키마 변경(`DROP`, `RENAME COLUMN`, `ADD NOT NULL` 등)이 포함된 작업은 1차 배포(앱 코드 변경)와 2차 배포(파괴적 마이그레이션)로 분리합니다.

**이유**: DB 마이그레이션은 앱 이미지를 롤백해도 되돌아가지 않습니다. 파괴적 마이그레이션을 앱 코드와 한 번에 배포하면, 롤백 시 스키마 검증이 실패하여 **앱이 시작조차 불가능한 상태**가 됩니다. 2단계로 분리하면 1차 배포 후 안정성을 확인한 뒤 스키마를 변경하므로, 롤백 가능성을 유지하면서 안전하게 마이그레이션할 수 있습니다.

#### 7. 환경변수 추가 체크리스트

새 환경변수 도입 시 전달 경로(GitHub Secrets → CD workflow → 배포 스크립트 → 배포 구성 → 컨테이너 → 앱 설정) 전체를 체크리스트로 검증합니다.

**이유**: 환경변수 전달 경로는 여러 파일에 걸쳐 있어 한 곳이라도 누락되면 프로덕션에서 앱 시작 실패가 발생합니다. 특히 AI 에이전트가 앱 코드에만 환경변수를 추가하고 CD 워크플로우나 배포 구성을 빠뜨리는 실수가 반복되었습니다. 체크리스트를 Phase 5 통합 검토에 포함시켜 **배포 전에 누락을 체계적으로 방지**합니다.

#### 8. 민감 파일 커밋 차단 & 동결 테스트 보호 Hook

PreToolUse hook 두 개로 (a) `.env`·`.claude/settings.local.json` 등 민감 파일이 git에 추가되는 것을 사전 차단하고, (b) 작성 모드와 무관하게 동결된 테스트 소스·fixture의 Edit/Write를 차단합니다.

**이유**: AI 에이전트가 `git add -A`를 실행하면 의도치 않게 시크릿이 커밋될 수 있고, RED 테스트를 통과시키지 못할 때 "테스트를 고쳐버리는" 우회 유혹이 생깁니다. 두 훅은 **자동화의 편의성을 유지하면서 보안 사고와 명세 훼손을 예방**합니다. (동결 훅은 예방, Phase 5의 `git diff` 감사는 탐지 — 두 층으로 Bash 우회 편집까지 방어합니다.) 민감 파일 차단은 훅에만 의존하지 않고 파이프라인 Step 1에서 **모든 하네스가 `automation/bin/sensitive-gate.sh`**(스테이징 후 `git diff --cached` 검사, 정규식이 패턴의 단일 원천)를 실행하므로, 훅이 없는 Codex/Gemini도 기계적으로 커버되고 Claude Code는 훅과 이중 방어됩니다.
