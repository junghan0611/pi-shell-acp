#!/usr/bin/env bash
set -euo pipefail

# bench.sh — PERSONAL maintainer-only benchmark helper.
#
# This is NOT part of the public install or verification flow. It exists for the
# repo maintainer to spot-check direct API vs pi-shell-acp (ACP bridge) latency
# and quality drift on a local machine. Consumers and contributors should ignore
# it — `./run.sh smoke-all` is the real dual-backend gate.
#
# Test prompts are deliberately kept in Korean because they reflect the
# maintainer's working language. Translating them would not make this script
# more useful to a generic consumer; it would just be cosmetic.
#
# Usage:
#   ./bench.sh [project-dir]
#
# Runs in the given project directory (default: this repo) so AGENTS.md
# system prompt and project context are loaded — matching the real harness.
#
# Environment:
#   PI_BENCH_MODEL_DIRECT  — direct model (default: github-copilot/claude-sonnet-4.6)
#   PI_BENCH_MODEL_SDK     — ACP bridge model (default: pi-shell-acp/claude-sonnet-4-6)
#   PI_BENCH_SUITE         — test suite: "quick" (3 tests) or "full" (default, all tests)

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=${1:-$(pwd)}
MODEL_DIRECT=${PI_BENCH_MODEL_DIRECT:-github-copilot/claude-sonnet-4.6}
MODEL_SDK=${PI_BENCH_MODEL_SDK:-pi-shell-acp/claude-sonnet-4-6}
SUITE=${PI_BENCH_SUITE:-full}
OUT_DIR="/tmp/pi-bench-$(date +%Y%m%dT%H%M%S)"

mkdir -p "$OUT_DIR"

echo "=== pi provider benchmark ==="
echo "project:  $PROJECT_DIR"
echo "direct:   $MODEL_DIRECT"
echo "sdk:      $MODEL_SDK"
echo "suite:    $SUITE"
echo "output:   $OUT_DIR"
echo ""

# --- Test Cases ---
# Each test: (name, prompt, expected_behavior)
#
# Layer 1: Basic — sanity checks
# Layer 2: Tool use — Read, Bash, multi-step
# Layer 3: Harness — system prompt adherence, code understanding, git awareness
declare -a TESTS_QUICK=(
  "simple|ok만 답하세요|단순 응답"
  "tool-bash|현재 날짜와 시간을 알려주세요. date 명령어를 사용하세요.|tool use (Bash)"
  "sysprompt|내가 사용하는 OS와 에디터가 뭐야? 한 줄로 답해.|시스템 프롬프트 준수"
)

declare -a TESTS_FULL=(
  # Layer 1: Basic
  "simple|ok만 답하세요|단순 응답"
  "reasoning|다음 수열의 다음 숫자를 구하세요: 2, 6, 14, 30, ?. 풀이 과정을 단계별로 보여주세요.|추론 능력"
  "korean-long|한국의 사계절 중 가장 좋아하는 계절과 그 이유를 3문장으로 설명해주세요. 비유를 하나 포함하세요.|한국어 생성 품질"

  # Layer 2: Tool use
  "tool-read|이 디렉토리에 README.md가 있으면 첫 3줄을 읽어주세요. 없으면 '없음'이라고 답하세요.|tool use (Read)"
  "tool-bash|현재 날짜와 시간을 알려주세요. date 명령어를 사용하세요.|tool use (Bash)"
  "multi-step|이 프로젝트의 package.json에서 name과 version을 읽고, 한 줄로 요약해주세요.|multi-step tool use"
  "file-search|이 프로젝트에서 extractPromptBlocks 함수가 정의된 파일을 찾아주세요. grep을 사용하세요.|파일 검색 (Grep)"

  # Layer 3: Harness — AGENTS.md system prompt loaded from PROJECT_DIR
  "sysprompt|내가 사용하는 OS와 에디터가 뭐야? 한 줄로 답해.|시스템 프롬프트 준수"
  "code-read|index.ts의 extractPromptBlocks 함수가 무엇을 하는지 한 줄로 설명해주세요.|코드 이해"
  "git-status|현재 git 브랜치와 최근 커밋 메시지 1개를 알려주세요.|git 인식"
)

