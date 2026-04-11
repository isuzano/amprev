/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Main application window and view composition.
 */

namespace Astware.Amprev {
    /* Composes the visible shell of the app.
     * The window owns layout and presentation only; actions, rendering, and state flow stay external.
     */
    public class MainWindow : Adw.ApplicationWindow {
        private EditorView editor_view;
        private PreviewView preview_view;
        private Gtk.MenuButton menu_button;
        private Gtk.Label status_label;
        private uint status_clear_id = 0;

        public signal void markdown_changed (string markdown);

        public MainWindow (Gtk.Application application, SyncService sync_service) {
            Object (
                application: application,
                title: "amprev",
                default_width: 1320,
                default_height: 860
            );

            set_icon_name ("amprev");

            var toolbar_view = new Adw.ToolbarView ();
            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            set_content (toolbar_view);

            var header = build_header ();
            toolbar_view.add_top_bar (header);
            toolbar_view.set_content (root);

            var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            paned.wide_handle = true;
            paned.hexpand = true;
            paned.vexpand = true;
            paned.resize_start_child = true;
            paned.resize_end_child = true;
            paned.shrink_start_child = false;
            paned.shrink_end_child = false;

            editor_view = new EditorView ();
            preview_view = new PreviewView ();

            var editor_frame = wrap_view (editor_view);
            var preview_frame = wrap_view (preview_view);

            paned.set_start_child (editor_frame);
            paned.set_end_child (preview_frame);
            paned.set_position (720);
            root.append (paned);

            status_label = new Gtk.Label ("");
            status_label.visible = false;
            status_label.halign = Gtk.Align.START;
            status_label.margin_start = 18;
            status_label.margin_end = 18;
            status_label.margin_top = 8;
            status_label.margin_bottom = 12;
            status_label.add_css_class ("dim-label");
            root.append (status_label);

            editor_view.get_buffer ().changed.connect (() => {
                markdown_changed (get_markdown ());
            });

            sync_service.bind (editor_view, preview_view);
        }

        private Gtk.Widget build_header () {
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = true;
            header.show_end_title_buttons = true;

            var title_box = build_title_box ();

            menu_button = new Gtk.MenuButton ();
            menu_button.icon_name = "open-menu-symbolic";
            menu_button.has_frame = false;
            menu_button.tooltip_text = "Menu";
            menu_button.valign = Gtk.Align.CENTER;
            menu_button.margin_start = 6;

            header.title_widget = title_box;
            header.pack_start (menu_button);

            return header;
        }

        private Gtk.Widget build_title_box () {
            var title_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            title_box.halign = Gtk.Align.CENTER;
            title_box.valign = Gtk.Align.CENTER;

            string? local_icon = resolve_local_icon_path ();
            if (local_icon != null) {
                var image = new Gtk.Image.from_file (local_icon);
                image.pixel_size = 20;
                image.valign = Gtk.Align.CENTER;
                title_box.append (image);
            } else {
                var image = new Gtk.Image.from_icon_name ("amprev");
                image.pixel_size = 20;
                image.valign = Gtk.Align.CENTER;
                title_box.append (image);
            }

            var title = new Gtk.Label ("amprev");
            title.add_css_class ("title-4");
            title.valign = Gtk.Align.CENTER;
            title_box.append (title);

            return title_box;
        }

        private string? resolve_local_icon_path () {
            /* Build-tree icon lookup keeps terminal runs and local development in sync with the
             * installed icon name without adding runtime dependency on the source tree.
             */
            try {
                string exe_path = GLib.FileUtils.read_link ("/proc/self/exe");
                string exe_dir = GLib.Path.get_dirname (exe_path);
                string icon_path = GLib.Path.build_filename (exe_dir, "..", "data", "amprev.png");

                if (GLib.FileUtils.test (icon_path, GLib.FileTest.EXISTS)) {
                    return icon_path;
                }
            } catch (Error error) {
                warning ("title icon lookup failed: %s", error.message);
            }

            return null;
        }

        private Gtk.Widget wrap_view (Gtk.Widget child) {
            var frame = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            frame.hexpand = true;
            frame.vexpand = true;

            var scroller = new Gtk.Frame (null);
            scroller.hexpand = true;
            scroller.vexpand = true;
            scroller.set_child (child);

            frame.append (scroller);
            return frame;
        }

        public string get_markdown () {
            return editor_view.get_markdown ();
        }

        public void set_markdown (string markdown) {
            editor_view.set_markdown (markdown);
        }

        public void update_preview (string html) {
            preview_view.load_html (html);
        }

        public PreviewView get_preview_view () {
            return preview_view;
        }

        public Gtk.TextBuffer get_editor_buffer () {
            return editor_view.get_buffer ();
        }

        public WebKit.WebView get_preview_web_view () {
            return preview_view.get_web_view ();
        }

        public void set_menu_model (GLib.MenuModel menu_model) {
            menu_button.menu_model = menu_model;
        }

        public void show_toast (string message) {
            status_label.set_text (message);
            status_label.visible = true;

            if (status_clear_id != 0) {
                GLib.Source.remove (status_clear_id);
                status_clear_id = 0;
            }

            status_clear_id = GLib.Timeout.add_seconds (4, () => {
                status_clear_id = 0;
                status_label.set_text ("");
                status_label.visible = false;
                return false;
            });
        }
    }
}
