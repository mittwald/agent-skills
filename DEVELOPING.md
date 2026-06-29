# DEVELOPING.md

**Contribution guidelines for agent-skills repository**

This document explains how to work on the skills themselves — structure, conventions, testing, and contribution workflow.

---

## Repository Structure

```
agent-skills/
├── skills/                     # Individual skill directories
│   ├── mittwald-migrate/       # Migration skill
│   │   ├── SKILL.md            # Main entry point (< 200 lines)
│   │   ├── playbooks/          # Step-by-step executable guides
│   │   └── references/         # Background knowledge docs
│   └── mittwald-zerodeploy/  # Deployment skill
│       ├── SKILL.md
│       ├── playbooks/
│       └── references/
├── README.md                   # User-facing documentation
├── DEVELOPING.md               # This file - maintainer guide
├── AGENTS.md                   # OpenAI Codex support
├── LICENSE                     # MIT license
└── example.env                 # API token template
```

### Design Principles

1. **SKILL.md is the entry point** - Keep it under 200 lines. It should be a workflow index, not a manual.
2. **Playbooks are executable** - Each playbook is a self-contained guide for one phase. The AI follows them step-by-step.
3. **References are background** - Context, explanations, and deep dives. The AI loads these on-demand when playbooks reference them.
4. **Separation of concerns** - Playbooks say "what to do", references explain "why and how".
5. **Agent-agnostic** - Pure markdown. No code, no agent-specific features. Works with any AI assistant.

---

## File Conventions

### SKILL.md

- **Purpose**: Workflow index and trigger matcher
- **Length**: < 200 lines
- **Structure**:

  ```markdown
  # Skill Name
  
  ## Triggers
  - List of phrases/keywords that activate this skill
  
  ## Workflow
  - Phase-by-phase overview with links to playbooks
  
  ## Playbooks
  - Brief description of each playbook
  - Link to playbook file
  
  ## References
  - Brief description of each reference
  - Link to reference file
  ```

### Playbooks

- **Purpose**: Step-by-step executable guides
- **Naming**: Descriptive, action-oriented (e.g., `migrate-mysql.md`, `cutover-dns.md`)
- **For zerodeploy**: Number-prefixed for sequence (e.g., `01-provision-target.md`)
- **Structure**:

  ```markdown
  # Playbook Title
  
  ## Context
  - Brief: what is this playbook for?
  - When to use it
  - Prerequisites
  
  ## Steps
  1. Concrete action
  2. Expected output
  3. Next action
  
  ## Troubleshooting
  - Common issues
  - How to recover
  
  ## Next Steps
  - What happens after this playbook
  - Link to next playbook or references
  ```

### References

- **Purpose**: Background knowledge, explanations, catalogs
- **Naming**: Descriptive noun (e.g., `pitfalls.md`, `ssh-modes.md`)
- **Structure**: Flexible - whatever works for the content. Can be:
  - Catalog (e.g., app catalog, database engines)
  - Concept explanation (e.g., SSH modes, Railpack overview)
  - Troubleshooting guide (e.g., pitfalls)
  - Decision tree (e.g., when to escalate)

---

## Adding New Content

### Adding a Playbook

1. Create the playbook file in `skills/<skill-name>/playbooks/`
2. Follow the playbook structure above
3. Add an entry to `SKILL.md` under the appropriate workflow phase
4. Test with an AI assistant - does it execute correctly?

### Adding a Reference

1. Create the reference file in `skills/<skill-name>/references/`
2. Write comprehensive, clear content
3. Add an entry to `SKILL.md` references section
4. Link from relevant playbooks
5. Test - is the AI able to find and use this reference when needed?

### Adding a New Skill

1. Create `skills/<skill-name>/` directory
2. Create `SKILL.md` with triggers and workflow
3. Create `playbooks/` and `references/` subdirectories
4. Populate with content following conventions above
5. Add section to main `README.md`
6. Add symlink instructions to `README.md`
7. Test installation and triggering

---

## Testing

### Manual Testing

1. **Install locally**:

   ```bash
   mkdir -p ~/.agents/skills
   ln -s $(pwd)/skills/mittwald-migrate ~/.agents/skills/mittwald-migrate
   ln -s $(pwd)/skills/mittwald-zerodeploy ~/.agents/skills/mittwald-zerodeploy
   ```

2. **Restart your AI assistant** (VS Code, Claude Code, etc.)

3. **Test trigger phrases**:
   - "I want to migrate to mittwald"
   - "Help me deploy my app to mittwald"

4. **Walk through a workflow**:
   - Does the AI load the correct playbook?
   - Does it follow the steps?
   - Does it reference the right background docs?

5. **Test error scenarios**:
   - Missing prerequisites
   - API errors
   - Network issues

### Testing with Different AI Assistants

Test with multiple assistants to ensure compatibility:

- VS Code Copilot
- Claude Code
- OpenAI Codex (via AGENTS.md)

Each should be able to load and execute the skills without modification.

---

## Continuous Integration

Because this repository is pure markdown, CI focuses on content integrity rather
than builds or unit tests. Three checks run on every pull request (see
`.github/workflows/ci.yml`):

1. **Markdown lint** — `markdownlint-cli2` enforces consistent, clean-rendering
   markdown. Rules are configured in `.markdownlint-cli2.jsonc`.
