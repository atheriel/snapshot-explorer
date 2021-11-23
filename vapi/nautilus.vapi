[CCode (cheader_filename = "nautilus-extension.h")]
namespace Nautilus {
	public interface FileInfo : GLib.Object {
		public bool is_gone();
		public string get_name();
		public string get_uri();
		public string get_parent_uri();
		public string get_uri_scheme();
		public string get_mime_type();
		public bool is_mime_type(string mime_type);
		public bool is_directory();
		public void add_emblem(string emblem_name);
		public string get_string_attribute(string attribute_name);
		public void add_string_attribute(string attribute_name, string @value);
		public void invalidate_extension_info();
		public string get_activation_url();
		public GLib.FileType get_file_type();
		public GLib.File get_location();
		public GLib.File get_parent_location();
		public FileInfo get_parent_info();
		public GLib.Mount get_mount();
		public bool can_write();
	}

	public class Menu : GLib.Object {
		public void append_item(MenuItem item);
		public GLib.List<MenuItem> get_items();
		public Menu();
	}

	public class MenuItem : GLib.Object {
		public string name {set; get;}
		public string label {set; get;}
		public string tip {set; get;}
		public string icon {set; get;}
		public string menu {set; get;}
		public bool priority {set; get;}
		public bool sensitive {set; get;}
		public signal void activate();
		public void set_submenu(Menu menu);
		public MenuItem(string name, string label, string tip, string? icon = null);
	}

	public interface LocationWidgetProvider : GLib.Object {
		public abstract Gtk.Widget? get_widget(string uri, Gtk.Widget window);
	}

	public interface MenuProvider : GLib.Object {
		public abstract GLib.List<MenuItem>? get_file_items(Gtk.Widget window, GLib.List<FileInfo> files);
		public abstract GLib.List<MenuItem>? get_background_items(Gtk.Widget window, FileInfo current_folder);
	}
}