run_test() {
  local name="$1" prompt="$2" desc="$3" model="$4" label="$5"
  local outfile="$OUT_DIR/${name}_${label}.txt"
  local timefile="$OUT_DIR/${name}_${label}.time"

  echo -n "  [$label] $name ($desc)... "

  local start end elapsed
  start=$(date +%s%N)

  # Run pi in non-interactive mode
  # SDK bridge needs -e to load extension; direct anthropic does not
  local pi_cmd
  if [[ "$label" == "sdk" ]]; then
    pi_cmd="pi -e '$REPO_DIR' --model '$model' -p '$prompt'"
  else
    pi_cmd="pi --model '$model' -p '$prompt'"
  fi

  # Timeout: 120s per test
  if timeout 120 bash -c "cd '$PROJECT_DIR' && $pi_cmd" > "$outfile" 2>"$OUT_DIR/${name}_${label}.err"; then
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    echo "${elapsed}ms"
    echo "$elapsed" > "$timefile"
  else
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    echo "FAIL (${elapsed}ms)"
    echo "FAIL:$elapsed" > "$timefile"
  fi
}

# --- Select suite ---
if [[ "$SUITE" == "quick" ]]; then
  TESTS=("${TESTS_QUICK[@]}")
else
  TESTS=("${TESTS_FULL[@]}")
fi

# --- Run all tests ---
for test_spec in "${TESTS[@]}"; do
  IFS='|' read -r name prompt desc <<< "$test_spec"
  echo "--- $name: $desc ---"
  run_test "$name" "$prompt" "$desc" "$MODEL_DIRECT" "direct"
  run_test "$name" "$prompt" "$desc" "$MODEL_SDK" "sdk"
  echo ""
done

# --- Summary ---
echo "=== Results ==="
echo ""
printf "%-15s  %-10s  %-10s  %-8s\n" "Test" "Direct(ms)" "SDK(ms)" "Ratio"
printf "%-15s  %-10s  %-10s  %-8s\n" "----" "----------" "-------" "-----"

for test_spec in "${TESTS[@]}"; do
  IFS='|' read -r name _ _ <<< "$test_spec"
  direct_time=$(cat "$OUT_DIR/${name}_direct.time" 2>/dev/null || echo "N/A")
  sdk_time=$(cat "$OUT_DIR/${name}_sdk.time" 2>/dev/null || echo "N/A")

  if [[ "$direct_time" =~ ^[0-9]+$ ]] && [[ "$sdk_time" =~ ^[0-9]+$ ]] && [[ "$direct_time" -gt 0 ]]; then
    ratio=$(python3 -c "print(f'{$sdk_time/$direct_time:.1f}x')")
  else
    ratio="N/A"
  fi

  printf "%-15s  %-10s  %-10s  %-8s\n" "$name" "$direct_time" "$sdk_time" "$ratio"
done

echo ""
echo "=== Output comparison ==="
echo ""

for test_spec in "${TESTS[@]}"; do
  IFS='|' read -r name prompt desc <<< "$test_spec"
  echo "--- $name ---"

  if [[ -f "$OUT_DIR/${name}_direct.txt" ]]; then
    echo "[direct] $(head -c 200 "$OUT_DIR/${name}_direct.txt")"
  else
    echo "[direct] (no output)"
  fi

  if [[ -f "$OUT_DIR/${name}_sdk.txt" ]]; then
    echo "[sdk]    $(head -c 200 "$OUT_DIR/${name}_sdk.txt")"
  else
    echo "[sdk]    (no output)"
  fi

  echo ""
done

echo "Full outputs in: $OUT_DIR"
echo ""
echo "To diff a specific test:"
echo "  diff $OUT_DIR/<test>_direct.txt $OUT_DIR/<test>_sdk.txt"
