# dmgbuild settings for the download image: the app on the left, Applications on the right,
# a hairline arrow between them on a light field (Tools/dmgbg.swift draws the background;
# its icon centres must match icon_locations below). Used by `make dmg`.
#   dmgbuild -s Packaging/dmg.py -D app=build/TypeVoice.app TypeVoice dist/TypeVoice.dmg
import os.path

app = defines.get("app", "build/TypeVoice.app")  # noqa: F821 (dmgbuild injects `defines`)
here = "Packaging"  # run from the repo root, as make does

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = ["TypeVoice.app"]
icon = os.path.join(here, "AppIcon.icns")            # the mounted volume wears the app icon

background = os.path.join(here, "dmg-background.png")   # dmgbuild pairs it with the @2x for Retina
window_rect = ((240, 180), (660, 430))   # frame incl. title bar; the image is taller than any content area
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {"TypeVoice.app": (170, 165), "Applications": (490, 165)}
include_icon_view_settings = "auto"
