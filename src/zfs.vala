/* -*- mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * SPDX-FileCopyrightText: 2021 Aaron Jacobs
 */

namespace Zfs {
	public class Snapshot {
		public string name;
		public string path;
		public DateTime created;

		public Snapshot (string name, string path, DateTime created) {
			this.name = name;
			this.path = path;
			this.created = created;
		}

		public enum AgeRange {
			TODAY,
			YESTERDAY,
			THIS_WEEK,
			THIS_YEAR,
			PREVIOUS_YEARS,
		}

		public struct Timestamp {
			public string display;
			public AgeRange range;
		}

		public Timestamp timestamp () {
			var now = new DateTime.now_local ();
			var hours_today = now.get_hour ();
			var since = now.difference (created);
			string timestamp = created.format ("%X");
			string day;
			AgeRange range;
			if (since < TimeSpan.HOUR * hours_today) {
				day = _("Today");
				range = AgeRange.TODAY;
			} else if (since < TimeSpan.HOUR * (hours_today + 24)) {
				day = _("Yesterday");
				range = AgeRange.YESTERDAY;
			} else if (since < TimeSpan.HOUR * (hours_today + 6 * 24)) {
				day = created.format ("%A");
				range = AgeRange.THIS_WEEK;
			} else if (since < TimeSpan.DAY * now.get_day_of_year ()) {
				day = created.format ("%b %-e");
				range = AgeRange.THIS_YEAR;
			} else {
				day = created.format ("%Y-%m-%d");
				range = AgeRange.PREVIOUS_YEARS;
			}
			return {
				_("%s at %s").printf (day, timestamp),
				range,
			};
		}
	}

	public async Node<string>? mountpoint_tree () {
		if (!yield has_zfs_utils ()) {
			return null;
		}
		string[] argv;
		if (sandboxed ()) {
			argv = {
				"flatpak-spawn", "--host", "zfs", "list", "-Hp", "-t",
				"filesystem", "-o", "mountpoint,canmount", "-s", "mountpoint"
			};
		} else {
			argv = {
				"zfs", "list", "-Hp", "-t", "filesystem", "-o",
				"mountpoint,canmount", "-s", "mountpoint"
			};
		}
		var mountpoints = new List<string> ();
		try {
			var proc = new Subprocess.newv (argv, SubprocessFlags.STDOUT_PIPE);
			var stream = new DataInputStream ((!) proc.get_stdout_pipe ());
			string? line;
			while ((line = yield stream.read_line_async()) != null) {
				string[] columns = ((!) line).split("\t");
				if (columns.length != 2) {
					continue;
				}
				if (columns[0].ascii_casecmp ("none") == 0) {
					continue;
				}
				if (columns[1].ascii_casecmp ("off") == 0) {
					continue;
				}
				mountpoints.append (columns[0]);
			}
		} catch (Error e) {
			// TODO: Better error reporting.
			print ("error: mountpoint_tree(): %s\n", e.message);
			return null;
		}

		return tree_from_list ((owned) mountpoints);
	}

	/* This translates a list of paths that might represent ZFS datasets, e.g.
	 *
	 *	  /home, /home/user, /home/user2, /home/user2/Documents,
	 *	  /mnt/backup, /mnt/backup/user2, /mnt/backup/user2/Documents
	 *
	 * Into a directed graph
	 *
	 *	  /home
	 *	   |--> /home/user
	 *	   |--> /home/user2
	 *			 |--> /home/user2/Documents
	 *	  /mnt/backup
	 *	   |--> /mnt/backup/user2
	 *			 |--> /home/user2/Documents
	 *
	 * The *purpose* of this is to make collapsible/nested folder structures in
	 * the sidebar pane.
	 *
	 * The actual *implementation* is pretty awkward, because GLib.Node<string>
	 * structures must be built up from leaf-to-root to preserve ownership.
	 *
	 * We take the following approach:
	 *
	 * Loop over the list in reverse, keeping a FILO queue of sibling nodes
	 * and appending them to parent nodes when encountered. The remainder are
	 * re-queued until the end, where they're stuffed into a (hidden) root node.
	 */
	private Node<string> tree_from_list (List<string> mountpoints) {
		var root = new Node<string> ("<root>");
		if (mountpoints.length () == 0) {
			return (owned) root;
		}

		// TODO: This is probably not necessary, zfs list should do it for us.
		mountpoints.sort ((a, b) => { return strcmp(a, b); });
		mountpoints.reverse ();

		Node<string>? elt;
		var stack = new Queue<Node<string>> ();
		stack.push_tail (new Node<string> (mountpoints.data.dup ()));
		unowned var prev = stack.peek_tail ();
		// print ("queue sibling, mountpoint=%s \n", prev.data);

		for (int i = 1; i < mountpoints.length (); i++) {
			string m = mountpoints.nth_data (i).dup ();
			if (prev.data.has_prefix (m)) {
				// print ("found parent, mountpoint=%s\n", m);
				var parent = new Node<string> (m);
				while ((elt = stack.pop_tail()) != null) {
					/* This might occur when we get sequences like
					 *
					 *	   /home/b, /home/a/c, /home/a
					 *
					 * or
					 *
					 *	   /mnt/data, /home/a/c, /home/a
					 */
					if (!((!)elt).data.has_prefix (m)) {
						// print ("re-queue nonmatching, parent=%s mountpoint=%s\n", parent.data, elt.data);
						stack.push_tail ((!) (owned) elt);
						break;
					}
					// print ("appending child, parent=%s child=%s\n", parent.data, elt.data);
					parent.append ((!) (owned) elt);
				}
				stack.push_tail ((owned) parent);
			} else {
				stack.push_tail (new Node<string> (m));
			}
			prev = stack.peek_tail ();
			// print ("queue sibling, mountpoint=%s\n", prev.data);
		}

		while ((elt = stack.pop_tail()) != null) {
			// print ("declared root, mountpoint=%s\n", elt.data);
			root.append ((!) (owned) elt);
		}

		return (owned) root;
	}

