/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021 Aaron Jacobs
 */

namespace SnapshotExplorer {
	public class Window : Gtk.ApplicationWindow {
		Gtk.Button back;
		Gtk.ListBox folders;
		Gtk.Box snapshots;
		Hdy.Leaflet content;
		string? current_path;
		FileManager1? fm = null;

		const ActionEntry[] ACTION_ENTRIES = {
			{ "refresh", on_refresh },
			{ "shortcuts", on_shortcuts },
		};

		public Window (Gtk.Application app) {
			Object (
				application: app,
				title: "Snapshot Explorer",
				default_height: 500,
				default_width: 760
			);
		}

		static construct {
			Hdy.init ();
		}

		construct {
			add_action_entries (ACTION_ENTRIES, this);

			var app = (Gtk.Application) GLib.Application.get_default ();
			app.set_accels_for_action ("win.refresh", {"<Control>r", "F5"});
			app.set_accels_for_action ("win.shortcuts", {"<Control>question"});

			var titlebar = new Gtk.HeaderBar () {
				title = _("Snapshot Explorer"),
				show_close_button = true
			};
			set_titlebar (titlebar);

			back = new Gtk.Button.from_icon_name ("go-previous-symbolic") {
				tooltip_text = _("Back to folders"),
			};
			back.clicked.connect(on_back);
			titlebar.pack_start(back);

			var refresh = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
				tooltip_text = _("Refresh folder list"),
				action_name = "win.refresh"
			};
			titlebar.pack_start(refresh);

			var menu = new Menu ();
			var item = new MenuItem (_("Keyboard Shortcuts"), "win.shortcuts");
			item.set_attribute ("accel", "s", "<Control>question");
			menu.append_item (item);
			item = new MenuItem (_("Quit"), "app.quit");
			item.set_attribute ("accel", "s", "<Control>q");
			menu.append_item (item);
			var menu_button = new Gtk.MenuButton() {
				tooltip_text = _("Menu"),
				use_popover = true,
				menu_model = menu,
			};
			menu_button.add (new Gtk.Image.from_icon_name ("open-menu-symbolic", Gtk.IconSize.BUTTON));
			titlebar.pack_end(menu_button);

			folders = new Gtk.ListBox () {
				selection_mode = Gtk.SelectionMode.NONE,
				vexpand = true,
			};
			folders.get_style_context ().add_class ("sidebar");
			folders.set_placeholder (new Hdy.StatusPage () {
				description = _("No mounted ZFS filesystems found."),
				icon_name = "drive-multidisk-symbolic",
				visible = true,
			});

			var snapshots_clamp = new Hdy.Clamp () {
				maximum_size = 500,
				tightening_threshold = 400,
				margin_top = 14,
				margin_start = 12,
				margin_end = 12
			};
			snapshots = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
			snapshots_clamp.add (snapshots);
			snapshots.pack_start (new Hdy.StatusPage () {
				title = _("Select a Folder"),
				description = _("Choose a folder from a mounted ZFS filesystem\nto view snapshots."),
				icon_name = "folder-symbolic",
				vexpand = true,
			});

			var sidebar_container = new Gtk.ScrolledWindow (null, null) {
				width_request = 200,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				hexpand = true,
			};
			sidebar_container.add (folders);

			var pane_container = new Gtk.ScrolledWindow (null, null) {
				hscrollbar_policy = Gtk.PolicyType.NEVER
			};
			pane_container.set_size_request (500, -1);
			pane_container.add (snapshots_clamp);

			content = new Hdy.Leaflet () {
				transition_type = Hdy.LeafletTransitionType.SLIDE
			};
			content.add_with_properties (sidebar_container, "name", "sidebar");
			content.add (new Gtk.Separator (Gtk.Orientation.VERTICAL));
			content.add_with_properties (pane_container, "name", "pane");
			content.set_visible_child (sidebar_container);
			add (content);

			content.notify["visible-child"].connect((s, p) => {
				update_titlebar ();
			});
			content.notify["folded"].connect((s, p) => {
				update_titlebar ();
			});

			refresh_folders.begin ();
			start_bus.begin ();
		}

		private async void refresh_folders () {
			var zroot = yield Zfs.mountpoint_tree ();
			folders.@foreach((child) => {
				folders.remove (child);
			});
			if (zroot != null) {
				var header = new Gtk.ListBoxRow () {
					selectable = false,
					activatable = false,
				};
				var header_label = new Gtk.Label (_("Folders")) {
					xalign = 0,
					margin_bottom = 6,
					margin_start = 6,
					margin_top = 14,
				};
				header_label.get_style_context ().add_class ("heading");
				header.add (header_label);
				folders.add (header);
				((!) zroot).children_foreach(TraverseFlags.ALL, (n) => {
					folders.add (build_row_for_node (n, _("ZFS Dataset")));
				});
			}
			folders.show_all ();
		}

		private async void start_bus () {
			try {
				fm = Bus.get_proxy_sync (
					BusType.SESSION,
					"org.freedesktop.FileManager1",
					"/org/freedesktop/FileManager1"
				);
			} catch (IOError e) {
				print ("failed to connect to dbus: %s", e.message);
			}
		}

		private void update_titlebar () {
			var viewing_sidebar = content.visible_child_name == "sidebar";
			var folded = content.folded;
			back.set_visible (folded && !viewing_sidebar);
		}

