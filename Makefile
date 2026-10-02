.PHONY: generate icon build test install clean

PROJECT      := Nag.xcodeproj
BUILD_DIR    := build
APP          := $(BUILD_DIR)/Build/Products/Release/Nag.app
VERSION      := $(shell tr -d '[:space:]' < VERSION)
BUILD_NUMBER := $(shell git rev-list --count HEAD)
XCB_VERSION  := MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

generate:
	xcodegen generate

icon:
	swift scripts/make-icon.swift

build: generate
	xcodebuild build -project $(PROJECT) -scheme Nag -configuration Release \
		-derivedDataPath $(BUILD_DIR) -destination 'platform=macOS' -quiet $(XCB_VERSION)

test: generate
	xcodebuild test -project $(PROJECT) -scheme Nag \
		-derivedDataPath $(BUILD_DIR) -destination 'platform=macOS' -quiet $(XCB_VERSION)

install: build
	rm -rf /Applications/Nag.app
	cp -R $(APP) /Applications/Nag.app

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)
