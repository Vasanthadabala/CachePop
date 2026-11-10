"""Finder layout for the CachePop drag-to-install disk image."""

from pathlib import Path

files = [str(Path(defines["app"]).resolve())]
symlinks = {"Applications": "/Applications"}
# Do not set FinderInfo on the signed app to hide its extension: that invalidates its signature.

format = "ULFO"
filesystem = "HFS+"
background = str(Path(defines["background"]).resolve())
window_rect = ((240, 180), (760, 508))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
include_icon_view_settings = True
include_list_view_settings = False
show_icon_preview = False
arrange_by = None
grid_spacing = 72
scroll_position = (0, 0)
icon_size = 104
# Finder fixes native captions to black. Place them beside the icons on the black canvas;
# the Retina artwork supplies the visible white captions below, without altering the app.
text_size = 10
label_pos = "right"
icon_locations = {"CachePop.app": (206, 270), "Applications": (554, 270)}
