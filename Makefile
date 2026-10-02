.PHONY: generate build test install clean

PROJECT   := Nag.xcodeproj
BUILD_DIR := build
APP       := $(BUILD_DIR)/Build/Products/Release/Nag.app

generate:
	xcodegen generate

build: generate
	xcodebuild build -project $(PROJECT) -scheme Nag -configuration Release \
		-derivedDataPath $(BUILD_DIR) -destination 'platform=macOS' -quiet

test: generate
	xcodebuild test -project $(PROJECT) -scheme Nag \
		-derivedDataPath $(BUILD_DIR) -destination 'platform=macOS' -quiet

install: build
	rm -rf /Applications/Nag.app
	cp -R $(APP) /Applications/Nag.app

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)
