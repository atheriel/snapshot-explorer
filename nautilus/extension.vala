class SnapshotLocationWidgetProvider : Nautilus.LocationWidgetProvider, Object {
	private Gtk.InfoBar bar;
	private Gtk.Label label;

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
	}

	public virtual Gtk.Widget? get_widget (string uri, Gtk.Widget window) {
		if (!uri.contains ("file://") || !is_snapshot_path (uri)) {
			return null;
		}
		var current = current_uri_from_snapshot (uri);
		label.label = "Browsing a read-only snapshot of %s".printf (
			current.replace ("file://", "")
		);
		bar.show_all ();
		return bar;
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

[ModuleInit]
public void nautilus_module_initialize(TypeModule module) {
	typeof(SnapshotLocationWidgetProvider);
}

public void nautilus_module_shutdown() {
}

// See shim.c.
public void _nautilus_module_list_types([CCode (array_length_type = "int")] out Type[] types) {
	types = {typeof(SnapshotLocationWidgetProvider)};
}
