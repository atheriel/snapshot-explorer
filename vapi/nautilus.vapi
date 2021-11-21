[CCode (cheader_filename = "nautilus-extension.h")]
namespace Nautilus {
	public interface LocationWidgetProvider : GLib.Object {
		public abstract Gtk.Widget? get_widget(string uri, Gtk.Widget window);
	}
}
