.PHONY: test generate build build-signed cli

test:
	cd Packages/CleanerKit && swift test

generate:
	xcodegen generate

# On a fresh package resolve, Xcode writes the app's whole package graph (including Sparkle) into
# the local package's Package.resolved. CleanerKit does not depend on Sparkle, so its own file is
# saved before xcodebuild and put back afterwards. Sparkle is pinned in project.yml instead.
KEEP_RESOLVED = mkdir -p .build && cp Packages/CleanerKit/Package.resolved .build/CleanerKit-Package.resolved.keep
RESTORE_RESOLVED = cp .build/CleanerKit-Package.resolved.keep Packages/CleanerKit/Package.resolved

build: generate
	@$(KEEP_RESOLVED)
	xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Debug -derivedDataPath .build/xcode \
		CODE_SIGN_IDENTITY=- $(XCODEBUILD_FLAGS) build; status=$$?; $(RESTORE_RESOLVED); exit $$status

# Needs a development certificate and team: enables the App Group and the widget sandbox.
build-signed: generate
	@$(KEEP_RESOLVED)
	xcodebuild -project Cleaner.xcodeproj -scheme Cleaner -configuration Debug -derivedDataPath .build/xcode \
		CLEANER_APP_ENTITLEMENTS=Config/Cleaner.entitlements \
		CLEANER_WIDGET_ENTITLEMENTS=Config/CleanerWidgets.entitlements build; status=$$?; $(RESTORE_RESOLVED); exit $$status

cli:
	cd Packages/CleanerKit && swift build -c release --product cleaner
