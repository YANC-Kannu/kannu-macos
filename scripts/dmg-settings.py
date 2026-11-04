# dmgbuild settings for Kannu's install window. scripts/create-dmg.sh runs this through dmgbuild, which
# provides `defines` and reads the names assigned here. dmgbuild writes this layout straight into the
# volume's .DS_Store, so a build never scripts Finder, opens a window or raises an Automation prompt.
#
# The window size and the two icon centres must match InstallWindow in
# scripts/brand/generate-brand-assets.swift, which draws the heading and arrow around them.
import os.path

application = defines["app"]
brand_dir = defines["brand_dir"]
app_name = os.path.basename(application.rstrip("/"))

format = "UDZO"

files = [application]
symlinks = {"Applications": "/Applications"}

icon = os.path.join(brand_dir, "VolumeIcon.icns")
# dmgbuild finds dmg-background@2x.png beside this file and merges the pair into .background.tiff.
background = os.path.join(brand_dir, "dmg-background.png")
hide = [".background.tiff", ".VolumeIcon.icns"]

default_view = "icon-view"
window_rect = ((200, 140), (660, 420))
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (185, 236),
    "Applications": (475, 236),
}
