/* -*- mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * SPDX-FileCopyrightText: 2021 Aaron Jacobs
 */

class SnapshotLocationWidgetProvider : Nautilus.LocationWidgetProvider, Object {
	private Gtk.InfoBar bar;
	private Gtk.Label label;
	private Cancellable cancellable;
	private Zfs.Snapshot? snapshot;

	construct {
		label = new Gtk.Label ("") {
			justify = Gtk.Justification.LEFT,
			xalign = 0,
			margin_bottom = 6,
			margin_top = 6
		};
		bar = new Gtk.InfoBar ();
		var container = bar.get_content_area ();
		container.add (label);
		cancellable = new Cancellable ();
	}

	public virtual Gtk.Widget? get_widget (string uri, Gtk.Widget window) {
		if (!uri.contains ("file://") || !is_snapshot_path (uri)) {
			return null;
		}
		var current = current_uri_from_snapshot (uri).replace ("file://", "");
		cancellable.cancel ();
		cancellable.reset ();
		fetch_snapshot_metadata.begin (current, snapshot_name_from_uri (uri));
		return bar;
	}

	private async void fetch_snapshot_metadata (string path, string? name) {
		bool cancelled = false;
		cancellable.cancelled.connect (() => {
			cancelled = true;
		});
		var snapshots = yield Zfs.snapshots_for_path (path);
		if (cancelled) {
			return;
		}
		snapshot = null;
		foreach (var s in snapshots) {
			if (s.name.ascii_casecmp ((!) name) == 0) {
				snapshot = s;
				break;
			}
		}
		if (snapshot == null) {
			return;
		}
		label.label = _("Browsing snapshot of %s on %s.").printf (
			path, ((!) snapshot).timestamp ().display
		);
		bar.show_all ();
	}
}

class SnapshotMenuProvider : Nautilus.MenuProvider, Object {
	public virtual List<Nautilus.MenuItem>? get_file_items(Gtk.Widget window, List<Nautilus.FileInfo> files) {
		// TODO: Multiple selection?
		if (files.length () != 1) {
			return null;
		}
		var file = files.nth_data (0);
		var uri = file.get_uri ();
		if (!uri.contains ("file://") || !is_snapshot_path (uri)) {
			return null;
		}
		var item = new Nautilus.MenuItem(
			"restore-to", _("Restore to..."),
			_("Restore this item from the snapshot.")
		);
		item.activate.connect(() => {
			var dialog = new Gtk.FileChooserNative(
				_("Select Restore Destination"), (Gtk.Window) window,
				Gtk.FileChooserAction.SAVE, _("Restore"), _("Close")
			);
			var parent = current_uri_from_snapshot (file.get_parent_uri ());
			dialog.set_current_folder_uri (parent);
			dialog.set_uri (current_uri_from_snapshot (uri));
			dialog.do_overwrite_confirmation = true;

			var res = dialog.run ();
			dialog.destroy ();
			if (res != Gtk.ResponseType.ACCEPT) {
				return;
			}

			var dest_uri = dialog.get_uri ();
			if (dest_uri == null) {
				// It's unclear how this could ever happen.
				return;
			}
			var dest = File.new_for_uri ((!) dest_uri);
			try {
				var copied = file.get_location ().copy (
					dest,
					FileCopyFlags.OVERWRITE | FileCopyFlags.ALL_METADATA |
					FileCopyFlags.NOFOLLOW_SYMLINKS,
					null, null
				);
				if (!copied) {
					// TODO: Can this ever happen?
					warning ("Failed to copy file; src=%s dest=%s", uri, (!) dest_uri);
				}
			} catch (Error e) {
				// TODO: Surface this error to the user instead.
				print ("error in copy(): %s\n", e.message);
			}
		});
		var items = new List<Nautilus.MenuItem>();
		items.append(item);
		return items;
	}

	public virtual List<Nautilus.MenuItem>? get_background_items(Gtk.Widget window, Nautilus.FileInfo current_folder) {
		return null;
	}
}

bool is_snapshot_path (string path) {
	// TODO: This will work for ZFS but BTRFS support would require more work.
	return path.contains (".zfs/snapshot/");
}

string current_uri_from_snapshot (string uri) {
	// TODO: This will work for ZFS but BTRFS support would require more work.
	string current;
	var parts = uri.split ("/.zfs/snapshot/");
	if (parts.length != 2) {
		return uri;
	}
	var suffix = parts[1].split ("/", 3);
	if (suffix.length == 1) {
		current = parts[0];
	} else {
		current = string.join ("/", parts[0], suffix[1]);
	}
	return current;
}

string? snapshot_name_from_uri (string uri) {
	// TODO: This will work for ZFS but BTRFS support would require more work.
	var parts = uri.split ("/.zfs/snapshot/");
	if (parts.length != 2) {
		return null;
	}
	var suffix = parts[1].split ("/", 2);
	if (suffix.length == 0) {
		return null;
	}
	return suffix[0];
}

[ModuleInit]
public void nautilus_module_initialize(TypeModule module) {
	typeof(SnapshotLocationWidgetProvider);
	typeof(SnapshotMenuProvider);
}

public void nautilus_module_shutdown() {
}

// See shim.c.
public void _nautilus_module_list_types([CCode (array_length_type = "int")] out Type[] types) {
	types = {
		typeof(SnapshotLocationWidgetProvider),
		typeof(SnapshotMenuProvider),
	};
}
