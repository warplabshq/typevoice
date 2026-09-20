# TypeVoice build. `make` builds a release .app into build/, `make run` launches it,
# `make release` signs it with Developer ID, notarizes it and writes the Sparkle appcast.
APP      := TypeVoice
BUNDLE   := build/$(APP).app
CONFIG   ?= release
SPARKLE  := .build/artifacts/sparkle/Sparkle
ENTITLEMENTS := Packaging/$(APP).entitlements

# Day-to-day signing: a stable identity keeps Accessibility/Microphone grants across rebuilds.
# Ad-hoc ("-") changes identity on every build, so macOS would forget the grant each time;
# the Makefile pins an identifier-based designated requirement instead.
# Auto-picks "TypeVoice Dev" (self-signed, see README) or an Apple Development cert.
SIGN_ID  ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -oE '"(TypeVoice Dev|Apple Development[^"]*)"' | head -1 | tr -d '"')
ifeq ($(SIGN_ID),)
SIGN_ID  := -
endif

# Release signing: the Developer ID Application certificate from your Apple Developer account,
# and a notarytool keychain profile (`xcrun notarytool store-credentials TypeVoice`).
RELEASE_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -oE '"Developer ID Application[^"]*"' | head -1 | tr -d '"')
NOTARY_PROFILE ?= TypeVoice
# Downloads live in the public releases-only repo (the source repo is private); the appcast
# points there and the site's Download button serves its latest release.
RELEASES_REPO ?= warplabshq/typevoice-releases
DOWNLOAD_URL ?= https://github.com/$(RELEASES_REPO)/releases/download/v$(VERSION)/
SITE_DIR ?= ../TypeVoiceSite
VERSION  := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Packaging/Info.plist)

.PHONY: all build app run debug clean release notarize appcast keys icon notes publish

all: app

build:
	swift build -c $(CONFIG) 2>&1 | tail -20

