/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*- */

[GtkTemplate (ui = "/org/github/atheriel/snapshot-explorer/snapshot-row.ui")]
class SnapshotRow : Adw.ActionRow {
	public unowned Fs.Snapshot entry { get; construct; }

	[GtkChild] public unowned Gtk.Button browse;

	public SnapshotRow (Fs.Snapshot entry) {
		Object (entry: entry);
	}

	construct {
		title = entry.timestamp ().display;
		subtitle = entry.name;
		activatable_widget = browse;
	}
}
