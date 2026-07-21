#!/usr/bin/env bash
#
# claude-ops-harness 설치 스크립트
# 대상 프로젝트 루트에서 실행하세요.
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

echo "==> Claude Code 하네스를 설치합니다..."
echo "    소스: $SCRIPT_DIR"
echo "    대상: $PROJECT_DIR"
echo ""

# .claude 디렉토리 구조 생성
mkdir -p "$PROJECT_DIR/.claude/commands"
mkdir -p "$PROJECT_DIR/.claude/common"
mkdir -p "$PROJECT_DIR/.claude/hooks"

# settings.json 백업 (기존 파일이 있으면)
if [ -f "$PROJECT_DIR/.claude/settings.json" ]; then
  cp "$PROJECT_DIR/.claude/settings.json" "$PROJECT_DIR/.claude/settings.json.bak"
  echo "  [!!] 기존 .claude/settings.json → settings.json.bak 백업 완료"
  echo "       커스텀 hooks/permissions가 있었다면 백업 파일을 확인하세요."
fi

# 파일 복사
cp "$SCRIPT_DIR/.claude/settings.json" "$PROJECT_DIR/.claude/settings.json"
echo "  [OK] .claude/settings.json"

cp "$SCRIPT_DIR/.claude/commands/problem.md" "$PROJECT_DIR/.claude/commands/problem.md"
echo "  [OK] .claude/commands/problem.md"

cp "$SCRIPT_DIR/.claude/commands/ship.md" "$PROJECT_DIR/.claude/commands/ship.md"
echo "  [OK] .claude/commands/ship.md"

cp "$SCRIPT_DIR/.claude/common/pipeline.md" "$PROJECT_DIR/.claude/common/pipeline.md"
echo "  [OK] .claude/common/pipeline.md"

cp "$SCRIPT_DIR/.claude/hooks/validate-git-sensitive.sh" "$PROJECT_DIR/.claude/hooks/validate-git-sensitive.sh"
chmod +x "$PROJECT_DIR/.claude/hooks/validate-git-sensitive.sh"
echo "  [OK] .claude/hooks/validate-git-sensitive.sh"

cp "$SCRIPT_DIR/.claude/hooks/freeze-test-files.sh" "$PROJECT_DIR/.claude/hooks/freeze-test-files.sh"
chmod +x "$PROJECT_DIR/.claude/hooks/freeze-test-files.sh"
echo "  [OK] .claude/hooks/freeze-test-files.sh"

# VERSION 복사
cp "$SCRIPT_DIR/VERSION" "$PROJECT_DIR/.claude/VERSION"
echo "  [OK] .claude/VERSION"

echo ""
echo "==> 설치 완료!"
echo ""
echo "참고: .claude/settings.local.json 은 개인 설정이므로 .gitignore에 등록하세요."
echo "      그 외 .claude/ 파일과 CLAUDE.md 는 팀과 공유 가능합니다."
echo "      하네스 업데이트 시 이 스크립트를 다시 실행하면 됩니다."