app: build
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources $(BUNDLE)/Contents/Frameworks
	@cp .build/$(CONFIG)/$(APP) $(BUNDLE)/Contents/MacOS/$(APP)
	@cp Packaging/Info.plist $(BUNDLE)/Contents/Info.plist
	@# SPM resource bundles (if any) live next to the binary; ship them in Resources.
	@for b in .build/$(CONFIG)/*.bundle; do [ -d "$$b" ] && cp -R "$$b" $(BUNDLE)/Contents/Resources/ || true; done
	@[ -f Packaging/AppIcon.icns ] && cp Packaging/AppIcon.icns $(BUNDLE)/Contents/Resources/ || true
	@# Sparkle ships as a dynamic framework; embed it where the rpath expects it. Its XPC
	@# services only matter for sandboxed apps, so they stay out of the bundle.
	@cp -R $(SPARKLE)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(BUNDLE)/Contents/Frameworks/
	@rm -rf $(BUNDLE)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices
	@$(MAKE) --no-print-directory sign IDENTITY="$(SIGN_ID)"
	@echo "→ $(BUNDLE)  (signed: $(SIGN_ID))"

# Inside-out signing: Sparkle's nested helpers first, then the framework, then the app.
# Ad-hoc signatures get an identifier-based designated requirement so TCC grants survive
# rebuilds, and skip the hardened runtime (its library validation refuses an ad-hoc framework
# in an ad-hoc process); a real certificate gets the default requirement and the runtime.
sign:
	@F=$(BUNDLE)/Contents/Frameworks/Sparkle.framework; \
	 codesign -f -s "$(IDENTITY)" -o runtime $$F/Versions/B/Autoupdate 2>&1 | grep -v "replacing existing" || true; \
	 codesign -f -s "$(IDENTITY)" -o runtime $$F/Versions/B/Updater.app 2>&1 | grep -v "replacing existing" || true; \
	 codesign -f -s "$(IDENTITY)" -o runtime $$F 2>&1 | grep -v "replacing existing" || true
	@if [ "$(IDENTITY)" = "-" ]; then \
	  codesign -f -s - --entitlements $(ENTITLEMENTS) \
	    --requirements '=designated => identifier "com.priyamventures.typevoice"' $(BUNDLE) 2>&1 | grep -v "replacing existing" || true; \
	else \
	  codesign -f -s "$(IDENTITY)" -o runtime --timestamp --entitlements $(ENTITLEMENTS) $(BUNDLE) 2>&1 | grep -v "replacing existing" || true; \
	fi
	@codesign --verify --deep --strict $(BUNDLE) && echo "signature verified" || echo "WARNING: signature invalid"

run: app
	@pkill -x $(APP) 2>/dev/null || true
	@open $(BUNDLE)

debug:
	@$(MAKE) CONFIG=debug run

clean:
	rm -rf .build build dist

# ---- Release ------------------------------------------------------------------------
# make release → dist/TypeVoice-<version>.zip (Sparkle update), dist/TypeVoice.dmg (the site's
# Download button) and dist/appcast.xml. Copy appcast.xml into the site repo and upload the
# zip + dmg to the GitHub release tagged v<version>.
release: app notes
	@[ -n "$(RELEASE_ID)" ] || { echo "No Developer ID Application certificate in the keychain (see README › Releasing)"; exit 1; }
	@$(MAKE) --no-print-directory sign IDENTITY="$(RELEASE_ID)"
	@mkdir -p dist && rm -f dist/$(APP)-$(VERSION).zip dist/$(APP).dmg
	@ditto -c -k --keepParent $(BUNDLE) dist/$(APP)-$(VERSION).zip
	@$(MAKE) --no-print-directory notarize FILE=dist/$(APP)-$(VERSION).zip
	@xcrun stapler staple $(BUNDLE) && rm -f dist/$(APP)-$(VERSION).zip && ditto -c -k --keepParent $(BUNDLE) dist/$(APP)-$(VERSION).zip
	@$(MAKE) --no-print-directory dmg
	@$(MAKE) --no-print-directory appcast
	@echo "→ dist/$(APP)-$(VERSION).zip  dist/$(APP).dmg  dist/appcast.xml"

notarize:
	xcrun notarytool submit $(FILE) --keychain-profile $(NOTARY_PROFILE) --wait

# A plain DMG: the app plus an Applications shortcut. Notarized and stapled on its own.
dmg:
	@rm -rf build/dmg && mkdir -p build/dmg
	@cp -R $(BUNDLE) build/dmg/ && ln -s /Applications build/dmg/Applications
	@hdiutil create -quiet -volname $(APP) -srcfolder build/dmg -ov -format UDZO dist/$(APP).dmg
	@codesign -f -s "$(RELEASE_ID)" --timestamp dist/$(APP).dmg
	@$(MAKE) --no-print-directory notarize FILE=dist/$(APP).dmg
	@xcrun stapler staple dist/$(APP).dmg

# After `make release`: the GitHub release (zip + dmg + notes) and the appcast on the site.
publish:
	gh release create v$(VERSION) dist/$(APP)-$(VERSION).zip dist/$(APP).dmg --repo $(RELEASES_REPO) \
	  --title "TypeVoice $(VERSION)" --notes-file dist/$(APP)-$(VERSION).html
	cp dist/appcast.xml $(SITE_DIR)/appcast.xml && $(MAKE) -C $(SITE_DIR) deploy
	@echo "→ https://github.com/$(RELEASES_REPO)/releases/tag/v$(VERSION)"

# Sparkle appcast from the zips in dist/updates/ (the dmg must not sit beside them: generate_appcast
# refuses two archives of one version). Needs the EdDSA private key in the login keychain
# (`make keys`, once). Release notes: dist/updates/TypeVoice-<version>.html next to the zip.
appcast:
	@mkdir -p dist/updates && cp dist/$(APP)-$(VERSION).zip dist/$(APP)-$(VERSION).html dist/updates/
	$(SPARKLE)/bin/generate_appcast --download-url-prefix "$(DOWNLOAD_URL)" --embed-release-notes -o dist/appcast.xml dist/updates/

# Release notes for Sparkle: the top CHANGELOG.md entry as a small HTML page next to the zip.
notes:
	@mkdir -p dist
	@python3 -c 'import re,sys,html; t=open("CHANGELOG.md").read(); m=re.search(r"^## (.+?)\n(.*?)(?=^## |\Z)", t, re.S|re.M); title,body=m.group(1),m.group(2).strip(); 	items=[html.escape(re.sub(r"\s+"," ",i.strip())) for i in re.split(r"^- ", body, flags=re.M)[1:]]; intro=html.escape(body.split("\n- ")[0].strip()) if not body.startswith("- ") else ""; 	print("<!doctype html><meta charset=utf-8><style>body{font:14px/1.5 -apple-system,system-ui;color:#222;margin:16px 20px}h1{font-size:17px;margin:0 0 8px}li{margin:4px 0}@media(prefers-color-scheme:dark){body{color:#ddd;background:#1e1e1e}}</style>" 	+"<h1>TypeVoice "+html.escape(title)+"</h1>"+("<p>"+intro+"</p>" if intro else "")+"<ul>"+"".join("<li>"+i+"</li>" for i in items)+"</ul>")' > dist/$(APP)-$(VERSION).html
	@echo "→ dist/$(APP)-$(VERSION).html"

# One-time: EdDSA key pair for update signing. Prints the public key for SUPublicEDKey in
# Packaging/Info.plist; the private key lives in your login keychain. Back it up (-x).
keys:
	$(SPARKLE)/bin/generate_keys

# Regenerate Packaging/AppIcon.icns from Tools/icon.swift.
icon:
	@rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
	@swift Tools/icon.swift build/AppIcon.iconset
	@cd build/AppIcon.iconset && for s in 16 32 128 256 512; do \
	   cp icon_$$s.png icon_$${s}x$${s}.png; d=$$((s*2)); cp icon_$$d.png icon_$${s}x$${s}@2x.png; done && rm icon_[0-9]*.png
	@iconutil -c icns build/AppIcon.iconset -o Packaging/AppIcon.icns && echo "→ Packaging/AppIcon.icns"
