#!/bin/bash
set -e

MAX_ITERATIONS=${1:-15}

if [ -z "$GOOGLE_API_KEY" ]; then
  echo "ERROR: GOOGLE_API_KEY is not set. Export it before running."
  echo "  export GOOGLE_API_KEY=your-key-here"
  exit 1
fi

# Ensure we're on the right branch
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "genkit-refactor" ]; then
  echo "ERROR: Must be on genkit-refactor branch. Run: git checkout genkit-refactor"
  exit 1
fi

# Initialize progress file if it doesn't exist
touch progress_code.txt

echo "Starting Ralph-Code Loop — max $MAX_ITERATIONS iterations"
echo "================================================"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo ""
  echo ">>> Ralph-Code iteration $i of $MAX_ITERATIONS"
  echo "================================================"

  PRD=$(cat PRD_v2.md)
  PROGRESS=$(cat progress_code.txt)

  PROMPT="You are Ralph-Code. You write code, you do NOT write blog content.

Here is the PRD:

<prd>
${PRD}
</prd>

Here is the current code progress:

<progress>
${PROGRESS}
</progress>

Identify the next incomplete code task from the PRD. ONLY DO ONE TASK AT A TIME.

1. Implement that single task
2. Run \`flutter build web --dart-define=GOOGLE_API_KEY=\$GOOGLE_API_KEY\` to verify it compiles
3. Commit your changes with a conventional commit message
4. Add exactly one line to progress_code.txt: \"Task N: DONE — <one-line summary>\"

If all tasks are complete, output <promise>COMPLETE</promise> and stop.

IMPORTANT: Do NOT modify blog_v2.md. Do NOT write blog content. Only write code."

  OUTPUT=$(echo "$PROMPT" | claude -p \
    --permission-mode acceptEdits \
    --allowedTools 'Bash(git commit:*),Bash(git add:*),Bash(flutter *),Bash(dart *),Bash(mkdir *),Bash(ls *),Bash(cat *),Bash(rm *)' \
    2>&1) || true

  echo "$OUTPUT"

  if echo "$OUTPUT" | grep -q '<promise>COMPLETE</promise>'; then
    echo ""
    echo "================================================"
    echo "Ralph-Code COMPLETE after $i iterations!"
    echo "================================================"
    exit 0
  fi
done

echo ""
echo "================================================"
echo "Ralph-Code finished $MAX_ITERATIONS iterations (limit reached)"
echo "================================================"
