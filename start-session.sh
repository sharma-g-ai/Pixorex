#!/usr/bin/env bash
# start-session.sh — builds the context bundle for ONE task, then opens a fresh agent session.
#
# Usage:
#   ./start-session.sh PX-04-T07 "app/services/scan_service.py app/repositories/scan_repo.py" "Tenancy and access control"
#
#   $1  task ID            (PX-<epic>-T<nn>)
#   $2  files in scope     (space-separated, max 5)
#   $3  ARCHITECTURE.md heading to include (optional; matched as a substring of a "## " heading)
#
# Env:
#   AGENT_CMD   command used to launch the agent (default: "claude"). Set to "" to only write the bundle.

set -euo pipefail

TASK_ID="${1:?task ID required, e.g. PX-04-T07}"
FILES="${2:-}"
ARCH_SECTION="${3:-}"
OUT_DIR=".claude"
OUT="${OUT_DIR}/session-context.md"
AGENT_CMD="${AGENT_CMD-claude}"

# --- Parse and validate the task ID -------------------------------------------------
if [[ ! "$TASK_ID" =~ ^PX-([0-9]{2})-T([0-9]{2})$ ]]; then
  echo "Task ID must look like PX-04-T07" >&2; exit 1
fi
EPIC="${BASH_REMATCH[1]}"
SPEC="specs/SPEC-PX-${EPIC}.md"
TASK_FILE="tasks/${TASK_ID}.md"

for f in CONSTITUTION.md STATE.md "$SPEC"; do
  [[ -f "$f" ]] || { echo "Missing required file: $f" >&2; exit 1; }
done

# --- Enforce the file limit from the constitution ----------------------------------
read -r -a FILE_ARR <<< "$FILES"
if (( ${#FILE_ARR[@]} > 5 )); then
  echo "Too many files (${#FILE_ARR[@]}). Constitution limit is 5 per task. Split the task." >&2; exit 1
fi
for f in "${FILE_ARR[@]}"; do
  [[ -f "$f" ]] || echo "Warning: $f does not exist yet (fine if the task creates it)" >&2
done

# --- Refuse to start if THIS operator already has a task in progress ---------------
# Operator = 4th column of the task table; set OPERATOR (e.g. OPERATOR=FSD-A) to enable.
if [[ -n "${OPERATOR:-}" ]]; then
  if awk -F'|' -v op="$OPERATOR" -v id="$TASK_ID" '
      { gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $6) }
      $2 != id && index($5, op) > 0 && $6 == "in_progress" { found = 1 }
      END { exit !found }' STATE.md; then
    echo "${OPERATOR} already has a task in_progress in STATE.md. Merge it before starting ${TASK_ID}." >&2
    exit 1
  fi
else
  echo "Note: set OPERATOR=<your lane, e.g. FSD-A> to enforce one task at a time." >&2
fi

mkdir -p "$OUT_DIR"
{
  echo "# SESSION CONTEXT — ${TASK_ID}"
  echo
  echo "Order of authority: CONSTITUTION > task > spec > state > architecture."
  echo "Work ONLY on ${TASK_ID}. List assumptions and open questions before coding. Tests first."
  echo
  echo "---"; echo "## 1. CONSTITUTION.md"; echo; cat CONSTITUTION.md
  echo; echo "---"; echo "## 2. TASK ${TASK_ID}"; echo
  if [[ -f "$TASK_FILE" ]]; then cat "$TASK_FILE"; else echo "(No task file at ${TASK_FILE}. Use the task row in STATE.md and the spec.)"; fi
  echo; echo "---"; echo "## 3. SPEC ${SPEC}"; echo; cat "$SPEC"
  echo; echo "---"; echo "## 4. STATE.md"; echo; cat STATE.md

  if [[ -n "$ARCH_SECTION" && -f ARCHITECTURE.md ]]; then
    echo; echo "---"; echo "## 5. ARCHITECTURE.md — section matching: ${ARCH_SECTION}"; echo
    awk -v pat="$ARCH_SECTION" '
      /^## / { printing = (index(tolower($0), tolower(pat)) > 0) }
      printing { print }
    ' ARCHITECTURE.md
  fi

  if (( ${#FILE_ARR[@]} > 0 )); then
    echo; echo "---"; echo "## 6. FILES IN SCOPE"
    for f in "${FILE_ARR[@]}"; do
      echo; echo "### ${f}"; echo '```'
      [[ -f "$f" ]] && cat "$f" || echo "(new file)"
      echo '```'
    done
  fi
} > "$OUT"

echo "Context written to ${OUT} ($(wc -l < "$OUT") lines) for ${TASK_ID}"

# --- Mark the task in progress in STATE.md (best effort) ----------------------------
if grep -q "| ${TASK_ID} |" STATE.md; then
  sed -i.bak -E "/\| ${TASK_ID} \|/ s/\| (todo|blocked) \|/| in_progress |/" STATE.md && rm -f STATE.md.bak
fi

# --- Launch a fresh agent session ----------------------------------------------------
if [[ -n "$AGENT_CMD" ]]; then
  exec $AGENT_CMD "Read ${OUT} fully. Then work only on ${TASK_ID} as instructed there."
fi
