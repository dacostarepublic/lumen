SHELL := /bin/bash

.DEFAULT_GOAL := help

VERSION ?= 1.1.0
ARTIFACT_NAME := lumen-v$(VERSION)-macos.tar.gz
ARTIFACT_PATH := dist/$(ARTIFACT_NAME)

.PHONY: help build build-release test ci smoke release-artifact clean

help:
	@printf "Available targets:\n"
	@printf "  make build             Build debug binary\n"
	@printf "  make build-release     Build release binary\n"
	@printf "  make test              Run unit tests\n"
	@printf "  make ci                Run release build + tests\n"
	@printf "  make smoke             Run CLI smoke checks\n"
	@printf "  make release-artifact VERSION=1.1.0\n"
	@printf "                         Build and package release artifact\n"
	@printf "  make clean             Remove build and dist artifacts\n"

build:
	swift build

build-release:
	swift build -c release

test:
	swift test

ci:
	swift build -c release && swift test

smoke:
	swift run lumen --version
	swift run lumen config path

release-artifact: build-release
	mkdir -p dist
	cp .build/release/lumen dist/lumen
	tar -czf "$(ARTIFACT_PATH)" -C dist lumen
	shasum -a 256 "$(ARTIFACT_PATH)" > "$(ARTIFACT_PATH).sha256"
	@printf "Created %s and %s.sha256\n" "$(ARTIFACT_PATH)" "$(ARTIFACT_PATH)"

clean:
	rm -rf .build dist
