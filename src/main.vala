/* -*- mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021 Aaron Jacobs
 */

using SnapshotExplorer;

int main (string[] args) {
	var app = new Gtk.Application (
		"org.github.atheriel.snapshot-explorer", ApplicationFlags.FLAGS_NONE
	);
	app.activate.connect (() => {
		var win = app.active_window;
		win = new Window (app);
		win.show_all ();
		win.present ();
	});

	return app.run (args);
}
