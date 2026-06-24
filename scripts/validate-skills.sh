#!/usr/bin/env bash
#
# validate-skills.sh — enforce the SKILL.md invariants documented in DEVELOPING.md.
#
# For every skills/*/SKILL.md this checks:
#   1. The file opens with a YAML frontmatter block delimited by `---`.
#   2. The frontmatter contains a non-empty `name:` and `description:`.
#   3. The `name:` value equals the parent directory name.
#   4. The file is shorter than 200 lines (DEVELOPING.md mandates "< 200 lines").
#
# Exits non-zero and prints every violation if any check fails. No dependencies
# beyond a POSIX shell + coreutils, so contributors can run it locally without setup.

set -euo pipefail

# Resolve the repo root from this script's location so it works from any CWD.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

MAX_LINES=200

errors=0
checked=0

fail() {
  printf '  ✗ %s\n' "$1"
  errors=$((errors + 1))
}

# Read a top-level scalar key from the frontmatter block (between the first two
# `---` lines). Prints the trimmed value, or nothing if the key is absent.
frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---"   { exit }
    in_fm {
      # Match "key:" at the start of the line, capture the rest.
      if ($0 ~ "^" key ":[[:space:]]*") {
        sub("^" key ":[[:space:]]*", "")
        print
        exit
      }
    }
  ' "$file"
}

if [ ! -d "$SKILLS_DIR" ]; then
  echo "No skills/ directory found at $SKILLS_DIR" >&2
  exit 1
fi

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  [ -e "$skill_md" ] || continue
  checked=$((checked + 1))

  skill_dir="$(dirname "$skill_md")"
  dir_name="$(basename "$skill_dir")"
  rel="${skill_md#"$REPO_ROOT"/}"

  printf '• %s\n' "$rel"

  # 1. Frontmatter present (must start with `---` on line 1 and have a closing `---`).
  first_line="$(head -n 1 "$skill_md")"
  if [ "$first_line" != "---" ]; then
    fail "missing YAML frontmatter (file must start with '---')"
    continue
  fi
  if [ "$(awk 'NR>1 && $0=="---"{print NR; exit}' "$skill_md")" = "" ]; then
    fail "frontmatter is not closed with a second '---'"
    continue
  fi

  # 2 + 3. name present and matches the directory.
  name_value="$(frontmatter_value "$skill_md" name)"
  if [ -z "$name_value" ]; then
    fail "frontmatter is missing a non-empty 'name:'"
  elif [ "$name_value" != "$dir_name" ]; then
    fail "frontmatter name '$name_value' does not match directory '$dir_name'"
  fi

  # 2. description present.
  desc_value="$(frontmatter_value "$skill_md" description)"
  if [ -z "$desc_value" ]; then
    fail "frontmatter is missing a non-empty 'description:'"
  fi

  # 4. Line-count budget.
  line_count="$(wc -l < "$skill_md" | tr -d '[:space:]')"
  if [ "$line_count" -ge "$MAX_LINES" ]; then
    fail "SKILL.md has $line_count lines (must be < $MAX_LINES)"
  fi
done

echo
if [ "$checked" -eq 0 ]; then
  echo "No SKILL.md files found under skills/*/" >&2
  exit 1
fi

if [ "$errors" -gt 0 ]; then
  echo "✗ validate-skills: $errors problem(s) found across $checked skill(s)." >&2
  exit 1
fi

echo "✓ validate-skills: $checked skill(s) passed all checks."
