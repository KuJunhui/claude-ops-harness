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

SENSITIVE_PATTERNS=(
  ".claude/settings.local.json"
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
