# dmgbuild settings for the Sweepkey installer window (used by scripts/make-dmg.sh).
# Pass the app with: dmgbuild -s scripts/dmg-settings.py -D app=/path/Sweepkey.app "Sweepkey" out.dmg
import os.path

app = defines["app"]  # noqa: F821 (injected by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {app_name: (170, 200), "Applications": (490, 200)}

# The window matches Branding/dmg-background.svg (660x400 points).
background = "Branding/dmg-background.tiff"  # relative to the repo root; make-dmg.sh runs from there
window_rect = ((200, 160), (660, 428))  # 400pt background + the title bar
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
arrange_by = None
