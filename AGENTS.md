# Agent Instructions

This repository contains AI agent skills for OpenShift platform engineering — Shipwright,
Tekton, Quay, External Secrets, Istio/OSSM, progressive delivery, and DORA metrics.

## Repository Layout

```
skills/
├── platform-ci/                      # Build + pipeline skill
│   ├── SKILL.md
│   ├── references/
│   │   ├── shipwright.md
│   │   └── tekton.md
│   └── evals/evals.json
├── platform-mesh/                    # Service mesh skill
│   ├── SKILL.md
│   ├── references/
│   │   └── istio.md
│   └── evals/evals.json
├── platform-infra/                   # Registry + secrets skill
│   ├── SKILL.md
│   ├── references/
│   │   ├── quay.md
│   │   └── external-secrets.md
│   └── evals/evals.json
├── platform-integration/             # Cross-layer integration skill
│   ├── SKILL.md
│   ├── references/
│   │   ├── delivery-flows.md
│   │   ├── platform-onboarding.md
│   │   ├── dora-metrics.md
│   │   └── troubleshooting.md
│   ├── scripts/
│   │   ├── health-check.sh
│   │   ├── discover.sh
│   │   └── validate.sh
│   ├── assets/schemas/               # CRD JSON schemas for validation
│   └── evals/evals.json
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

1. Read the target skill's `SKILL.md` to understand its scope and CRD ownership
2. Read the reference files in that skill's `references/` directory before making changes
3. Check sibling skills to avoid duplicating CRD tables or reference content
4. Keep `SKILL.md` under ~15KB — heavy reference material belongs in `references/`

## Running Skill Evals

Each skill has its own `evals/evals.json` file. Run evals per-skill or all at once:

```bash
make test-ci           # platform-ci evals (3)
make test-mesh         # platform-mesh evals (3)
make test-infra        # platform-infra evals (2)
make test-integration  # platform-integration evals (4)
make test-all          # all 12 evals
make test-scripts      # shell script tests against fixtures
```

When running evals manually:

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
3. Use the existing skills as templates — read any `skills/*/SKILL.md` to match conventions:
   - Workflows are explicit step-by-step, not open-ended
   - Reference docs are actionable checklists and lookup tables, not tutorials
   - Edge cases section prevents false positives on common patterns
4. Add evaluation scenarios in `evals/evals.json` with specific expectations
5. Add test fixtures in `tests/{skill-name}/` covering distinct scenarios
6. Register the skill in `.claude-plugin/marketplace.json` under `plugins[0].skills`
7. Document the skill in `README.md` with example prompts and usage instructions
