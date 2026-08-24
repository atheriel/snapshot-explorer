/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: Copyright 2021 Aaron Jacobs
 */

namespace SnapshotExplorer {
	[GtkTemplate (ui = "/org/github/atheriel/snapshot-explorer/window.ui")]
	public class Window : Adw.ApplicationWindow {
		[GtkChild] unowned Gtk.ListBox folders;
		[GtkChild] unowned SnapshotPane snapshots;
		[GtkChild] unowned Adw.OverlaySplitView view;
		[GtkChild] unowned Adw.ToastOverlay toast_overlay;
		[GtkChild] unowned Gtk.Stack stack;
		[GtkChild] unowned Gtk.Box loading_container;
#if ADW_HAS_SPINNER
		[GtkChild] unowned Adw.StatusPage startup;
#endif
		GLib.ListStore folder_store;
		Node<string>? dataset_nodes;
		Node<string>? other_nodes;

		const ActionEntry[] ACTION_ENTRIES = {
			{ "open-folder", on_open_folder },
			{ "refresh", on_refresh },
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
			app.set_accels_for_action ("win.open-folder", {"<Control>o"});
			app.set_accels_for_action ("win.refresh", {"<Control>r", "F5"});

			folder_store = new GLib.ListStore (typeof(FolderItem));
			folders.bind_model (
				new Gtk.TreeListModel (
					folder_store, false, false, FolderItem.child_models
				),
				FolderItem.create_row_widget
			);

			folders.row_activated.connect ((row) => {
				var folder = FolderItem.from_row (row);
				// Clicking on a ZFS row drops the Other section, if it exists.
				if (folder.type != Fs.Type.UNKNOWN) {
					remove_other_folder ();
				}
				show_snapshots (folder.path, folder.type);
			});

			// Make sure the sidebar is visible if there is room for it.
			view.notify["collapsed"].connect (() => {
				if (!view.collapsed) {
					view.show_sidebar = true;
				}
			});

#if ADW_HAS_SPINNER
			startup.paintable = new Adw.SpinnerPaintable (startup);

			var spinner = new Adw.Spinner () {
				tooltip_text = _("Loading..."),
				visible = false,
			};
#else
			var spinner = new Gtk.Spinner () {
				tooltip_text = _("Loading..."),
				spinning = false,
				visible = false,
			};
			snapshots.bind_property (
				"loading", spinner, "spinning", BindingFlags.SYNC_CREATE
			);
#endif
			snapshots.bind_property (
				"loading", spinner, "visible", BindingFlags.SYNC_CREATE
			);
			loading_container.append (spinner);

			snapshots.error_occurred.connect ((e) => {
				warning ("%s", e.message);
				toast_overlay.add_toast (new Adw.Toast (e.message));
			});

			refresh_folders.begin ();
		}

		private async void refresh_folders () {
			dataset_nodes = null;
			bool refreshed = false;
			try {
				dataset_nodes = yield Zfs.mountpoint_tree ();
				refreshed = true;
			} catch (Error e) {
				warning ("%s", e.message);
				toast_overlay.add_toast (new Adw.Toast (e.message));
			}
			folder_store.remove_all ();
			FolderItem.maybe_add_section (
				folder_store, dataset_nodes, _("ZFS Datasets"), Fs.Type.ZFS
			);
			maybe_add_other_folder ();

			if (folder_store.n_items == 0) {
				stack.visible_child_name = "no-datasets";
				return;
			}

			if (stack.visible_child_name != "main") {
				stack.visible_child_name = "main";
				return;
			}

			if (!refreshed) {
				return;
			}

			toast_overlay.add_toast (new Adw.Toast (_("Refreshed folders.")) {
				timeout = 2,
			});
		}

		private void show_snapshots (string path, Fs.Type type) {
			if (view.collapsed) {
				view.show_sidebar = false;
			}
			snapshots.set_path.begin (path, type);
		}

		private void maybe_add_other_folder () {
			FolderItem.maybe_add_section (
				folder_store, other_nodes, _("Other"), Fs.Type.UNKNOWN
			);
		}

