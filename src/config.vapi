/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: Copyright 2026 Aaron Jacobs
 */
[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "config.h")]
namespace Config {
	public const string APP_ID;
	public const string VERSION;
	public const string PROJECT_WEBSITE;
	public const string ISSUE_URL;
	public const string GETTEXT_PACKAGE;
	public const string LOCALEDIR;
}
