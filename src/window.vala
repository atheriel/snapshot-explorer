/* -*- mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
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
			var titlebar = new Gtk.HeaderBar () {
				title = "Snapshot Explorer",
				show_close_button = true
			};
			set_titlebar (titlebar);

			back = new Gtk.Button.from_icon_name ("go-previous-symbolic");
			back.clicked.connect(on_back);
			titlebar.pack_start(back);

			var refresh = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
				tooltip_text = "Refresh the folder list."
			};
			refresh.clicked.connect(on_refresh);
			titlebar.pack_start(refresh);

			// var menu = new Menu();
			// menu.append("Keyboard Shortcuts", "app.shortcuts");
			// menu.append("About System Information", "app.about");
			// var menu_button = new Gtk.MenuButton() {
			//	   use_popover = true,
			//	   menu_model = menu,
			// };
			// menu_button.add (new Gtk.Image.from_icon_name ("open-menu-symbolic", Gtk.IconSize.BUTTON));
			// titlebar.pack_end(menu_button);

			var sidebar_container = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
			sidebar_container.set_size_request (200, -1);
			sidebar_container.pack_start (new Gtk.Label ("Folders") {
				justify = Gtk.Justification.LEFT,
				xalign = 0,
				margin_bottom = 6,
				margin_left = 6,
				margin_top = 6
			}, false, false, 0);
			folders = new Gtk.ListBox () {
				selection_mode = Gtk.SelectionMode.NONE
			};
			folders.set_placeholder (new Hdy.ActionRow () {
				title = "No snapshot-capable folders found."
			});
			folders.row_selected.connect((row) => {
				print("row selected\n");
			});
			var folders_container = new Gtk.ScrolledWindow (null, null) {
				hscrollbar_policy = Gtk.PolicyType.NEVER
			};
			folders_container.add (folders);
			sidebar_container.pack_start (folders_container, true, true, 0);
			var help_container = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
			help_container.get_style_context ().add_class ("background");
			sidebar_container.pack_start (help_container, false, false, 0);

			var help = new Gtk.Button.from_icon_name ("help-faq-symbolic", Gtk.IconSize.MENU) {
				margin_left = 3,
				// margin_top = 6,
				margin_bottom = 6,
				relief = Gtk.ReliefStyle.NONE
			};
			help_container.pack_start (help, false, true, 0);
			var help_popover = new Gtk.Popover (help) {
				constrain_to = Gtk.PopoverConstraint.WINDOW,
				modal = true,
				visible = false
			};
			help_popover.add (new Gtk.Label ("hello"));
			help.clicked.connect(() => {
				help_popover.popup ();
				help_popover.show_all ();
			});

			help_container.pack_start (new Gtk.Label (null) {
				label = "Missing something?",
				justify = Gtk.Justification.LEFT,
				xalign = 0,
				margin_bottom = 6,
				margin_top = 6
			}, false, false, 0);

			var snapshots_clamp = new Hdy.Clamp () {
				maximum_size = 500,
				tightening_threshold = 400,
				margin_top = 32,
				margin_bottom = 32,
				margin_start = 12,
				margin_end = 12
			};
			snapshots = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
			snapshots_clamp.add (snapshots);
			snapshots.pack_start (new Gtk.Label (null) {
				label = "Choose a folder to view snapshots, if any.",
				hexpand = true
			}, false, false, 0);

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
				((!) zroot).children_foreach(TraverseFlags.ALL, (n) => {
					folders.add (build_row_for_node (n, "ZFS Dataset"));
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
					label = "No snapshots found.",
					hexpand = true
				}, false, false, 0);
				snapshots.show_all ();
				return;
			}
			var now = new DateTime.now_local ();
			var hours_today = now.get_hour ();
			var today = new List<Hdy.ActionRow> ();
			var yesterday = new List<Hdy.ActionRow> ();
			var this_week = new List<Hdy.ActionRow> ();
			var this_year = new List<Hdy.ActionRow> ();
			var older = new List<Hdy.ActionRow> ();
			entries.@foreach ((e) => {
				Zfs.Snapshot entry = (!) e;
				var row = new Hdy.ActionRow () {
					subtitle = "ZFS Snapshot: %s".printf(entry.name)
				};
				if (fm != null) {
					var open = new Gtk.Button.from_icon_name ("folder") {
						label = "Browse",
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
				string timestamp = entry.created.format ("%X");
				string day;
				var since = now.difference (entry.created);
				if (since < TimeSpan.HOUR * hours_today) {
					day = "Today";
					today.append (row);
				} else if (since < TimeSpan.HOUR * (hours_today + 24)) {
					day = "Yesterday";
					yesterday.append (row);
				} else if (since < TimeSpan.HOUR * (hours_today + 6 * 24)) {
					day = entry.created.format ("%A");
					this_week.append (row);
				} else if (since < TimeSpan.DAY * now.get_day_of_year ()) {
					day = entry.created.format ("%b %-e");
					this_year.append (row);
				} else {
					day = entry.created.format ("%Y-%m-%d");
					older.append (row);
				}
				row.title = "%s at %s".printf(day, timestamp);
			});

			maybe_add_snapshot_rows (today, "Today");
			maybe_add_snapshot_rows (yesterday, "Yesterday");
			maybe_add_snapshot_rows (this_week, "Earlier This Week");
			maybe_add_snapshot_rows (this_year, "Earlier This Year");
			maybe_add_snapshot_rows (older, "Previous Years");

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
				snapshots.pack_start (new Gtk.Label (title) {
				justify = Gtk.Justification.LEFT,
					xalign = 0,
					margin_left = 6
				}, false, false, 0);
				var list = new Gtk.ListBox () {
					selection_mode = Gtk.SelectionMode.NONE,
					margin_bottom = 24
				};
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
			if (path.has_suffix("Documents")) {
				return "folder-documents";
			} else if (path.has_suffix("Downloads")) {
				return "folder-downloads";
			} else if (path.has_suffix("Music")) {
				return "folder-music";
			} else if (path.has_suffix("Pictures")) {
				return "folder-pictures";
			} else if (path.has_suffix("Videos")) {
				return "folder-videos";
			} else if (path.split("/").length == 3) {
				// E.g. "/home/user".
				return "folder-home";
			}
			return "folder";
		}
	}
}