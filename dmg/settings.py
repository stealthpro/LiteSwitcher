"""dmgbuild settings for the LiteSwitcher DMG window.

Run from make-dmg.sh: the app and background paths are passed via -D.
See https://dmgbuild.readthedocs.io for the full settings reference.
"""
import os.path

app = defines["app"]
appname = os.path.basename(app)

# Compressed, read-only image (same as the old hdiutil -format UDZO).
format = "UDZO"

files = [app]
symlinks = {"Applications": "/Applications"}

# Custom window background (the arrow is drawn into the image itself).
background = defines["background"]

# Big icons: the app on the left, Applications on the right. Coordinates are
# the CENTER of each icon, from the top-left of the window. Keep in sync with
# dmg/make-background.py.
icon_locations = {
    appname: (170, 160),
    "Applications": (490, 160),
}

window_rect = ((100, 100), (660, 400))
default_view = "icon-view"
icon_size = 128
text_size = 16
label_pos = "bottom"
arrange_by = None

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
