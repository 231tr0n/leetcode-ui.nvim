NVIM     ?= nvim
STYLUA   ?= stylua
LUACHECK ?= luacheck
LUA_LS   ?= lua-language-server
PRETTIER ?= npx --yes prettier
GIT      ?= git

MINI_DIR    ?= $(HOME)/.local/share/nvim/site/pack/core/opt/mini.nvim
BUILD_DIR   ?= build
DOC_OUTPUT  ?= $(BUILD_DIR)/leetcode-ui.txt
LUA_LS_OUT  ?= $(BUILD_DIR)/luals-check.json
LUA_SOURCES ?= lua plugin tests scripts .luacheckrc

.PHONY: all help build bootstrap-mini deps test test-file docs docs-check format format-check luacheck luals actionlint lint check ci run clean

all: check ## Run the default checks

help: ## Show this help
	@echo "Usage: make <target>"
	@echo
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
	| sed 's/:.*## /|/' \
	| awk -F'|' '{ printf "  %-18s %s\n", $$1, $$2 }'

build:
	@mkdir -p $(BUILD_DIR)

bootstrap-mini: ## Clone mini.nvim into the standard pack directory if missing
	@if [ ! -f "$(MINI_DIR)/lua/mini/test.lua" ]; then \
		echo "Cloning mini.nvim into $(MINI_DIR)"; \
		mkdir -p "$(dir $(MINI_DIR))"; \
		$(GIT) clone --depth 1 https://github.com/echasnovski/mini.nvim.git "$(MINI_DIR)"; \
	else \
		echo "mini.nvim is already installed at $(MINI_DIR)"; \
	fi

deps: ## Report missing development dependencies
	@missing=0; \
	for command in "$(GIT)" "$(NVIM)" "$(STYLUA)" "$(LUACHECK)" "$(LUA_LS)" npx curl python3 openssl; do \
		if ! command -v "$$command" >/dev/null 2>&1; then \
			echo "missing: $$command"; \
			missing=1; \
		fi; \
	done; \
	if command -v python3 >/dev/null 2>&1 && ! python3 -c 'import sqlite3' >/dev/null 2>&1; then \
		echo "missing: python3 sqlite3 module"; \
		missing=1; \
	fi; \
	if [ ! -f "$(MINI_DIR)/lua/mini/test.lua" ]; then \
		echo "missing: mini.nvim (run 'make bootstrap-mini')"; \
		missing=1; \
	fi; \
	exit $$missing

test: ## Run the full mini.test suite
	LEETCODE_UI_MINI_DIR="$(MINI_DIR)" $(NVIM) --headless -u scripts/minitest.lua

test-file: ## Run one test file (FILE=tests/test_commands.lua)
	@if [ -z "$(FILE)" ]; then echo "usage: make test-file FILE=tests/test_commands.lua"; exit 1; fi
	LEETCODE_UI_MINI_DIR="$(MINI_DIR)" LEETCODE_UI_TEST_FILE="$(FILE)" $(NVIM) --headless -u scripts/minitest.lua

docs: ## Regenerate doc/leetcode-ui.txt and help tags
	@mkdir -p doc
	LEETCODE_UI_MINI_DIR="$(MINI_DIR)" $(NVIM) --headless -u scripts/minidoc.lua
	$(NVIM) --headless -u NONE -c 'helptags doc' -c 'qa!'

docs-check: build ## Check that generated docs match the source
	@rm -rf "$(BUILD_DIR)/doc-tags"
	LEETCODE_UI_MINI_DIR="$(MINI_DIR)" LEETCODE_UI_DOC_OUTPUT="$(DOC_OUTPUT)" $(NVIM) --headless -u scripts/minidoc.lua
	@diff -u doc/leetcode-ui.txt "$(DOC_OUTPUT)"
	@mkdir -p "$(BUILD_DIR)/doc-tags"
	@cp "$(DOC_OUTPUT)" "$(BUILD_DIR)/doc-tags/leetcode-ui.txt"
	$(NVIM) --headless -u NONE -c 'helptags $(BUILD_DIR)/doc-tags' -c 'qa!'

format: ## Format Lua and other supported files
	$(STYLUA) $(LUA_SOURCES)
	$(PRETTIER) --write .

format-check: ## Verify formatting without writing files
	$(STYLUA) --check $(LUA_SOURCES)
	$(PRETTIER) --check .

luacheck: ## Run luacheck
	$(LUACHECK) . --no-cache

luals: build ## Run LuaLS diagnostics
	$(LUA_LS) --check . --check_out_path "$(LUA_LS_OUT)"

actionlint: ## Lint GitHub Actions workflows if actionlint is installed
	@if command -v actionlint >/dev/null 2>&1; then \
	actionlint; \
	else \
	echo "actionlint is not installed; skipping workflow lint"; \
	fi

lint: luacheck luals actionlint ## Run all static checks

check: format-check lint test docs-check ## Run formatting, lint, tests, and docs checks

ci: check ## Alias for check

run: ## Start Neovim with this plugin on the runtime path
	$(NVIM) --cmd "set runtimepath^=$(CURDIR)" -c "lua require('leetcode-ui').setup({})"

clean: ## Remove build artifacts
	rm -rf $(BUILD_DIR)
