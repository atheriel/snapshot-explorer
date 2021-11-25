/* -*- mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * SPDX-FileCopyrightText: 2021 Aaron Jacobs
 */

/* DBus client for opening folders with the system's file manager. Implemented
 * by Nautilus and its derivatives, Dolphin, and others.
 *
 * See: https://www.freedesktop.org/wiki/Specifications/file-manager-interface/
 *
 * This is only a partial implementation.
 */
[DBus (name = "org.freedesktop.FileManager1")]
interface FileManager1 : Object {
	public abstract void show_folders (string[] uris, string startup_id)
		throws IOError, DBusError;
}
