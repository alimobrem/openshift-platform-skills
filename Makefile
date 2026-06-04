TEST_DIR := tests/platform-audit

.PHONY: help test-evals

test-evals: ## Run platform-engineering skill evals
	@echo "Running platform-engineering evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-engineering/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-engineering/SKILL.md first, then follows the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'
