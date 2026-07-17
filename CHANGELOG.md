# Changelog

All notable changes to agent-skills will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Cursor plugin packaging: `.cursor-plugin/plugin.json` and `.cursor-plugin/marketplace.json`
  publish the repository as the **mittwald mStudio Skills** plugin, installable via
  Cursor's *Add Marketplace → Import from Repo*. Cursor discovers both skills from `skills/`
  at the repository root; no files moved. See "Plugin packaging" in DEVELOPING.md for why
  Cursor gets one bundled plugin while Claude Code gets two.
- `assets/logo.svg` (mittwald icon, negative on navy) for the Cursor marketplace listing.
- Bundled mittwald MCP server (`mcp.json`) in the Cursor plugin. Installing the plugin now connects
  `https://mcp.mittwald.de/mcp` via OAuth — no config file to edit, no API token to paste — which
  puts both skills on their preferred MCP surface immediately. This makes the plugin a replacement
  for the manual Cursor MCP setup guide rather than a pointer to it.
- Consolidated repository structure with both mittwald-migrate and mittwald-zerodeploy-skill
- Unified README.md covering both skills
- DEVELOPING.md with contribution guidelines and repository conventions
- CONTRIBUTING.md for quick contribution guide
- AGENTS.md for OpenAI Codex support
- example.env template for API token configuration
- setup-test.sh automated test setup script
- .gitignore for sensitive files and artifacts
- LICENSE file (MIT)
- This CHANGELOG.md

### Changed

- Repository now houses multiple skills instead of single skill
- Installation instructions updated to reflect consolidated structure
- Both skills maintained in single repository for easier maintenance

### Migration from Separate Repositories

- mittwald-migrate: Previously at mittwald/mstudio-migrate-skill
- mittwald-zerodeploy-skill: Previously at mittwald/mittwald-zerodeploy-skill
- All playbooks and references preserved in their respective skill directories
