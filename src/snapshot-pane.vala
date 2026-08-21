/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: Copyright 2025 Aaron Jacobs
 */

[GtkTemplate (ui = "/org/github/atheriel/snapshot-explorer/snapshot-pane.ui")]
class SnapshotPane : Gtk.Box {
#if ADW_HAS_SPINNER
	public Adw.Spinner loading_indicator { get; construct set; }
#else
	public Gtk.Spinner loading_indicator { get; construct set; }
#endif

	[GtkChild] private unowned Gtk.Stack stack;
	[GtkChild] private unowned Adw.PreferencesGroup today_section;
	[GtkChild] private unowned Adw.PreferencesGroup yesterday_section;
	[GtkChild] private unowned Adw.PreferencesGroup earlier_this_week_section;
	[GtkChild] private unowned Adw.PreferencesGroup earlier_this_year_section;
	[GtkChild] private unowned Adw.PreferencesGroup previous_years_section;
	[GtkChild] private unowned Gtk.ListBox today;
	[GtkChild] private unowned Gtk.ListBox yesterday;
	[GtkChild] private unowned Gtk.ListBox earlier_this_week;
	[GtkChild] private unowned Gtk.ListBox earlier_this_year;
	[GtkChild] private unowned Gtk.ListBox previous_years;
	private FileManager1? fm = null;

	construct {
#if ADW_HAS_SPINNER
		loading_indicator = new Adw.Spinner () {
			tooltip_text = _("Loading snapshots..."),
			visible = false,
		};
#else
		loading_indicator = new Gtk.Spinner () {
			tooltip_text = _("Loading snapshots..."),
			spinning = false,
			visible = false,
		};
#endif

		start_bus.begin ();
	}

	public async void set_path (string? path, Fs.Type fs_type) {
		if (path == null) {
			return;
		}

		loading_indicator.visible = true;
#if !ADW_HAS_SPINNER
		loading_indicator.spinning = true;
#endif

		List<Fs.Snapshot> entries;
		switch (fs_type) {
		case Fs.Type.ZFS:
			entries = yield Zfs.snapshots_for_path ((!) path);
			break;
		default:
			show_page ("not-supported");
			return;
		}

		if (entries.length () == 0) {
			show_page ("no-snapshots");
			return;
		}

		clear_snapshots ();

		entries.@foreach ((e) => {
			Fs.Snapshot entry = (!) e;
			var row = new SnapshotRow (entry);
			if (fm != null) {
				row.browse.clicked.connect(() => {
					try {
						((!) fm).show_folders({ entry.uri }, "");
					} catch (Error e) {
					// TODO: Better error handling/reporting.
						print ("failed to connect to dbus: %s", e.message);
					};
				});
			}
			switch (entry.timestamp ().range) {
			case Fs.Snapshot.AgeRange.TODAY:
				today.append (row);
				today_section.visible = true;
				break;
			case Fs.Snapshot.AgeRange.YESTERDAY:
				yesterday.append (row);
				yesterday_section.visible = true;
				break;
			case Fs.Snapshot.AgeRange.THIS_WEEK:
				earlier_this_week.append (row);
				earlier_this_week_section.visible = true;
				break;
			case Fs.Snapshot.AgeRange.THIS_YEAR:
				earlier_this_year.append (row);
				earlier_this_year_section.visible = true;
				break;
			default:
				previous_years.append (row);
				previous_years_section.visible = true;
				break;
			}
		});

		show_page ("snapshots");
	}

	private void show_page (string name) {
		stack.visible_child_name = name;

		// We're done loading at this point.
		loading_indicator.visible = false;
#if !ADW_HAS_SPINNER
		loading_indicator.spinning = false;
#endif
	}

	private void clear_snapshots () {
		today.remove_all ();
		yesterday.remove_all ();
		earlier_this_week.remove_all ();
		earlier_this_year.remove_all ();
		previous_years.remove_all ();

		today_section.visible = false;
		yesterday_section.visible = false;
		earlier_this_week_section.visible = false;
		earlier_this_year_section.visible = false;
		previous_years_section.visible = false;
	}

	private async void start_bus () {
		try {
			fm = yield Bus.get_proxy (
				BusType.SESSION,
				"org.freedesktop.FileManager1",
				"/org/freedesktop/FileManager1"
			);
		} catch (IOError e) {
			print ("failed to connect to dbus: %s", e.message);
		}
	}
}
