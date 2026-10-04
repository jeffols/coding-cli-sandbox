.DEFAULT_GOAL := help

IMAGE ?= pi-sandbox
CODEX_IMAGE ?= codex-sandbox
CODEX_VERSION ?= 0.160.0
CODEX_CONFIG_DIR ?= $(HOME)/.codex/pi-sandbox
DEFAULT_WORKSPACE := $(CURDIR)/workspace
WORKSPACE ?= $(DEFAULT_WORKSPACE)
DUEL_DIR ?= $(CURDIR)/duel
DOCKERFILE ?= Dockerfile.pi
PI_VERSION ?= 1.0.0
PI_CONFIG_DIR ?= $(HOME)/.pi/agent

# LLM endpoint: any OpenAI-compatible base URL (LiteLLM, api.openai.com/v1, a gateway...).
# Set in your shell or per call. Codex needs the Responses API on this endpoint.
#   LLM_BASE_URL=http://localhost:4000/v1 LLM_API_KEY=... LLM_MODEL=<id> make run
# Loopback hosts are rewritten to host.docker.internal for the container.
LLM_BASE_URL ?=
LLM_API_KEY ?=
LLM_MODEL ?=
LLM_MODELS ?=
MODEL ?= $(LLM_MODEL)
CODEX_MODEL ?= $(MODEL)
CONTAINER_LLM_BASE_URL = $(subst //localhost,//host.docker.internal,$(subst //127.0.0.1,//host.docker.internal,$(LLM_BASE_URL)))

# Optional PEM bundle of extra CA roots, for networks that intercept TLS.
# Leave unset otherwise. Set per call (make build CA_BUNDLE=/path/ca.pem) or export it in your shell.
# Proxy settings come from the standard HTTP_PROXY/HTTPS_PROXY/NO_PROXY environment variables.
CA_BUNDLE ?=
ifneq ($(CA_BUNDLE),)
ifeq ($(shell test -f "$(CA_BUNDLE)" && echo ok),)
$(error CA_BUNDLE is not a readable file: $(CA_BUNDLE))
endif
endif

.PHONY: help build run build-codex run-codex duel-setup prepare-workspace

help: ## Show targets and the variables they read
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf '\nLLM endpoint (set in your shell; any OpenAI-compatible URL):\n'
	@printf '  LLM_BASE_URL   base URL incl. /v1, e.g. http://localhost:4000/v1 or https://api.openai.com/v1\n'
	@printf '  LLM_API_KEY    bearer key (passed to the container, not stored in the image)\n'
	@printf '  LLM_MODEL      default model id (Pi: --model; Codex: config model)\n'
	@printf '  LLM_MODELS     optional comma-separated extra model ids for Pi\n'
	@printf '  MODEL          overrides the Pi model; CODEX_MODEL overrides the Codex model\n'
	@printf '\nOptional network settings:\n'
	@printf '  CA_BUNDLE      PEM file of extra CA roots (corporate TLS interception)\n'
	@printf '  HTTP_PROXY, HTTPS_PROXY, NO_PROXY   passed to the build and the container\n'
	@printf '\nOther variables:\n'
	@printf '  WORKSPACE      directory mounted at /workspace (default ./workspace)\n'
	@printf '  REPO, DUEL_DIR duel-setup source repo and clone directory\n'
	@printf '  PI_VERSION, CODEX_VERSION   image tool versions\n'
	@printf '\nExample:\n'
	@printf '  LLM_BASE_URL=http://localhost:4000/v1 LLM_API_KEY=... LLM_MODEL=openai-fast make run\n'
	@printf '  LLM_BASE_URL=http://localhost:4000/v1 LLM_API_KEY=... make run-codex CODEX_MODEL=openai5.2\n'

prepare-workspace:
	@set -eu; \
	if [ "$(abspath $(WORKSPACE))" = "$(DEFAULT_WORKSPACE)" ]; then \
	  mkdir -p "$(WORKSPACE)"; \
	fi; \
	test -d "$(WORKSPACE)" || { echo "Workspace does not exist: $(WORKSPACE)" >&2; exit 1; }

build: ## Build the Pi image
	@set -eu; \
	set -- --build-arg HTTP_PROXY --build-arg HTTPS_PROXY --build-arg NO_PROXY \
	  --build-arg "PI_VERSION=$(PI_VERSION)"; \
	if [ -n "$(CA_BUNDLE)" ]; then \
	  set -- "$$@" --secret "id=ca_bundle,src=$(CA_BUNDLE)"; \
	fi; \
	docker build -f "$(DOCKERFILE)" "$$@" -t "$(IMAGE)" .

build-codex: build ## Build the Codex image on top of the Pi image
	@set -eu; \
	set -- --build-arg HTTP_PROXY --build-arg HTTPS_PROXY --build-arg NO_PROXY \
	  --build-arg "CODEX_VERSION=$(CODEX_VERSION)" \
	  --build-arg "PI_IMAGE=$(IMAGE)"; \
	if [ -n "$(CA_BUNDLE)" ]; then \
	  set -- "$$@" --secret "id=ca_bundle,src=$(CA_BUNDLE)"; \
	fi; \
	docker build -f Dockerfile.codex "$$@" -t "$(CODEX_IMAGE)" .

run: build prepare-workspace ## Run Pi interactively against WORKSPACE
	@test -n "$${LLM_API_KEY:-}" || { echo "Set LLM_API_KEY before running Pi." >&2; exit 1; }
	@test -n "$(LLM_BASE_URL)" || { echo "Set LLM_BASE_URL (OpenAI-compatible base URL) before running Pi." >&2; exit 1; }
	@test -n "$(MODEL)" || { echo "Set LLM_MODEL (or MODEL) before running Pi." >&2; exit 1; }
	@mkdir -p "$(PI_CONFIG_DIR)"
	@set -eu; \
	no_proxy="host.docker.internal,localhost,127.0.0.1,.localhost$${NO_PROXY:+,$$NO_PROXY}"; \
	http_proxy="$${http_proxy:-$${HTTP_PROXY:-}}"; \
	https_proxy="$${https_proxy:-$${HTTPS_PROXY:-}}"; \
	set -- --rm -it \
	  -v "$(abspath $(WORKSPACE)):/workspace" \
	  -v "$(PI_CONFIG_DIR):/root/.pi/agent" \
	  -w /workspace \
	  --add-host=host.docker.internal:host-gateway \
	  -e LLM_API_KEY \
	  -e "LLM_BASE_URL=$(CONTAINER_LLM_BASE_URL)" \
	  -e "LLM_MODEL=$(MODEL)" \
	  -e "LLM_MODELS=$(MODEL),$(LLM_MODELS)" \
	  -e "HTTP_PROXY=$$http_proxy" \
	  -e "HTTPS_PROXY=$$https_proxy" \
	  -e "NO_PROXY=$$no_proxy" \
	  -e "http_proxy=$$http_proxy" \
	  -e "https_proxy=$$https_proxy" \
	  -e "no_proxy=$$no_proxy" \
	  -e NODE_USE_ENV_PROXY=1; \
	if [ -n "$(CA_BUNDLE)" ]; then \
	  set -- "$$@" -v "$(CA_BUNDLE):/run/secrets/ca_bundle:ro" \
	    -e NODE_EXTRA_CA_CERTS=/run/secrets/ca_bundle; \
	fi; \
	docker run "$$@" "$(IMAGE)" --provider llm --model "$(MODEL)"

run-codex: build-codex prepare-workspace ## Run Codex interactively against WORKSPACE
	@test -n "$${LLM_API_KEY:-}" || { echo "Set LLM_API_KEY before running Codex." >&2; exit 1; }
	@test -n "$(LLM_BASE_URL)" || { echo "Set LLM_BASE_URL (OpenAI-compatible base URL) before running Codex." >&2; exit 1; }
	@test -n "$(CODEX_MODEL)" || { echo "Set LLM_MODEL (or CODEX_MODEL) before running Codex." >&2; exit 1; }
	@mkdir -p "$(CODEX_CONFIG_DIR)"
	@set -eu; \
	no_proxy="host.docker.internal,localhost,127.0.0.1,.localhost$${NO_PROXY:+,$$NO_PROXY}"; \
	http_proxy="$${http_proxy:-$${HTTP_PROXY:-}}"; \
	https_proxy="$${https_proxy:-$${HTTPS_PROXY:-}}"; \
	set -- --rm -it \
	  -v "$(abspath $(WORKSPACE)):/workspace" \
	  -v "$(CODEX_CONFIG_DIR):/root/.codex" \
	  -w /workspace \
	  --add-host=host.docker.internal:host-gateway \
	  -e LLM_API_KEY \
	  -e "LLM_BASE_URL=$(CONTAINER_LLM_BASE_URL)" \
	  -e "LLM_MODEL=$(CODEX_MODEL)" \
	  -e "HTTP_PROXY=$$http_proxy" \
	  -e "HTTPS_PROXY=$$https_proxy" \
	  -e "NO_PROXY=$$no_proxy" \
	  -e "http_proxy=$$http_proxy" \
	  -e "https_proxy=$$https_proxy" \
	  -e "no_proxy=$$no_proxy"; \
	if [ -n "$(CA_BUNDLE)" ]; then \
	  set -- "$$@" -v "$(CA_BUNDLE):/run/secrets/ca_bundle:ro" \
	    -e NODE_EXTRA_CA_CERTS=/run/secrets/ca_bundle; \
	fi; \
	docker run "$$@" "$(CODEX_IMAGE)" --sandbox danger-full-access --model "$(CODEX_MODEL)"

# Clone twice instead of worktrees: .git stays usable inside each container.
duel-setup: ## Clone REPO twice (pi/, codex/) at the same commit for side-by-side runs
	@test -n "$(REPO)" || { echo "Pass REPO=/absolute/path/to/clean/git/repo" >&2; exit 1; }
	@set -eu; \
	repo="$$(cd "$(REPO)" && pwd -P)"; \
	test "$$(git -C "$$repo" rev-parse --show-toplevel)" = "$$repo" || { echo "REPO must be a Git repository root" >&2; exit 1; }; \
	test -z "$$(git -C "$$repo" status --porcelain)" || { echo "REPO has uncommitted changes; commit or clean it first" >&2; exit 1; }; \
	test ! -e "$(DUEL_DIR)/pi" && test ! -e "$(DUEL_DIR)/codex" || { echo "Duel workspaces already exist: $(DUEL_DIR)" >&2; exit 1; }; \
	commit="$$(git -C "$$repo" rev-parse HEAD)"; \
	mkdir -p "$(DUEL_DIR)"; \
	git clone --no-local --quiet "$$repo" "$(DUEL_DIR)/pi"; \
	git clone --no-local --quiet "$$repo" "$(DUEL_DIR)/codex"; \
	git -C "$(DUEL_DIR)/pi" checkout --quiet --detach "$$commit"; \
	git -C "$(DUEL_DIR)/codex" checkout --quiet --detach "$$commit"; \
	printf 'Two independent clones at %s: %s/{pi,codex}\n' "$$commit" "$(DUEL_DIR)"
