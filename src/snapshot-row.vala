/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: Copyright 2025 Aaron Jacobs
 */

[GtkTemplate (ui = "/org/github/atheriel/snapshot-explorer/snapshot-row.ui")]
class SnapshotRow : Adw.ActionRow {
	public Fs.Snapshot entry { get; construct; }
	public FileInfo info { get; construct; }

	[GtkChild] public unowned Gtk.Button browse;

	public SnapshotRow (Fs.Snapshot entry, FileInfo info) {
		Object (entry: entry, info: info);
	}

	construct {
		title = entry.timestamp ().display;
		subtitle = entry.name;
		activatable_widget = browse;
	}
}
