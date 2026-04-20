SWIFT_PATHS := WhisperDB WhisperDBiOS WhisperDBKit Package.swift

.PHONY: format lint build

format:
	swift format --in-place --recursive $(SWIFT_PATHS)

lint:
	swift format lint --strict --recursive $(SWIFT_PATHS)

build:
	swift build
