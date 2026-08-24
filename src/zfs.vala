/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * SPDX-FileCopyrightText: Copyright 2021 Aaron Jacobs
 */

namespace Zfs {
	public async Node<string> mountpoint_tree () throws Error {
		if (!yield has_zfs_utils ()) {
			throw no_zfs_utils_error ();
		}
		if (Environment.get_variable("SNAPSHOT_EXPLORER_DEBUG_LATENCY") == "1") {
			yield nap(2000);
		}
		string[] argv;
		if (sandboxed ()) {
			argv = {
				"flatpak-spawn", "--host", "zfs", "list", "-Hp", "-t",
				"filesystem", "-o", "mountpoint,canmount,mounted", "-s",
				"mountpoint"
			};
		} else {
			argv = {
				"zfs", "list", "-Hp", "-t", "filesystem", "-o",
				"mountpoint,canmount,mounted", "-s", "mountpoint"
			};
		}
		var mountpoints = new List<string> ();
		try {
			var code = yield exec_and_stream (argv, null, (line) => {
				string[] columns = line.split("\t");
				if (columns.length != 3) {
					throw malformed_output_error ("zfs list");
				}
				if (columns[0].ascii_casecmp ("none") == 0) {
					return;
				}
				if (columns[1].ascii_casecmp ("off") == 0) {
					return;
				}
				if (columns[2].ascii_casecmp ("no") == 0) {
					return;
				}
				mountpoints.append (columns[0]);
			});
			if (code != 0) {
				throw command_failed_error ("zfs list", code);
			}
		} catch (IOError e) {
			throw e;
		} catch (Error e) {
			throw new IOError.FAILED (
				_("Failed to list mounted ZFS filesystems: %s").printf (e.message)
			);
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

	public async List<Fs.Snapshot> snapshots_for_path (
		string path, Cancellable? cancellable = null
	) throws Error {
		var result = new List<Fs.Snapshot> ();
		if (!yield has_zfs_utils ()) {
			throw no_zfs_utils_error ();
		}
		if (Environment.get_variable("SNAPSHOT_EXPLORER_DEBUG_LATENCY") == "1") {
			yield nap(2000);
		}
		string mountpoint = yield find_mountpoint (path, cancellable);
		string relpath = "";
		if (mountpoint == "/") {
			if (path.has_prefix ("/")) {
				relpath = path.substring (1);
			} else {
				relpath = path;
			}
		} else if (path.has_prefix (mountpoint + "/")) {
			relpath = path.substring (mountpoint.length + 1);
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
			var code = yield exec_and_stream (argv, cancellable, (line) => {
				string[] columns = line.split("\t");
				if (columns.length != 2) {
					throw malformed_output_error ("zfs list");
				}
				string[] name = columns[0].split("@");
				if (name.length != 2) {
					throw malformed_output_error ("zfs list");
				}
				int64? created;
				if (!int64.try_parse (columns[1], out created)) {
					throw malformed_output_error ("zfs list");
				}
				result.append (new Fs.Snapshot (
					name[1],
					File.new_for_path (
						Path.build_filename (
							mountpoint, ".zfs", "snapshot", name[1], relpath
						)
					).get_uri (),
					new DateTime.from_unix_local ((!) created)
				));
			});
			if (code != 0) {
				throw command_failed_error ("zfs list", code);
			}
		} catch (IOError e) {
			throw e;
		} catch (Error e) {
			throw new IOError.FAILED (
				_("Failed to query ZFS snapshots: %s").printf (e.message)
			);
		}
		return (owned) result;
	}

	private static async string find_mountpoint (
		string path, Cancellable? cancellable
	) throws Error {
		string[] argv;
		if (sandboxed ()) {
			argv = {
				"flatpak-spawn", "--host", "zfs", "list", "-Hp", "-o",
				"mountpoint", path
			};
		} else {
			argv = { "zfs", "list", "-Hp", "-o", "mountpoint", path };
		}
		string? mountpoint = null;
		try {
			var code = yield exec_and_stream (argv, cancellable, (line) => {
				if (mountpoint == null) {
					mountpoint = line.dup ();
				}
			});
			if (code != 0 || mountpoint == null) {
				throw unsupported_path_error ();
			}
			mountpoint = mountpoint?.strip ();
			if (mountpoint == "" || mountpoint == "none" ||
				mountpoint == "legacy" || mountpoint == "-") {
				throw unsupported_path_error ();
			}
			return (!) mountpoint;
		} catch (IOError.CANCELLED e) {
			throw e;
		} catch (Fs.Error e) {
			throw e;
		} catch (Error e) {
			throw new IOError.FAILED (
				_("Failed to determine ZFS mountpoint containing \"%s\": %s").
				printf (path, e.message)
			);
		}
	}

	private static Error no_zfs_utils_error () {
		return new IOError.FAILED (_("No ZFS CLI available."));
	}

	private static Error malformed_output_error (string cmd) {
		return new IOError.FAILED (
			_("Unexpected or malformed '%s' output.").printf (cmd)
		);
	}

	private static Error command_failed_error (string cmd, int exit_status) {
		return new IOError.FAILED (
			_("'%s' failed with status %d.").printf (cmd, exit_status)
		);
	}

	private static Error unsupported_path_error () {
		return new Fs.Error.NOT_SUPPORTED (_("Not a ZFS filesystem."));
	}

	private delegate void LineHandler (string line) throws Error;

	private static async int exec_and_stream (
		string[] argv,
		Cancellable? cancellable,
		LineHandler handler
	) throws Error {
		var proc = new Subprocess.newv (
			argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE
		);
		try {
			var stream = new DataInputStream ((!) proc.get_stdout_pipe ());
			string? line;
			while ((line = yield stream.read_line_async (Priority.DEFAULT, cancellable)) != null) {
				handler ((!) line);
			}
			yield proc.wait_async ();
			return proc.get_exit_status ();
		} catch (Error e) {
			proc.force_exit ();
			try {
				yield proc.wait_async ();
			} catch (Error wait_error) {
				warning ("Failed to reap child process: %s", wait_error.message);
			}
			throw e;
		}
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

	// Async version of "sleep", from the Vala wiki.
	private async void nap (uint interval, int priority = GLib.Priority.DEFAULT) {
		GLib.Timeout.add (interval, () => {
				nap.callback ();
				return false;
			}, priority);
		yield;
	}
}