	public async List<Snapshot> snapshots_for_path (string path) {
		var result = new List<Snapshot> ();
		if (!yield has_zfs_utils ()) {
			return (owned) result;
		}
		string[] argv;
		if (sandboxed ()) {
			argv = {
				"flatpak-spawn", "--host", "zfs", "list", "-Hp", "-t",
				"snapshot", "-o", "name,creation", "-S", "creation", path
			};
		} else {
			argv = {
				"zfs", "list", "-Hp", "-t", "snapshot", "-o", "name,creation",
				"-S", "creation", path
			};
		}
		try {
			var proc = new Subprocess.newv (argv, SubprocessFlags.STDOUT_PIPE);
			var stream = new DataInputStream ((!) proc.get_stdout_pipe ());
			string? line;
			// TODO: Handle malformed input instead of ignoring it.
			while ((line = yield stream.read_line_async()) != null) {
				string[] columns = ((!) line).split("\t");
				if (columns.length != 2) {
					continue;
				}
				string[] name = columns[0].split("@");
				if (name.length != 2) {
					continue;
				}
				int64? created;
				if (!int64.try_parse (columns[1], out created)) {
					continue;
				}
				result.append (new Snapshot (
					name[1],
					Path.build_filename (
						"file://", path, ".zfs/snapshot", name[1]
					),
					new DateTime.from_unix_local ((!) created)
				));
			}
		} catch (Error e) {
			// TODO: Better error reporting.
			print ("error: snapshots_for_path(): %s\n", e.message);
			return (owned) result;
		}
		return (owned) result;
	}

	static bool? _has_zfs_utils = null;

	private static async bool has_zfs_utils () {
		if (_has_zfs_utils == null) {
			string[] argv;
			if (sandboxed ()) {
				argv = { "flatpak-spawn", "--host", "which", "zfs" };
			} else {
				argv = { "which", "zfs" };
			}
			Subprocess proc;
			try {
				proc = new Subprocess.newv (
					argv, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE
				);
				yield proc.wait_async ();
				_has_zfs_utils = proc.get_exit_status() == 0;
			} catch (Error e) {
				warning (
					"Could not detect ZFS utilities, error in subprocess: %s, sandboxed=%s",
					e.message, sandboxed() ? "true" : "false"
				);
				_has_zfs_utils = false;
			}
			// TODO: Should we make use of structured logging, e.g.:
			// log_structured (
			//	   "SnapshotExplorer", LogLevelFlags.LEVEL_MESSAGE,
			//	   "SANDBOXED", sandboxed() ? "true" : "false",
			//	   "MESSAGE", "Found userspace ZFS utilities: %s",
			//	   _has_zfs_utils ? "true" : "false"
			// );
			message (
				"Finished search for userspace ZFS utilities, zfs_found=%s sandboxed=%s",
				(!) _has_zfs_utils ? "true" : "false",
				sandboxed() ? "true" : "false"
			);
		}
		return (!) _has_zfs_utils;
	}

	private static bool sandboxed () {
#if FLATPAK
		return true;
#else
		return false;
#endif
	}
}
