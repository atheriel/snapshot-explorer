/* -*- mode: vala; indent-tabs-mode: t; tab-width: 4 -*-
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * SPDX-FileCopyrightText: 2023 Aaron Jacobs
 */

namespace Fs {
	public enum Type {
		BTRFS,
		ZFS,
		NONE,
	}

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
}
