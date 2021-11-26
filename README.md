# Snapshot Explorer

Snapshot Explorer is a work-in-progress GTK-based application for browsing ZFS
snapshots using the system file manager (e.g. Nautilus on GNOME).

![Screenshot of the application](data/screenshot.png?raw=true)

It also includes a standalone Nautilus extension to enable easy restoration of
earlier versions of a file from a ZFS snapshot.

![Screenshot of the Nautilus extension](data/nautilus-screenshot.png?raw=true)

Together these give an experience similar to Time Machine on macOS, the
["Previous Versions"
feature](https://pureinfotech.com/enable-previous-versions-recover-files-windows-10/)
on Windows, or the [TimeSlider Nautilus
patches](https://distrowatch.com/images/screenshots/openindiana-2019.10-caja-time-slider.png)
from OpenSolaris and its descendants -- all of which inspired this tool.

Snapshot Explorer is not:

* A ZFS snapshot scheduling tool. There are many available programs for this
  already. Snapshot Explorer should be able to work with snapshots created by
  any of them, or manually via the ZFS utilities.

* A general-purpose ZFS administration GUI. It is intended purely for exploring
  snapshots of locally-mounted filesystems.

Planned features:

* BTRFS support.

* Browsing of additional snapshots stored on an external/remote pool.

## Building and Installation

You'll need the following dependencies, using Debian-style package names:

* `libglib2.0-dev`
* `libgtk-3-dev`
* `libhandy-1-dev` (for the application)
* `libnautilus-extension-dev` (for the Nautilus extension)
* `meson`
* `valac`

You will need ZFS filesystem(s) for this tool to be useful, but it has no
dependencies on ZFS during installation.

On Linux, you will also need the userspace ZFS utilities (from `zfsutils-linux`)
to actually see available snapshots in the UI.

Run `meson build` to configure the build environment, then run `ninja` in the
new `build` directory to build:

    meson build --prefix=/usr/local
    cd build
    ninja

You can pass `-Denable-nautilus-extension=false` to `meson` to disable building
the Nautilus extension.

To install the application and possibly the extension, use `ninja install`, then
execute `snapshot-explorer`:

    sudo ninja install
    snapshot-explorer
