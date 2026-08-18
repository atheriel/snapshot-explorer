/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021 Aaron Jacobs
 */

namespace SnapshotExplorer {
	[GtkTemplate (ui = "/org/github/atheriel/snapshot-explorer/window.ui")]
	public class Window : Adw.ApplicationWindow {
		[GtkChild] unowned Gtk.ListBox folders;
		[GtkChild] unowned SnapshotPane snapshots;
		[GtkChild] unowned Adw.OverlaySplitView view;
		[GtkChild] unowned Adw.ToastOverlay toast_overlay;
		[GtkChild] unowned Gtk.Stack stack;
		[GtkChild] new unowned Adw.HeaderBar titlebar;
#if ADW_HAS_SPINNER
		[GtkChild] unowned Adw.StatusPage startup;
#endif
		string? current_path;
		Fs.Type current_fs_type = Fs.Type.UNKNOWN;

		const ActionEntry[] ACTION_ENTRIES = {
			{ "refresh", on_refresh },
			{ "shortcuts", on_shortcuts },
			{ "about", on_about },
		};

		public Window (Gtk.Application app) {
			Object (application: app);
		}

		static construct {
			typeof (SnapshotPane).ensure ();
		}

		construct {
			add_action_entries (ACTION_ENTRIES, this);

			var app = (Gtk.Application) GLib.Application.get_default ();
			app.set_accels_for_action ("win.refresh", {"<Control>r", "F5"});
			app.set_accels_for_action ("win.shortcuts", {"<Control>question"});

			folders.row_activated.connect((row) => {
				var folder = FolderItem.from_row (row);
				if (view.collapsed) {
					view.show_sidebar = false;
				}
				current_path = folder.path.dup ();
				current_fs_type = folder.type;
				snapshots.set_path.begin (current_path, current_fs_type);
			});

			// Make sure the sidebar is visible if there is room for it.
			view.notify["collapsed"].connect (() => {
				if (!view.collapsed) {
					view.show_sidebar = true;
				}
			});

#if ADW_HAS_SPINNER
			startup.paintable = new Adw.SpinnerPaintable (startup);
#endif
			titlebar.pack_end (snapshots.loading_indicator);

			refresh_folders.begin ();
		}

		private async void refresh_folders () {
			var zroot = yield Zfs.mountpoint_tree ();
			if (zroot == null) {
				stack.visible_child_name = "no-datasets";
				return;
			}
			var store = new GLib.ListStore (typeof(FolderItem));
			FolderItem.maybe_add_section (store, zroot, _("ZFS Datasets"),
										  Fs.Type.ZFS);
			folders.bind_model (
				new Gtk.TreeListModel (store, false, false, FolderItem.child_models),
				FolderItem.create_row_widget
			);

			if (stack.visible_child_name != "main") {
				stack.visible_child_name = "main";
				return;
			}

			toast_overlay.add_toast (new Adw.Toast (_("Refreshed folders.")) {
				timeout = 2,
			});
		}

		private void on_refresh () {
			if (!view.collapsed || view.show_sidebar) {
				refresh_folders.begin ();
			} else {
				snapshots.set_path.begin (current_path, current_fs_type);
			}
		}

		private void on_shortcuts () {
			var win = (Gtk.Window) new Gtk.Builder.from_resource (
				"/org/github/atheriel/snapshot-explorer/shortcuts.ui")
				.get_object ("shortcuts");
			win.transient_for = this;
			win.present ();
		}

		private void on_about () {
			var dialog = new Adw.AboutDialog () {
				application_name = _("Snapshot Explorer"),
				application_icon = "org.github.atheriel.snapshot-explorer",
				version = "0.1.0",
				comments = _("Browse local ZFS snapshots using the system file manager."),
				developer_name = "Aaron Jacobs",
				copyright = "© 2021 Aaron Jacobs",
				license_type = Gtk.License.GPL_3_0,
				developers = { "Aaron Jacobs" },
			};
			dialog.present (this);
		}
	}

	public class FolderItem : GLib.Object {
		public string label;
		public string path;
		public Fs.Type type;
		public GLib.ListStore? children;
		protected bool heading;

		public static void maybe_add_section (GLib.ListStore store, Node<string>? root, string heading, Fs.Type t) {
			assert (store.item_type == typeof(FolderItem));
			if (root == null) {
				return;
			}
			store.append (new FolderItem.header (heading));
			((!) root).children_foreach(TraverseFlags.ALL, (n) => {
				store.append (new FolderItem.from_node (n, t));
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
			this.type = Fs.Type.UNKNOWN;
			this.heading = true;
		}

		protected FolderItem.from_node (Node<string> item, Fs.Type t, string parent = "") {
			this.label = item.data.replace(parent, "");
			this.path = item.data;
			this.type = t;
			this.heading = false;
			if (item.n_children() == 0) {
				return;
			}
			var model = new GLib.ListStore (typeof(FolderItem));
			item.children_foreach(TraverseFlags.ALL, (n) => {
				var p = this.path == "/" ? "/" : this.path + "/";
				model.append (new FolderItem.from_node (n, t, p));
			});
			this.children = model;
		}
	}
}
