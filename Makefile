# Moonraker — developer entry points.
#
# Cross-platform notes: this Makefile targets POSIX make. On Windows, run
# under Git Bash, MSYS2, or WSL. Native cmd users can invoke the underlying
# `lua build.lua` and `busted` commands directly.

LUA       ?= lua
BUSTED    ?= busted
LUACHECK  ?= luacheck
STYLUA    ?= stylua

DIST_DIR  := dist
BIN_NAME  := moonraker

ifeq ($(OS),Windows_NT)
  EXE := .exe
  RM_RF := cmd //C "rmdir /s /q"
else
  EXE :=
  RM_RF := rm -rf
endif

BIN := $(DIST_DIR)/$(BIN_NAME)$(EXE)

LUA_SRC := \
  src/main.lua src/cli.lua src/registry.lua src/common.lua \
  src/version.lua src/usage.lua \
  $(wildcard src/applets/*.lua)

.PHONY: all build test test-ci lint fmt fmt-check regen clean help

help:
	@echo "Moonraker — make targets"
	@echo "  build       build the moonraker binary via luastatic"
	@echo "  test        run the busted test suite"
	@echo "  test-ci     run busted with TAP output (used by CI)"
	@echo "  lint        run luacheck on src/, spec/, build.lua"
	@echo "  fmt         format Lua sources with stylua"
	@echo "  fmt-check   verify formatting without modifying files"
	@echo "  regen       regenerate src/applets/init.lua from src/applets/"
	@echo "  clean       remove build artifacts"

all: lint test-ci build

build: $(BIN)

$(BIN): $(LUA_SRC) build.lua
	$(LUA) build.lua --output $(BIN)

test:
	LUA_PATH="src/?.lua;src/?/init.lua;;" $(BUSTED)

test-ci:
	LUA_PATH="src/?.lua;src/?/init.lua;;" $(BUSTED) --run=ci

lint:
	$(LUACHECK) src spec build.lua

fmt:
	$(STYLUA) src spec build.lua

fmt-check:
	$(STYLUA) --check src spec build.lua

regen:
	$(LUA) build.lua --regen-only

clean:
	-$(RM_RF) $(DIST_DIR)
	-rm -f src/main.luastatic.c
