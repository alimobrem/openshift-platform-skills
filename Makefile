SCHEMAS_DIR := skills/platform-integration/assets/schemas

.PHONY: help test-ci test-mesh test-infra test-integration test-all test-scripts download-schemas

test-ci: ## Run platform-ci evals
	@echo "Running platform-ci evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-ci/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-ci/SKILL.md first, then follows the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

test-mesh: ## Run platform-mesh evals
	@echo "Running platform-mesh evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-mesh/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-mesh/SKILL.md first, then follows the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

test-infra: ## Run platform-infra evals
	@echo "Running platform-infra evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-infra/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-infra/SKILL.md first, then follows the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

test-integration: ## Run platform-integration evals
	@echo "Running platform-integration evals..."
	@claude --print --dangerously-skip-permissions \
		"Read skills/platform-integration/evals/evals.json. For each eval: \
		1. Spawn a sub-agent that reads skills/platform-integration/SKILL.md first, then follows the skill workflow. \
		2. Score the output against the expectations array. \
		Report a scorecard table: eval id, passed/total, and list any failed expectations."

test-all: test-ci test-mesh test-infra test-integration ## Run all skill evals

test-scripts: ## Run script tests against fixtures
	@echo "Testing discover.sh..."
	@bash skills/platform-integration/scripts/discover.sh -d tests/platform-audit/full-stack
	@echo ""
	@echo "Testing validate.sh..."
	@bash skills/platform-integration/scripts/validate.sh -d tests/platform-audit/full-stack; echo "Exit code: $$?"

download-schemas: ## Download CRD JSON schemas for platform validation
	@mkdir -p $(SCHEMAS_DIR)
	@echo "Downloading platform CRD schemas..."
	curl -sL "https://json.schemastore.org/tekton-pipeline.json" -o "$(SCHEMAS_DIR)/pipeline-tekton.dev-v1.json"
	curl -sL "https://json.schemastore.org/tekton-task.json" -o "$(SCHEMAS_DIR)/task-tekton.dev-v1.json"
	@echo "Done. Remaining schemas require yq — see README."

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'
