#!/usr/bin/env bash
#
# Claude Code PreToolUse hook: 동결 테스트 산출물(소스·fixture)의 Edit/Write 차단
#
# frozen-tests.txt가 없으면 무조건 통과.
# 존재하면 대상 file_path가 목록에 있는지 확인하여 deny.
#
# frozen-tests.txt는 작성 모드(Codex 또는 Claude 단독)와 무관하게
# 동결할 테스트 소스·fixture의 리포 루트 기준 상대 경로를 기록한다.
# 대상 파일을 그 파일이 속한 git 워크트리 루트 기준 상대 경로로 정규화하여 비교하므로,
# 메인 리포와 병렬 워크트리(다른 루트 디렉토리) 양쪽에서 동일하게 매칭된다.
#
set -e

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -n "$FILE_PATH" ] || exit 0

FROZEN_LIST="${CLAUDE_PROJECT_DIR:-.}/.problem/frozen-tests.txt"
[ -f "$FROZEN_LIST" ] || exit 0

# 대상 파일 → 절대 경로
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(pwd)/$FILE_PATH"
fi

# 대상 파일이 속한 git 워크트리 루트 기준 상대 경로로 정규화
FILE_DIR=$(dirname "$FILE_PATH")
TOPLEVEL=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -n "$TOPLEVEL" ]; then
  REL_PATH="${FILE_PATH#"$TOPLEVEL"/}"
else
  REL_PATH="$FILE_PATH"
fi

while IFS= read -r frozen; do
  [ -z "$frozen" ] && continue
  # 상대 경로(정규화) 또는 절대 경로 양쪽 매칭 지원
  if [ "$REL_PATH" = "$frozen" ] || [ "$FILE_PATH" = "$frozen" ]; then
    jq -n --arg f "$REL_PATH" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("🧊 TEST-FREEZE: " + $f + " — 동결된 테스트 산출물입니다. 구현 코드를 수정하여 테스트를 통과시키세요. 테스트가 스펙을 잘못 해석했다면 ⚠️ TEST-DISPUTE로 이의를 제기하세요.")
      }
    }'
    exit 0
  fi
done < "$FROZEN_LIST"

exit 0
