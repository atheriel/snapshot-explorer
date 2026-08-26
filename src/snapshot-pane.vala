/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: Copyright 2025 Aaron Jacobs
 */

[GtkTemplate (ui = "/org/github/atheriel/snapshot-explorer/snapshot-pane.ui")]
class SnapshotPane : Gtk.Box {
	public bool loading { get; private set; }

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
	private Cancellable? current = null;
	private string? path = null;
	private Fs.Type fs_type = Fs.Type.UNKNOWN;
	private bool bus_initialised = false;

	public signal void error_occurred (Error error);
	private signal void bus_start_finished ();

	construct {
		start_bus.begin ();
	}

	public async void set_path (string? path, Fs.Type fs_type) {
		this.path = path?.dup ();
		this.fs_type = fs_type;
		yield refresh ();
	}

	public async bool refresh () {
		if (path == null) {
			return false;
		}

		current?.cancel ();
		var cancellable = new Cancellable ();
		current = cancellable;
		loading = true;

		List<Fs.Snapshot> entries;
		try {
			switch (fs_type) {
			case Fs.Type.ZFS:
				entries = yield Zfs.snapshots_for_path ((!) path, cancellable);
				break;
			case Fs.Type.UNKNOWN:
				// Assume that an unknown filesystem might be ZFS. This will
				// throw Fs.Error.NOT_SUPPORTED if it is not, which is caught
				// below.
				entries = yield Zfs.snapshots_for_path ((!) path, cancellable);
				break;
			default:
				show_page ("not-supported", cancellable);
				return false;
			}
		} catch (IOError.CANCELLED e) {
			return false;
		} catch (Fs.Error.NOT_SUPPORTED e) {
			show_page ("not-supported", cancellable);
			return false;
		} catch (Error e) {
			error_occurred (e);
			show_page ("error", cancellable);
			return false;
		}

		if (entries.length () == 0) {
			show_page ("no-snapshots", cancellable);
			return true;
		}

		if (!bus_initialised) {
			ulong handler_id = 0;
			handler_id = bus_start_finished.connect (() => {
				SignalHandler.disconnect (this, handler_id);
				refresh.callback ();
			});
			yield;
		}

		if (!is_current (cancellable)) {
			return false;
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
						error_occurred (e);
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

		show_page ("snapshots", cancellable);
		return true;
	}

	private void show_page (string name, Cancellable cancellable) {
		if (!is_current (cancellable)) {
			return;
		}
		stack.visible_child_name = name;
		current = null;
		loading = false;
	}

	private bool is_current (Cancellable cancellable) {
		return current == cancellable && !cancellable.is_cancelled ();
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

		bus_initialised = true;
		bus_start_finished ();
	}
}
