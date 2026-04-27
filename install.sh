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
mkdir -p "$PROJECT_DIR/.claude/hooks"

# 파일 복사
cp "$SCRIPT_DIR/.claude/settings.json" "$PROJECT_DIR/.claude/settings.json"
echo "  [OK] .claude/settings.json"

cp "$SCRIPT_DIR/.claude/commands/problem.md" "$PROJECT_DIR/.claude/commands/problem.md"
echo "  [OK] .claude/commands/problem.md"

cp "$SCRIPT_DIR/.claude/hooks/validate-git-sensitive.sh" "$PROJECT_DIR/.claude/hooks/validate-git-sensitive.sh"
chmod +x "$PROJECT_DIR/.claude/hooks/validate-git-sensitive.sh"
echo "  [OK] .claude/hooks/validate-git-sensitive.sh"

echo ""
echo "==> 설치 완료!"
echo ""
echo "참고: .claude/ 와 CLAUDE.md 가 대상 프로젝트의 .gitignore에 등록되어 있는지 확인하세요."
echo "      하네스 업데이트 시 이 스크립트를 다시 실행하면 됩니다."
