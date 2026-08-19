/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: Copyright 2021 Aaron Jacobs
 */

namespace SnapshotExplorer {
	public class Application : Adw.Application {
		const ActionEntry[] ACTION_ENTRIES = {
			{ "quit", quit },
		};

		public Application () {
			Object (
				application_id: "org.github.atheriel.snapshot-explorer",
				flags: ApplicationFlags.DEFAULT_FLAGS
			);
		}

		public override void startup () {
			base.startup ();
			add_action_entries (ACTION_ENTRIES, this);
			set_accels_for_action ("app.quit", {"<Control>q", "<Control>w"});
		}

		public override void activate () {
			// Note: Gtk.Application.active_window is annotated non-null, but
			// *does* in fact return null before the first Window is built.
			Gtk.Window? window = active_window;
			if (window == null) {
				window = new Window (this);
			}
			window?.present ();
		}
	}
}

int main (string[] args) {
	Intl.setlocale (LocaleCategory.ALL, "");
	Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
	Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
	Intl.textdomain (Config.GETTEXT_PACKAGE);

	return new SnapshotExplorer.Application ().run (args);
}
