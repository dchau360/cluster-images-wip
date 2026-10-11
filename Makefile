# cluster-images-wip — node image builds.
#
#   make build            build every image definition
#   make build IMAGE=x    build one
#   make import           import built images into Warewulf
#   make lint             the same gates CI runs

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

REPO_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
export REPO_ROOT

S := $(REPO_ROOT)/scripts
RUN := bash

IMAGE ?=
export IMAGE

.PHONY: help build import images timings lint lint-yaml lint-shell \
        lint-containerfiles secrets tracked-secrets check-host-values clean

help: ## Show this help
	@printf 'cluster-images-wip\n\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@printf '\none image:    make build IMAGE=compute-base\n'

build: ## Build every image definition, or one with IMAGE=<name>
	@$(RUN) $(S)/build.sh

import: ## Import built images into Warewulf
	@$(RUN) $(S)/import.sh

images: ## List the image definitions found under images/
	@$(RUN) -c 'source $(S)/lib/common.sh; lab_load_env; lab_image_names'

timings: ## Print the timing table for the most recent build
	@$(RUN) -c 'source $(S)/lib/common.sh; lab_load_env; source $(S)/lib/timing.sh; timing_report'

# --- repo hygiene. Same checks CI runs. ------------------------------------
#
# A gate whose tool is missing must say so. Bare `gitleaks` exits 127 and make
# does fail, but the message is "command not found", which reads like a broken
# gate rather than an uninstalled one. A leak gate is never skipped: a skipped
# gate and a passing gate look identical in a log, and only one of them is safe.
need = @command -v $(1) >/dev/null 2>&1 || { \
	  printf 'error: %s not found, so this gate cannot run.\n       %s\n' '$(1)' '$(2)' >&2; \
	  exit 127; }

lint: check-host-values secrets tracked-secrets lint-yaml lint-shell lint-containerfiles ## Run every repo gate

check-host-values: ## Fail if any host-specific value is in a tracked file
	@$(RUN) $(S)/check-no-host-values.sh

secrets: ## Run gitleaks over the worktree and the full history
	$(call need,gitleaks,See docs/lab-host-setup.md in the platform repo.)
	@gitleaks dir . --redact --no-banner --verbose
	@gitleaks git . --redact --no-banner

tracked-secrets: ## Fail if a tracked file is named or placed like key material
	@$(RUN) $(S)/check-no-tracked-secrets.sh

lint-yaml: ## yamllint
	$(call need,yamllint,See docs/lab-host-setup.md in the platform repo.)
	@yamllint -s .

lint-shell: ## shellcheck
	$(call need,shellcheck,See docs/lab-host-setup.md in the platform repo.)
	@shellcheck -x -S style -P SCRIPTDIR $$(git ls-files '*.sh')

# hadolint is a style linter, not a leak gate, so a local skip is safe. It is
# announced, and CI runs it unconditionally.
lint-containerfiles: ## hadolint, if installed
	@if command -v hadolint >/dev/null 2>&1; then \
	  hadolint --failure-threshold error $$(git ls-files '*Containerfile'); \
	else \
	  echo "SKIPPED: hadolint not installed locally; CI runs it"; \
	fi

clean: ## Remove built image artefacts from the build directory
	@$(RUN) -c 'source $(S)/lib/common.sh; lab_load_env; \
	  rm -rf "$$IMAGE_BUILD_DIR"/* 2>/dev/null || sudo rm -rf "$$IMAGE_BUILD_DIR"/*; \
	  echo "cleaned $$IMAGE_BUILD_DIR"'
