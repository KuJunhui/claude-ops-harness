#!/usr/bin/env bash
#
# Claude Code PreToolUse hook: git 명령에서 민감 파일 감지 시 차단
#
set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# git add 또는 git commit이 아니면 통과
if ! echo "$COMMAND" | grep -qE '^git (add|commit|push)'; then
  exit 0
fi

# 하네스 레포 자체에서는 .claude/ 커밋이 필요하므로 해당 패턴 제외
IS_HARNESS_REPO=false
if [ -f "$CLAUDE_PROJECT_DIR/install.sh" ] && grep -q "claude.*harness" "$CLAUDE_PROJECT_DIR/install.sh" 2>/dev/null; then
  IS_HARNESS_REPO=true
fi

SENSITIVE_PATTERNS=(
  "CLAUDE.md"
  ".claude/"
  ".env"
  "application-secret.yml"
  "firebase-adminsdk.json"
  "*.tfvars"
  "*.tfstate"
)

BLOCKED_FILES=()

# git add: 명시적으로 민감 파일을 추가하려는지 확인
if echo "$COMMAND" | grep -qE '^git add'; then
  ARGS=$(echo "$COMMAND" | sed 's/^git add\s*//')

  # git add . / git add -A 같은 전체 추가 명령이면 untracked + modified 확인
  if echo "$ARGS" | grep -qE '^\.|^-A|^--all'; then
    CANDIDATES=$(git ls-files --others --modified --exclude-standard 2>/dev/null || true)
  else
    CANDIDATES="$ARGS"
  fi

  for file in $CANDIDATES; do
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
      # 하네스 레포에서는 .claude/ 패턴 건너뛰기
      if [ "$IS_HARNESS_REPO" = true ] && [ "$pattern" = ".claude/" ]; then
        continue
      fi
      case "$file" in
        $pattern|*/$pattern|${pattern}*)
          BLOCKED_FILES+=("$file")
          ;;
      esac
    done
  done
fi

# git commit / git push: 스테이징된 파일 확인
if echo "$COMMAND" | grep -qE '^git (commit|push)'; then
  STAGED=$(git diff --cached --name-only 2>/dev/null || true)
  for file in $STAGED; do
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
      if [ "$IS_HARNESS_REPO" = true ] && [ "$pattern" = ".claude/" ]; then
        continue
      fi
      case "$file" in
        $pattern|*/$pattern|${pattern}*)
          BLOCKED_FILES+=("$file")
          ;;
      esac
    done
  done
fi

if [ ${#BLOCKED_FILES[@]} -gt 0 ]; then
  FILES_LIST=$(printf ', %s' "${BLOCKED_FILES[@]}")
  FILES_LIST=${FILES_LIST:2}

  jq -n --arg files "$FILES_LIST" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("민감 파일 감지로 차단: " + $files + ". git reset HEAD <file>로 스테이징 해제하세요.")
    }
  }'
  exit 0
fi

exit 0
