.PHONY: all build clean test
.SILENT:

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

SWIFTC ?= swiftc
OPT ?= opt
LLVM_AS ?= llvm-as
LINKER ?= sbpf-linker
CLANGXX ?= clang++
LLVM_CONFIG ?= llvm-config

SRC := src/entrypoint.swift
BUILD_DIR := build
BUILD_DIR_MARKER := $(BUILD_DIR)/.dir
RAW_LL_FILE := $(BUILD_DIR)/entrypoint.raw.ll
LL_FILE := $(BUILD_DIR)/entrypoint.ll
CC_LL_FILE := $(BUILD_DIR)/entrypoint.ccc.ll
BPF_LL_FILE := $(BUILD_DIR)/entrypoint.bpf.ll
BITCODE := $(BUILD_DIR)/entrypoint.bc
OUTPUT := $(BUILD_DIR)/program.so
PASS_SRC := tooling/llvm/swift_bpf_prepare_pass.cpp
PASS_SO := $(BUILD_DIR)/swift_bpf_prepare_pass.so
LLVM_LIBDIR_DEFAULT := $(shell set -e; if command -v $(LLVM_CONFIG) >/dev/null 2>&1; then $(LLVM_CONFIG) --libdir; else echo /usr/lib64/llvm20/lib64; fi)
LLVM_LIBDIR_FINAL := $(if $(LLVM_LIBDIR),$(LLVM_LIBDIR),$(LLVM_LIBDIR_DEFAULT))

all: build

build: $(OUTPUT)
	@echo "Build complete: $(OUTPUT)"

test: build
	cargo test -- --nocapture

clean:
	@echo "Removing build directory..."
	rm -rf $(BUILD_DIR)
	@echo "Cleaning cargo artifacts..."
	cargo clean

$(BUILD_DIR_MARKER):
	mkdir -p $(BUILD_DIR)
	touch "$@"

$(BUILD_DIR)/%: | $(BUILD_DIR_MARKER)

$(RAW_LL_FILE): $(SRC)
	@echo "Emitting LLVM IR from Swift..."
	$(SWIFTC) \
	    -emit-ir \
	    -O \
	    -wmo \
	    -module-name entrypoint \
	    -parse-as-library \
	    -Xfrontend -disable-stack-protector \
	    "$<" \
	    -o "$@"

$(PASS_SO): $(PASS_SRC)
	@echo "Building Swift literal LLVM pass..."
	$(CLANGXX) $$($(LLVM_CONFIG) --cxxflags) -fPIC -shared "$<" -o "$@" $$($(LLVM_CONFIG) --ldflags --system-libs --libs core Passes)

$(LL_FILE): $(RAW_LL_FILE) $(PASS_SO)
	@echo "Normalizing Swift IR via LLVM passes..."
	TMP_LL="$@.tmp"; \
	$(OPT) -load-pass-plugin "$(PASS_SO)" -passes=swift-literal-normalize,swift-cc-normalize -S "$<" -o "$$TMP_LL"; \
	mv "$$TMP_LL" "$@"

$(CC_LL_FILE): $(LL_FILE)
	@echo "Preparing IR for BPF..."
	cp "$<" "$@"

$(BPF_LL_FILE): $(CC_LL_FILE)
	@echo "Retargeting module to BPF..."
	$(OPT) -S -mtriple=bpfel -o "$@" "$<"

$(BITCODE): $(BPF_LL_FILE)
	@echo "Assembling bitcode..."
	$(LLVM_AS) "$<" -o "$@"


$(OUTPUT): $(BITCODE)
	@echo "Linking with sbpf-linker..."
	LD_LIBRARY_PATH="$(LLVM_LIBDIR_FINAL)$${LD_LIBRARY_PATH:+:$${LD_LIBRARY_PATH}}" \
	$(LINKER) \
	    --cpu v3 \
		--export entrypoint \
	    -o "$@" \
	    "$(BITCODE)"
