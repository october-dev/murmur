PROTO_FILES := $(shell find spec/proto -name '*.proto' -type f | sort)

.PHONY: check check-protocol check-conformance check-dart check-flutter check-flutter-plugin check-typescript check-python check-rust

check: check-protocol check-conformance check-dart check-flutter check-flutter-plugin check-typescript check-python check-rust

check-protocol:
	@descriptor="$$(mktemp)"; \
	trap 'rm -f "$$descriptor"' EXIT; \
	protoc --proto_path=spec/proto --include_imports --descriptor_set_out="$$descriptor" $(PROTO_FILES)

check-conformance:
	python3 tool/check_conformance.py

check-dart:
	cd sdks/dart/murmur_protocol && dart pub get && dart format --output=none --set-exit-if-changed . && dart analyze && dart test

check-flutter:
	cd apps/flutter && flutter pub get && flutter analyze && flutter test

check-flutter-plugin:
	cd packages/flutter/murmur_flutter && flutter pub get && flutter analyze

check-typescript:
	cd sdks/typescript && npm ci && npm run check && npm test

check-python:
	python3 -m unittest discover -s sdks/python/tests -v

check-rust:
	cd sdks/rust/murmur-protocol && cargo test