2. **Internal link check** — `lychee --offline` verifies that every relative link
   (playbook → reference, README → skill, etc.) points to a file that exists.
3. **SKILL.md validation** — `scripts/validate-skills.sh` checks that each
   `skills/*/SKILL.md` has valid frontmatter, that its `name:` matches the
   directory, and that it stays under 200 lines.

External URLs are **not** checked on PRs (third-party hosts go down or rate-limit,
which would cause flaky failures). Instead, `.github/workflows/external-links.yml`
checks them on a weekly schedule and opens a tracking issue if any are broken.

### Running the checks locally (before every commit)

Run these from the repository root and make sure all three pass before committing.
A green local run means a green PR.

```bash
# 1. Markdown: auto-fix mechanical issues, then verify the result is clean.
npx markdownlint-cli2 --fix "**/*.md"   # rewrites files in place
npx markdownlint-cli2 "**/*.md"         # must report 0 errors

# 2. Internal links resolve (requires lychee: https://github.com/lycheeverse/lychee,
#    or run via Docker: docker run --rm -v "$PWD:/input" -w /input lycheeverse/lychee ...)
lychee --offline --no-progress .         # must report 0 errors

# 3. SKILL.md conventions: frontmatter present, name matches directory, < 200 lines.
bash scripts/validate-skills.sh
```

**Keep mechanical formatting in its own commit.** When `--fix` reformats files,
commit that reformat separately (e.g. `style: apply markdownlint auto-fixes`) from
any content changes, so reviewers can read the substantive diff without noise.

---

## Code Review Checklist

Before submitting a PR:

- [ ] SKILL.md is under 200 lines
- [ ] Playbooks follow the standard structure
- [ ] References are clear and comprehensive
- [ ] All internal links work (playbook → reference, etc.)
- [ ] No hardcoded secrets or credentials
- [ ] Markdown is clean and renders correctly
- [ ] Tested with at least one AI assistant
- [ ] README.md updated if adding new skill or major feature
- [ ] No agent-specific features (pure markdown only)

---

## Writing Style

### For Playbooks

- **Imperative mood**: "Create a project", not "You should create a project"
- **Concrete steps**: Actual commands, not vague instructions
- **Expected output**: Show what success looks like
- **Error handling**: What to do when things go wrong

**Good**:

```markdown
1. Create the project:
   ```bash
   mw project create --name "my-project"
   ```

   Expected output: `Project created: p-abc123`

1. If you see "Permission denied", verify your token has api_write scope.

```

**Bad**:
```markdown
1. You might want to create a project using the CLI.
2. If there's an error, try fixing it.
```

### For References

- **Clear explanations**: Assume reader is learning
- **Examples**: Show, don't just tell
- **Links**: Reference official docs when appropriate
- **Context**: Why does this matter?

---

## Git Workflow

### Branching

- `master` - stable, tested content
- `feature/<name>` - new skills, playbooks, or references
- `fix/<issue>` - bug fixes, typo corrections

### Commit Messages

Follow conventional commits:

```
feat(migrate): add PostgreSQL migration playbook
fix(zerodeploy): correct port configuration instructions
docs: update README with new installation paths
```

### Pull Requests

1. **Title**: Clear, concise description
2. **Description**: What does this PR do? Why?
3. **Testing**: How did you test this?
4. **Screenshots**: If relevant (especially for documentation changes)
5. **Checklist**: Did you complete the Code Review Checklist above?

---

## Versioning

Skills don't have explicit version numbers. Instead:

- **Git tags** for major milestones
- **Commit hashes** for pinning to specific versions
- **Latest master** is the default

Users who need stability can:

```bash
git clone --branch v1.0.0 https://github.com/mittwald/agent-skills.git
```

Or pin to a commit:

```bash
git clone https://github.com/mittwald/agent-skills.git
cd agent-skills
git checkout <commit-hash>
```

---

## Maintenance

### Updating for API Changes

When mittwald API changes:

1. Update affected playbooks
2. Update references (especially `mittwald-surfaces.md`, `mittwald-mcp-tools.md`)
3. Test all workflows
4. Document breaking changes in commit message
5. Consider adding to pitfalls if it's a common trap

### Deprecating Content

When removing old playbooks or references:

1. Add deprecation notice at top of file
2. Point to replacement content
3. Keep the file for 6 months
4. Then remove in a clearly-marked PR

---

## Common Pitfalls (for Contributors)

1. **Making SKILL.md too long** - It should be an index, not a manual. Move content to playbooks/references.
2. **Hardcoding values** - Use placeholders like `<projectId>`, `<your-token>`, not real values.
3. **Agent-specific features** - Avoid anything that only works in one AI assistant.
4. **Assuming context** - Each playbook should be relatively self-contained. Link to prerequisites.
5. **Forgetting links** - Playbooks should link to relevant references. SKILL.md should link to everything.
6. **Inconsistent naming** - Follow the conventions: `action-noun.md` for playbooks, `noun.md` for references.

---

## Questions?

- **Issues**: Use GitHub Issues for bugs, feature requests, or questions
- **Discussions**: Use GitHub Discussions for general questions or ideas
- **Support**: For mittwald platform issues (not skill issues), use <https://studio.mittwald.de> support

---

## License

All contributions are made under the MIT License. See [LICENSE](LICENSE).
