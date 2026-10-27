.PHONY: test generate build cli

test:
	cd Packages/CleanerKit && swift test

generate:
	xcodegen generate

build: generate
	xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Debug -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- build

cli:
	cd Packages/CleanerKit && swift build -c release --product cleaner