		private void remove_other_folder () {
			if (other_nodes == null) {
				return;
			}
			folder_store.remove (folder_store.n_items - 1);
			folder_store.remove (folder_store.n_items - 1);
			other_nodes = null;
		}

		private void on_open_folder () {
			choose_folder.begin ();
		}

		private async void choose_folder () {
			var dialog = new Gtk.FileDialog () {
				title = _("Open Folder"),
				modal = true,
			};
			try {
				var folder = yield dialog.select_folder (this, null);
				var path = folder?.get_path ();
				if (path != null) {
					navigate_to ((!) path);
				}
			} catch (Gtk.DialogError.DISMISSED e) {
				return;
			} catch (Error e) {
				toast_overlay.add_toast (
					new Adw.Toast (_("Could not open the selected folder."))
				);
				warning ("Failed to open folder: %s", e.message);
			}
		}

		private void navigate_to (string path) {
			remove_other_folder ();
			bool is_dataset = is_dataset (path);
			if (!is_dataset) {
				other_nodes = new Node<string> ("<root>");
				other_nodes?.append (new Node<string> (path));
				maybe_add_other_folder ();
			}

			show_snapshots (path, is_dataset ? Fs.Type.ZFS : Fs.Type.UNKNOWN);
			stack.visible_child_name = "main";

			// Ensure that the entry is selected and any ancestors are expanded.
			bool expanded = false;
			do {
				expanded = false;
				for (int i = 0; ; i++) {
					var row = folders.get_row_at_index (i);
					if (row == null) {
						return;
					}
					if (!(((!) row).child is Gtk.TreeExpander)) {
						continue;
					}
					var expander = (Gtk.TreeExpander) ((!) row).child;
					var folder = FolderItem.from_row ((!) row);
					if (folder.path == path) {
						folders.select_row ((!) row);
						return;
					}
					if (folder.type != Fs.Type.ZFS ||
						!is_path_below (folder.path, path) ||
						expander.list_row.expanded) {
						continue;
					}
					expander.list_row.expanded = true;
					expanded = true;
					break;
				}
			} while (expanded);
		}

		private bool is_dataset (string path) {
			var found = false;
			dataset_nodes?.traverse (
				TraverseType.PRE_ORDER, TraverseFlags.ALL, -1, (node) => {
					found = node.data == path;
					return found;
				}
			);
			return found;
		}

		private static bool is_path_below (string parent, string path) {
			return parent == "/" ? path.has_prefix ("/") :
				path == parent || path.has_prefix (parent + "/");
		}

		private void on_refresh () {
			if (!view.collapsed || view.show_sidebar) {
				refresh_folders.begin ();
			} else {
				snapshots.refresh.begin ();
			}
		}

		private void on_about () {
			var dialog = new Adw.AboutDialog () {
				application_name = _("Snapshot Explorer"),
				application_icon = Config.APP_ID,
				version = Config.VERSION,
				comments = _("Browse local ZFS snapshots using the system file manager"),
				developer_name = "Aaron Jacobs",
				copyright = "© 2021–2026 Aaron Jacobs",
				license_type = Gtk.License.GPL_3_0,
				developers = { "Aaron Jacobs" },
				// Translators: replace this with your name(s), one per line, to
				// be credited in the About dialog. It is not shown when
				// untranslated.
				translator_credits = _("translator-credits"),
				website = Config.PROJECT_WEBSITE,
				issue_url = Config.ISSUE_URL,
				// Directly embed the most recent release notes. These are not
				// marked translatable, for now.
				release_notes_version = "0.2.0",
				release_notes = "<p>Snapshot Explorer is now built with libadwaita and GTK 4.</p>",
			};
			dialog.add_legal_section (
				// Translators: the heading of a section on the Legal page of the
				// About dialog, covering the parts under a different licence.
				_("Nautilus Extension and Shared Components"),
				"© 2021–2026 Aaron Jacobs",
				Gtk.License.LGPL_2_1,
				null
			);
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
			if (root == null || ((!) root).n_children () == 0) {
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
			if (item.data.has_prefix (parent)) {
				this.label = item.data.substring (parent.length);
			} else {
				this.label = item.data;
			}
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
