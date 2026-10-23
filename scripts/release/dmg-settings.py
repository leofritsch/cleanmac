# dmgbuild settings for the installer window. Paths come in with -D app=… -D background=… -D volicon=… (optional)
# dmgbuild writes the window layout itself (no Finder scripting), so builds are repeatable and need no permissions.
import os.path

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(app)

format = "ULFO"  # LZFSE: small and fast to open (macOS 10.11+)
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("volicon")  # noqa: F821
background = defines["background"]  # noqa: F821

# Window bounds include the title bar (and Finder's tab bar when the user shows it), so the window is as tall as
# the 440 pt background: the composition sits in its top part and survives either chrome.
window_rect = ((240, 160), (640, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 120
text_size = 13
arrange_by = None
icon_locations = {appname: (165, 165), "Applications": (475, 165)}
