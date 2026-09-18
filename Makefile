# TypeVoice build. `make` builds a release .app into build/, `make run` launches it.
APP      := TypeVoice
BUNDLE   := build/$(APP).app
BIN      := .build/release/$(APP)
# Signing: a stable identity keeps Accessibility/Microphone grants across rebuilds.
# Ad-hoc ("-") changes identity on every build, so macOS forgets the grant each time.
# Auto-picks "TypeVoice Dev" (self-signed, see README) or an Apple Development cert.
SIGN_ID  ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -oE '"(TypeVoice Dev|Apple Development[^"]*)"' | head -1 | tr -d '"')
ifeq ($(SIGN_ID),)
SIGN_ID  := -
endif
CONFIG   ?= release

.PHONY: all build app run clean debug

all: app

SECRETS = Sources/TypeVoice/Support/Secrets.swift
$(SECRETS):
	@cp Secrets.example.swift $(SECRETS) && echo "created $(SECRETS) from the template (fill in the RevenueCat key when you have it)"

build: $(SECRETS)
	swift build -c $(CONFIG) 2>&1 | tail -20

app: build
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp .build/$(CONFIG)/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	@cp Packaging/Info.plist $(BUNDLE)/Contents/Info.plist
	@# SPM resource bundles (if any) live next to the binary; ship them in Resources.
	@for b in .build/$(CONFIG)/*.bundle; do [ -d "$$b" ] && cp -R "$$b" $(BUNDLE)/Contents/Resources/ || true; done
	@[ -f Packaging/AppIcon.icns ] && cp Packaging/AppIcon.icns $(BUNDLE)/Contents/Resources/ || true
	@# Ad-hoc signatures get a stable designated requirement (identifier-based) so TCC grants
	@# survive rebuilds; a real certificate gets the default (identifier + anchor).
	@if [ "$(SIGN_ID)" = "-" ]; then \
	  codesign --force --sign - --options runtime --entitlements Packaging/TypeVoice.entitlements \
	    --requirements '=designated => identifier "com.priyamventures.typevoice"' $(BUNDLE) 2>&1 | grep -v "replacing existing signature" || true; \
	else \
	  codesign --force --sign "$(SIGN_ID)" --options runtime --entitlements Packaging/TypeVoice.entitlements $(BUNDLE) 2>&1 | grep -v "replacing existing signature" || true; \
	fi
	@codesign --verify --deep --strict $(BUNDLE) && echo "signature verified" || echo "WARNING: signature invalid"
	@echo "→ $(BUNDLE)  (signed: $(SIGN_ID))"

run: app
	@pkill -x $(APP) 2>/dev/null || true
	@open $(BUNDLE)

debug:
	@$(MAKE) CONFIG=debug run


# App Store: regenerate the Xcode project, archive, and upload to App Store Connect.
# Needs DEVELOPMENT_TEAM in project.yml and teamID in Packaging/ExportOptions.plist,
# and an App Store Connect API key or an Apple ID signed in to Xcode.
.PHONY: project archive
project: $(SECRETS)
	xcodegen generate

archive: project
	@rm -rf build/TypeVoice.xcarchive
	xcodebuild -project TypeVoice.xcodeproj -scheme TypeVoice -configuration Release \
	  -archivePath build/TypeVoice.xcarchive archive 2>&1 | grep -E "error:|ARCHIVE" 
	xcodebuild -exportArchive -archivePath build/TypeVoice.xcarchive \
	  -exportOptionsPlist Packaging/ExportOptions.plist -exportPath build/export 2>&1 | grep -E "error:|EXPORT|Upload"
