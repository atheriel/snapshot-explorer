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
		Adw.Leaflet content;
		string? current_path;
		FileManager1? fm = null;

		const ActionEntry[] ACTION_ENTRIES = {
			{ "refresh", on_refresh },
			{ "shortcuts", on_shortcuts },
		};

		public Window (Gtk.Application app) {
			Object (
				application: app,
				title: _("Snapshot Explorer"),
				default_height: 500,
				default_width: 760
			);
		}

		static construct {
			Adw.init ();
		}

		construct {
			add_action_entries (ACTION_ENTRIES, this);

			var app = (Gtk.Application) GLib.Application.get_default ();
			app.set_accels_for_action ("win.refresh", {"<Control>r", "F5"});
			app.set_accels_for_action ("win.shortcuts", {"<Control>question"});

			var titlebar = new Gtk.HeaderBar () {
				show_title_buttons = true
			};
			set_titlebar (titlebar);

			back = new Gtk.Button.from_icon_name ("go-previous-symbolic") {
				tooltip_text = _("Back to folders"),
				// This should be invisible on startup, when no folder can be
				// selected.
				visible = false,
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
			titlebar.pack_end(new Gtk.MenuButton() {
				tooltip_text = _("Menu"),
				icon_name = "open-menu-symbolic",
				menu_model = menu,
			});

			folders = new Gtk.ListBox () {
				selection_mode = Gtk.SelectionMode.NONE,
				vexpand = true,
				css_classes = {"navigation-sidebar"},
			};
			folders.set_placeholder (new Adw.StatusPage () {
				description = _("No mounted ZFS filesystems found."),
				icon_name = "drive-multidisk-symbolic",
				visible = true,
			});
			folders.row_activated.connect((row) => {
				var folder = FolderItem.from_row (row);
				open_snapshots_for_path (folder.path);
			});

			snapshots = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
			snapshots.append (new Adw.StatusPage () {
				title = _("Select a Folder"),
				description = _("Choose a folder from a mounted ZFS filesystem\nto view snapshots."),
				icon_name = "folder-symbolic",
				vexpand = true,
			});

			var sidebar_container = new Gtk.ScrolledWindow () {
				width_request = 200,
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				hexpand = true,
				child = folders,
			};

			var pane_container = new Gtk.ScrolledWindow () {
				hscrollbar_policy = Gtk.PolicyType.NEVER,
				width_request = 500,
				hexpand = true,
				child = new Adw.Clamp () {
					maximum_size = 500,
					tightening_threshold = 400,
					margin_top = 14,
					margin_start = 12,
					margin_end = 12,
					child = snapshots,
				},
			};

			content = new Adw.Leaflet () {
				transition_type = Adw.LeafletTransitionType.SLIDE
			};
			var page = content.append (sidebar_container);
			page.name = "sidebar";
			page = content.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));
			page.name = "separator";
			page.navigatable = false;
			page = content.append (pane_container);
			page.name = "pane";
			content.set_visible_child_name ("sidebar");
			child = content;

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
			var store = new GLib.ListStore (typeof(FolderItem));
			FolderItem.maybe_add_section (store, zroot, _("ZFS Datasets"));
			folders.bind_model (
				new Gtk.TreeListModel (store, false, false, FolderItem.child_models),
				FolderItem.create_row_widget
			);
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
			Gtk.Widget? child = snapshots.get_first_child ();
			while (child != null) {
				snapshots.remove ((!) child);
				child = snapshots.get_first_child ();
			}
			if (entries.length () == 0) {
				snapshots.append (new Gtk.Label (null) {
					label = _("No snapshots found."),
					hexpand = true
				});
				return;
			}
			var today = new List<Adw.ActionRow> ();
			var yesterday = new List<Adw.ActionRow> ();
			var this_week = new List<Adw.ActionRow> ();
			var this_year = new List<Adw.ActionRow> ();
			var older = new List<Adw.ActionRow> ();
			entries.@foreach ((e) => {
				Zfs.Snapshot entry = (!) e;
				var row = new Adw.ActionRow () {
					subtitle = _("ZFS Snapshot: %s").printf(entry.name)
				};
				if (fm != null) {
					var open = new Gtk.Button.from_icon_name ("folder") {
						label = _("Browse"),
						always_show_image = true,
						margin_top = 6,
						margin_bottom = 6
					};
					open.clicked.connect(() => {
						try {
							((!) fm).show_folders({ entry.path }, "");
						} catch (Error e) {
						// TODO: Better error handling/reporting.
							print ("failed to connect to dbus: %s", e.message);
						};
					});
					row.activatable_widget = open;
					row.add_suffix (open);
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

		void maybe_add_snapshot_rows (List<Adw.ActionRow>? rows, string title) {
			if (rows != null) {
				snapshots.append (new Gtk.Label (title) {
					xalign = 0,
					css_classes = {"heading"},
				});
				var list = new Gtk.ListBox () {
					selection_mode = Gtk.SelectionMode.NONE,
					margin_bottom = 24,
					css_classes = {"boxed-list"},
				};
				snapshots.append (list);
				((!) rows).@foreach ((row) => {
					list.append (row);
				});
			}
		}
	}

	public class FolderItem : GLib.Object {
		public string label;
		public string path;
		public GLib.ListStore? children;
		protected bool heading;

		public static void maybe_add_section (GLib.ListStore store, Node<string>? root, string heading) {
			assert (store.item_type == typeof(FolderItem));
			if (root == null) {
				return;
			}
			store.append (new FolderItem.header (heading));
			((!) root).children_foreach(TraverseFlags.ALL, (n) => {
				store.append (new FolderItem.from_node (n));
			});
		}

		public static GLib.ListStore? child_models (Object item) {
			assert (item is FolderItem);
			return ((FolderItem) item).children;
		}

		public static Gtk.Widget create_row_widget (GLib.Object item) {
			assert (item is Gtk.TreeListRow);
			assert (((Gtk.TreeListRow) item).item is unowned FolderItem);
			var list_row = (Gtk.TreeListRow) item;
			var folder = (FolderItem) list_row.item;
			if (folder.heading) {
				return new Gtk.ListBoxRow () {
					selectable = false,
					activatable = false,
					child = new Gtk.Label (folder.label) {
						xalign = 0,
						css_classes = {"heading"},
					},
				};
			}
			var entry = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
			entry.append (new Gtk.Image.from_icon_name ("folder-symbolic"));
			entry.append (new Gtk.Label (folder.label) {
				xalign = 0,
				css_classes = {"title"},
			});
			return new Gtk.ListBoxRow () {
				child = new Gtk.TreeExpander() {
					list_row = list_row,
					child = entry,
				},
			};
		}

		public static unowned FolderItem from_row (Gtk.ListBoxRow row) {
			assert (row.child is Gtk.TreeExpander);
			var item = ((Gtk.TreeExpander) (row.child)).item;
			assert (item is unowned FolderItem);
			return (FolderItem) item;
		}

		protected FolderItem.header (string heading) {
			this.label = heading;
			this.heading = true;
		}

		protected FolderItem.from_node (Node<string> item, string parent = "") {
			this.label = item.data.replace(parent, "");
			this.path = item.data;
			this.heading = false;
			if (item.n_children() == 0) {
				return;
			}
			var model = new GLib.ListStore (typeof(FolderItem));
			item.children_foreach(TraverseFlags.ALL, (n) => {
				var p = this.path == "/" ? "/" : this.path + "/";
				model.append (new FolderItem.from_node (n, p));
			});
			this.children = model;
		}
	}
}
