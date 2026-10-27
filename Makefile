.PHONY: test generate build build-signed cli

test:
	cd Packages/CleanerKit && swift test

generate:
	xcodegen generate

build: generate
	xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Debug -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- build

# Needs a development certificate and team: enables the App Group and the widget sandbox.
build-signed: generate
	xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Debug -derivedDataPath .build/xcode \
		CLEANER_APP_ENTITLEMENTS=Config/Cleaner.entitlements \
		CLEANER_WIDGET_ENTITLEMENTS=Config/CleanerWidgets.entitlements build

cli:
	cd Packages/CleanerKit && swift build -c release --product cleaner
