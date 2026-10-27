.PHONY: test generate build build-signed cli

test:
	cd Packages/SweepkeyKit && swift test

generate:
	xcodegen generate

# On a fresh package resolve, Xcode writes the app's whole package graph (including Sparkle) into
# the local package's Package.resolved. SweepkeyKit does not depend on Sparkle, so its own file is
# saved before xcodebuild and put back afterwards. Sparkle is pinned in project.yml instead.
KEEP_RESOLVED = mkdir -p .build && cp Packages/SweepkeyKit/Package.resolved .build/SweepkeyKit-Package.resolved.keep
RESTORE_RESOLVED = cp .build/SweepkeyKit-Package.resolved.keep Packages/SweepkeyKit/Package.resolved

build: generate
	@$(KEEP_RESOLVED)
	xcodebuild -project Sweepkey.xcodeproj -scheme Sweepkey -configuration Debug -derivedDataPath .build/xcode \
		CODE_SIGN_IDENTITY=- $(XCODEBUILD_FLAGS) build; status=$$?; $(RESTORE_RESOLVED); exit $$status

# Needs a development certificate and team: enables the App Group and the widget sandbox.
build-signed: generate
	@$(KEEP_RESOLVED)
	xcodebuild -project Sweepkey.xcodeproj -scheme Sweepkey -configuration Debug -derivedDataPath .build/xcode \
		SWEEPKEY_APP_ENTITLEMENTS=Config/Sweepkey.entitlements \
		SWEEPKEY_WIDGET_ENTITLEMENTS=Config/SweepkeyWidgets.entitlements build; status=$$?; $(RESTORE_RESOLVED); exit $$status

cli:
	cd Packages/SweepkeyKit && swift build -c release --product sweepkey
