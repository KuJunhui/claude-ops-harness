#!/usr/bin/env bash
#
# claude-ops-harness 설치 스크립트 (멀티 LLM 하네스)
# 대상 프로젝트 루트에서 실행하세요.
#
# 설치 대상 하네스를 인자로 지정할 수 있습니다 (기본: all):
#   ./install.sh            # automation/ + Claude + Codex + Gemini 전부
#   ./install.sh claude     # automation/ + Claude Code 어댑터만
#   ./install.sh codex      # automation/ + Codex 어댑터만
#   ./install.sh gemini     # automation/ + Gemini 어댑터만
#
set -euo pipefail

# Java/Spring 프로젝트 루트인지 확인
if [ ! -f "build.gradle" ] && [ ! -f "build.gradle.kts" ] && [ ! -f "pom.xml" ]; then
  echo "Error: Java/Spring 프로젝트 루트 디렉토리에서 실행해주세요."
  echo "       (build.gradle, build.gradle.kts, 또는 pom.xml이 필요합니다)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(pwd)"
TARGETS="${1:-all}"

want() { [ "$TARGETS" = "all" ] || [ "$TARGETS" = "$1" ]; }

echo "==> Ops 하네스를 설치합니다 (대상: $TARGETS)..."
echo "    소스: $SCRIPT_DIR"
echo "    대상: $PROJECT_DIR"
echo ""

# 기존 파일 백업 후 복사 (설정 파일이 덮어써지지 않도록)
copy_with_backup() {
  local rel="$1"
  if [ -f "$PROJECT_DIR/$rel" ] && ! cmp -s "$SCRIPT_DIR/$rel" "$PROJECT_DIR/$rel"; then
    cp "$PROJECT_DIR/$rel" "$PROJECT_DIR/$rel.bak"
    echo "  [!!] 기존 $rel → $rel.bak 백업 (커스텀 설정이 있었다면 확인하세요)"
  fi
  mkdir -p "$PROJECT_DIR/$(dirname "$rel")"
  cp "$SCRIPT_DIR/$rel" "$PROJECT_DIR/$rel"
  echo "  [OK] $rel"
}

copy_plain() {
  local rel="$1"
  mkdir -p "$PROJECT_DIR/$(dirname "$rel")"
  cp "$SCRIPT_DIR/$rel" "$PROJECT_DIR/$rel"
  echo "  [OK] $rel"
}

# ── 공통: 하네스 중립 명세 (automation/) ──────────────────────
echo "-- automation/ (하네스 중립 명세)"
copy_plain "automation/ship.md"
copy_plain "automation/pipeline.md"
# 폴링·게이트 스크립트 (pipeline.md가 참조)
copy_plain "automation/bin/pr-gate.sh"
copy_plain "automation/bin/pr-gate.jq"
copy_plain "automation/bin/run-wait.sh"
copy_plain "automation/bin/sensitive-gate.sh"
copy_plain "automation/bin/smoke-test.sh"
chmod +x "$PROJECT_DIR"/automation/bin/*.sh

# ── Claude Code 어댑터 ────────────────────────────────────────
if want claude; then
  echo "-- Claude Code 어댑터 (.claude/)"
  copy_with_backup ".claude/settings.json"
  copy_plain ".claude/commands/problem.md"
  copy_plain ".claude/commands/ship.md"
  copy_plain ".claude/common/pipeline.md"
  copy_plain ".claude/hooks/validate-git-sensitive.sh"
  copy_plain ".claude/hooks/freeze-test-files.sh"
  chmod +x "$PROJECT_DIR/.claude/hooks/validate-git-sensitive.sh"
  chmod +x "$PROJECT_DIR/.claude/hooks/freeze-test-files.sh"
fi

# ── Codex 어댑터 ──────────────────────────────────────────────
if want codex; then
  echo "-- Codex 어댑터 (.codex/)"
  copy_with_backup ".codex/config.toml"
  copy_plain ".codex/skills/ship/SKILL.md"
fi

# ── Gemini 어댑터 ─────────────────────────────────────────────
if want gemini; then
  echo "-- Gemini 어댑터 (.gemini/)"
  copy_plain ".gemini/commands/ship.toml"
fi

# ── VERSION ───────────────────────────────────────────────────
mkdir -p "$PROJECT_DIR/.claude" && cp "$SCRIPT_DIR/VERSION" "$PROJECT_DIR/.claude/VERSION"
cp "$SCRIPT_DIR/VERSION" "$PROJECT_DIR/automation/VERSION"
echo "  [OK] VERSION ($(cat "$SCRIPT_DIR/VERSION"))"

echo ""
echo "==> 설치 완료!"
echo ""
echo "호출 방법:"
echo "  Claude Code → /ship  또는  /problem  (네이티브 슬래시 명령)"
echo "  Gemini      → /ship                  (네이티브 슬래시 명령)"
echo "  Codex       → 'ship' 또는 '배포해줘'  (평문 — Codex엔 커스텀 슬래시 명령이 없음)"
echo ""
echo "다음 항목을 프로젝트에 맞게 조정하세요:"
echo "  - automation/pipeline.md: CI/CD 워크플로우 파일명·체크 이름 (Preflight에서 자동 탐색)"
echo "  - automation/ship.md, .claude/commands/problem.md: 빌드/테스트 명령, 이슈 템플릿"
echo "  - .codex/config.toml: IDE MCP 사용 시 URL (미사용이면 삭제 가능)"
echo ""
echo "참고: .claude/settings.local.json 은 개인 설정이므로 .gitignore에 등록하세요."
echo "      .problem/ (워크플로우 상태), .problem/local/ 은 커밋 대상이 아닙니다 — .gitignore에 추가하세요."
echo "      하네스 업데이트 시 이 스크립트를 다시 실행하면 됩니다."
