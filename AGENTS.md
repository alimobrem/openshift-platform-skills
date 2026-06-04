# Agent Instructions

This repository contains AI agent skills for OpenShift platform engineering — Shipwright,
Tekton, Quay, External Secrets, Istio/OSSM, progressive delivery, and DORA metrics.

## Repository Layout

```
skills/{skill-name}/
├── SKILL.md                          # Agent instructions (frontmatter + workflow)
├── references/                       # On-demand reference docs (checklists, API summaries)
└── evals/evals.json                  # Evaluation scenarios with expected behavior
tests/{skill-name}/                   # Test fixtures for offline evaluation
agents/                               # Agent configs per platform
├── claude-code/                      # Claude Code agent YAML
├── codex/                            # Codex agent instructions
└── github-copilot/                   # GitHub Copilot agent markdown
.claude-plugin/marketplace.json       # Skill registry for distribution
.codex-plugin/plugin.json             # Codex plugin manifest
Makefile                              # Test and eval targets
```

## Working on Existing Skills

1. Read the skill's `SKILL.md` to understand its workflow and allowed tools
2. Read all files in `references/` before making changes
3. Keep `SKILL.md` under ~15KB — heavy reference material belongs in `references/`

## Running Skill Evals

Each skill has an `evals/evals.json` file with evaluation scenarios. When asked to run them:

1. Read `evals/evals.json` to get the list of eval prompts and their expectations
2. For each eval, spawn a sub-agent with this prompt template:
   ```
   You are a [skill role]. Load the skill from `skills/{skill-name}/SKILL.md`
   exactly — read it first, then follow the workflow phases.

   Your task: [eval prompt from evals.json]

   Important:
   - Do not search the web, use only the skill references and your own reasoning
   - Produce the full structured report as specified in the workflow if there is one
   ```
3. Score each eval output against the `expectations` array — each expectation is a pass/fail check
4. Report results as a scorecard: eval id, pass/fail counts, and any missed expectations

The sub-agent should not be told the expectations — it must produce the correct output by following the skill workflow alone.

## Adding a New Skill

1. Create `skills/{skill-name}/` with the structure above
2. Write `SKILL.md` with frontmatter (`name`, `description`, `allowed-tools`) and a phased workflow
3. Use the existing skills as templates — read `skills/platform-engineering/SKILL.md` to match conventions:
   - Workflows are explicit step-by-step, not open-ended
   - Reference docs are actionable checklists and lookup tables, not tutorials
   - Edge cases section prevents false positives on common patterns
4. Add evaluation scenarios in `evals/evals.json` with specific expectations
5. Add test fixtures in `tests/{skill-name}/` covering distinct scenarios
6. Register the skill in `.claude-plugin/marketplace.json` under `plugins[0].skills`
7. Document the skill in `README.md` with example prompts and usage instructions
