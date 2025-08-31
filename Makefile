# Makefile for injectable build_runner tasks

.PHONY: build watch clean rebuild

## Run code generation once
build:
	flutter pub run build_runner build --delete-conflicting-outputs

## Continuously watch for code changes and regenerate
watch:
	flutter pub run build_runner watch --delete-conflicting-outputs

## Clean generated files
clean:
	flutter clean
	rm -rf lib/**.g.dart lib/**.config.dart
	rm -rf .dart_tool build

## Clean and rebuild all generated files
rebuild: clean build