		private async void refresh_snapshots () {
			if (current_path == null) {
				return;
			}
			var entries = yield Zfs.snapshots_for_path ((!) current_path);
			snapshots.@foreach ((child) => {
				snapshots.remove (child);
			});
			if (entries.length () == 0) {
				snapshots.pack_start (new Gtk.Label (null) {
					label = _("No snapshots found."),
					hexpand = true
				}, false, false, 0);
				snapshots.show_all ();
				return;
			}
			var today = new List<Hdy.ActionRow> ();
			var yesterday = new List<Hdy.ActionRow> ();
			var this_week = new List<Hdy.ActionRow> ();
			var this_year = new List<Hdy.ActionRow> ();
			var older = new List<Hdy.ActionRow> ();
			entries.@foreach ((e) => {
				Zfs.Snapshot entry = (!) e;
				var row = new Hdy.ActionRow () {
					subtitle = _("ZFS Snapshot: %s").printf(entry.name)
				};
				if (fm != null) {
					var open = new Gtk.Button.from_icon_name ("folder") {
						label = _("Browse"),
						always_show_image = true,
						margin_top = 6,
						margin_bottom = 6
					};
					open.get_style_context ().add_class ("list-button");
					open.clicked.connect(() => {
						try {
							((!) fm).show_folders({ entry.path }, "");
						} catch (Error e) {
						// TODO: Better error handling/reporting.
							print ("failed to connect to dbus: %s", e.message);
						};
					});
					row.activatable_widget = open;
					row.add (open);
				}
				var ts = entry.timestamp ();
				row.title = ts.display;
				switch (ts.range) {
				case Zfs.Snapshot.AgeRange.TODAY:
					today.append (row);
					break;
				case Zfs.Snapshot.AgeRange.YESTERDAY:
					yesterday.append (row);
					break;
				case Zfs.Snapshot.AgeRange.THIS_WEEK:
					this_week.append (row);
					break;
				case Zfs.Snapshot.AgeRange.THIS_YEAR:
					this_year.append (row);
					break;
				default:
					older.append (row);
					break;
				}
			});

			maybe_add_snapshot_rows (today, _("Today"));
			maybe_add_snapshot_rows (yesterday, _("Yesterday"));
			maybe_add_snapshot_rows (this_week, _("Earlier This Week"));
			maybe_add_snapshot_rows (this_year, _("Earlier This Year"));
			maybe_add_snapshot_rows (older, _("Previous Years"));

			snapshots.show_all ();
		}

		private void on_back () {
			content.visible_child_name = "sidebar";
		}

		private void on_refresh () {
			if (content.visible_child_name == "sidebar") {
				refresh_folders.begin ();
			} else {
				refresh_snapshots.begin ();
			}
		}

		private void on_shortcuts () {
			var win = new ShortcutsWindow ();
			win.set_transient_for (this);
			win.show_all ();
			win.present ();
		}

		private void open_snapshots_for_path (string path) {
			content.visible_child_name = "pane";
			current_path = path.dup ();
			refresh_snapshots.begin ();
		}

		// Recursively build (expander) rows for a mount tree.
		Gtk.ListBoxRow build_row_for_node (GLib.Node<string> node, string flavour) {
			var path = node.data.dup ();
			// TODO: Or, use something more time-related?
			var open = new Gtk.Button.from_icon_name ("camera-photo-symbolic") {
				margin_top = 6,
				margin_bottom = 6
			};
			open.get_style_context ().add_class ("list-button");
			open.clicked.connect(() => {
				open_snapshots_for_path (path);
			});
			if (node.n_children () == 0) {
				var row = new Hdy.ActionRow () {
					title = node.data,
					subtitle = flavour,
					icon_name = icon_name_for_path (node.data),
					activatable_widget = open
				};
				row.add (open);
				return (owned) row;
			}
			var row = new Hdy.ExpanderRow () {
				title = node.data,
				subtitle = flavour,
				expanded = false,
				icon_name = icon_name_for_path (node.data)
			};
			row.add_action (open);
			node.children_foreach(TraverseFlags.ALL, (child_node) => {
				var child_row = build_row_for_node (child_node, flavour);
				row.add (child_row);
			});
			return (owned) row;
		}

		void maybe_add_snapshot_rows (List<Hdy.ActionRow>? rows, string title) {
			if (rows != null) {
				var header = new Gtk.Label (title) {
					xalign = 0,
				};
				header.get_style_context ().add_class ("heading");
				snapshots.pack_start (header, false, false, 0);
				var list = new Gtk.ListBox () {
					selection_mode = Gtk.SelectionMode.NONE,
					margin_bottom = 24
				};
				list.get_style_context ().add_class ("content");
				snapshots.pack_start (list, false, false, 0);
				((!) rows).@foreach ((row) => {
					list.add (row);
				});
			}
		}

		private string icon_name_for_path (string path) {
			if (!path.has_prefix ("/home")) {
				return "folder";
			}
			var theme = Gtk.IconTheme.get_default ();
			if (path.has_suffix("Documents") && theme.has_icon ("folder-documents")) {
				return "folder-documents";
			} else if (path.has_suffix("Downloads") && theme.has_icon ("folder-downloads")) {
				return "folder-downloads";
			} else if (path.has_suffix("Music") && theme.has_icon ("folder-music")) {
				return "folder-music";
			} else if (path.has_suffix("Pictures") && theme.has_icon ("folder-pictures")) {
				return "folder-pictures";
			} else if (path.has_suffix("Videos") && theme.has_icon ("folder-videos")) {
				return "folder-videos";
			} else if (path.split("/").length == 3 && theme.has_icon ("folder-home")) {
				// E.g. "/home/user".
				return "folder-home";
			}
			return "folder";
		}
	}
}
