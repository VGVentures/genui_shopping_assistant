#!/bin/bash
set -e

MAX_ITERATIONS=${1:-20}

# Ensure we're on the right branch
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "genkit-refactor" ]; then
  echo "ERROR: Must be on genkit-refactor branch. Run: git checkout genkit-refactor"
  exit 1
fi

# Initialize files if they don't exist
touch progress_blog.txt
touch blog_v2.md

echo "Starting Ralph-Blog Loop — max $MAX_ITERATIONS iterations"
echo "================================================"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo ""
  echo ">>> Ralph-Blog iteration $i of $MAX_ITERATIONS"
  echo "================================================"

  PRD=$(cat PRD_v2.md)
  CODE_PROGRESS=$(cat progress_code.txt)
  BLOG_PROGRESS=$(cat progress_blog.txt)
  BLOG=$(cat blog_v2.md)

  # Get recent git log for diff context
  GIT_LOG=$(git log --oneline -10)

  PROMPT="You are Ralph-Blog. You write blog content, you do NOT write code.

Here is the PRD:

<prd>
${PRD}
</prd>

Here is the code progress (written by Ralph-Code):

<code_progress>
${CODE_PROGRESS}
</code_progress>

Here is the blog progress (what you've already written):

<blog_progress>
${BLOG_PROGRESS}
</blog_progress>

Here is the current blog_v2.md:

<blog>
${BLOG}
</blog>

Recent git log:
<git_log>
${GIT_LOG}
</git_log>

Your job:
1. Compare code_progress with blog_progress to find the next completed code task that doesn't have a blog section yet
2. If no new completed task exists, output <promise>WAITING</promise> and stop
3. If all code tasks AND all blog sections are complete (including intro and conclusion), output <promise>COMPLETE</promise> and stop
4. Otherwise: read the actual source files changed by that task (use the git diff or read the files directly), then write the blog section

To write a blog section:
- Read the actual code files to get real snippets — do NOT invent code
- Append the section to blog_v2.md (read it first to avoid duplicates)
- Add one line to progress_blog.txt: \"Section for Task N: DONE\"

Special cases:
- If blog_v2.md is empty and there's at least one completed code task, write the Introduction first, then the section for Task 1
- If all code tasks are DONE and all sections are written, write the Conclusion

IMPORTANT: Do NOT modify any .dart, .yaml, or config files. Only modify blog_v2.md and progress_blog.txt."

  OUTPUT=$(echo "$PROMPT" | claude -p \
    --permission-mode acceptEdits \
    --allowedTools 'Bash(git log:*),Bash(git diff:*),Bash(git show:*),Bash(cat *)' \
    2>&1) || true

  echo "$OUTPUT"

  if echo "$OUTPUT" | grep -q '<promise>COMPLETE</promise>'; then
    echo ""
    echo "================================================"
    echo "Ralph-Blog COMPLETE after $i iterations!"
    echo "================================================"
    exit 0
  fi

  if echo "$OUTPUT" | grep -q '<promise>WAITING</promise>'; then
    echo ""
    echo "Waiting for Ralph-Code to complete more tasks..."
    echo "Sleeping 60 seconds..."
    sleep 60
  fi
done

echo ""
echo "================================================"
echo "Ralph-Blog finished $MAX_ITERATIONS iterations (limit reached)"
echo "================================================"
