# VPN Menu Bar

A macOS app that adds a VPN picker to the menu bar, since Apple did not include this feature properly.

You can build it yourself with `build.sh`, but there is also a prebuilt release version.<br>
The release version is unsigned, so use this command to unblock it (with your own path tho):
```bash
xattr -dr com.apple.quarantine /Applications/VPNMenuBar.app
```
