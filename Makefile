# Murmur build. `make` builds a release .app into build/, `make run` launches it.
APP      := Murmur
BUNDLE   := build/$(APP).app
BIN      := .build/release/$(APP)
# Signing: a stable identity keeps Accessibility/Microphone grants across rebuilds.
# Ad-hoc ("-") changes identity on every build, so macOS forgets the grant each time.
# Auto-picks "Murmur Dev" (self-signed, see README) or an Apple Development cert.
SIGN_ID  ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -oE '"(Murmur Dev|Apple Development[^"]*)"' | head -1 | tr -d '"')
ifeq ($(SIGN_ID),)
SIGN_ID  := -
endif
CONFIG   ?= release

.PHONY: all build app run clean debug

all: app

build:
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
	  codesign --force --deep --sign - --options runtime --entitlements Packaging/Murmur.entitlements \
	    --requirements '=designated => identifier "com.priyam.murmur"' $(BUNDLE) 2>&1 | grep -v "replacing existing signature" || true; \
	else \
	  codesign --force --deep --sign "$(SIGN_ID)" --options runtime --entitlements Packaging/Murmur.entitlements $(BUNDLE) 2>&1 | grep -v "replacing existing signature" || true; \
	fi
	@echo "→ $(BUNDLE)  (signed: $(SIGN_ID))"

run: app
	@pkill -x $(APP) 2>/dev/null || true
	@open $(BUNDLE)

debug:
	@$(MAKE) CONFIG=debug run

clean:
	rm -rf .build build
