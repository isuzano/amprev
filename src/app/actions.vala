/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Action wiring for the application window.
 */

namespace Astware.Amprev {
    /* Centralizes window actions and keeps all menu behavior behind Gio.SimpleAction.
     * The editor remains the source of truth; this class coordinates persistence,
     * preview refresh, export, theme, and sync policy.
     */
    public class Actions : Object {
        private MainWindow window;
        private Document document;
        private MarkdownEngine engine;
        private ExportService export_service;
        private SyncService sync_service;
        private ThemeService theme_service;
        private EditorHighlightService highlight_service;
        private SimpleAction save_action;
        private SimpleAction sync_action;
        private SimpleAction theme_action;
        private uint render_timeout_id = 0;
        private string pending_markdown = "";

        public Actions (
            MainWindow window,
            Document document,
            MarkdownEngine engine,
            ExportService export_service,
            SyncService sync_service,
            ThemeService theme_service
        ) {
            this.window = window;
            this.document = document;
            this.engine = engine;
            this.export_service = export_service;
            this.sync_service = sync_service;
            this.theme_service = theme_service;
            this.highlight_service = new EditorHighlightService ();

            install_actions ();
            bind_signals ();
            highlight_service.bind (window.get_editor_buffer ());
        }

        private void install_actions () {
            var open_action = new SimpleAction ("open-file", null);
            open_action.activate.connect ((parameter) => {
                open_document.begin ();
            });
            window.add_action (open_action);

            save_action = new SimpleAction ("save", null);
            save_action.activate.connect ((parameter) => {
                save_document ();
            });
            save_action.set_enabled (false);
            window.add_action (save_action);

            var export_markdown_action = new SimpleAction ("export-markdown", null);
            export_markdown_action.activate.connect ((parameter) => {
                export_markdown_document.begin ();
            });
            window.add_action (export_markdown_action);

            var export_action = new SimpleAction ("export-pdf", null);
            export_action.activate.connect ((parameter) => {
                export_document.begin ();
            });
            window.add_action (export_action);

            sync_action = new SimpleAction.stateful (
                "sync-scroll",
                null,
                new Variant.boolean (sync_service.enabled)
            );
            sync_action.change_state.connect ((variant) => {
                bool enabled = variant.get_boolean ();
                sync_service.set_enabled (enabled);
                sync_action.set_state (variant);
            });
            window.add_action (sync_action);

            theme_action = new SimpleAction.stateful (
                "theme",
                new GLib.VariantType ("s"),
                new GLib.Variant.string (theme_service.mode_key)
            );
            theme_action.change_state.connect ((variant) => {
                string key = variant.get_string ();
                theme_service.set_mode (ThemeService.mode_from_key (key));
                theme_action.set_state (new GLib.Variant.string (theme_service.mode_key));
            });
            window.add_action (theme_action);

            theme_service.mode_changed.connect ((mode) => {
                theme_action.set_state (new GLib.Variant.string (ThemeService.mode_to_key (mode)));
            });

            window.set_menu_model (build_menu_model ());
        }

        private void bind_signals () {
            window.markdown_changed.connect ((markdown) => {
                update_markdown (markdown);
            });

            document.html_changed.connect ((html) => {
                window.update_preview (html);
            });
        }

        private GLib.MenuModel build_menu_model () {
            var menu = new GLib.Menu ();

            var file_menu = new GLib.Menu ();
            file_menu.append ("Open File", "win.open-file");
            file_menu.append ("Save", "win.save");
            menu.append_section (null, file_menu);

            var export_menu = new GLib.Menu ();
            export_menu.append ("Export Markdown", "win.export-markdown");
            export_menu.append ("Export PDF", "win.export-pdf");
            menu.append_section (null, export_menu);

            var options = new GLib.Menu ();
            options.append ("Sync scroll", "win.sync-scroll");

            var theme_menu = new GLib.Menu ();
            var system_item = new GLib.MenuItem ("System", null);
            system_item.set_action_and_target_value ("win.theme", new GLib.Variant.string ("system"));
            theme_menu.append_item (system_item);

            var light_item = new GLib.MenuItem ("Light", null);
            light_item.set_action_and_target_value ("win.theme", new GLib.Variant.string ("light"));
            theme_menu.append_item (light_item);

            var dark_item = new GLib.MenuItem ("Dark", null);
            dark_item.set_action_and_target_value ("win.theme", new GLib.Variant.string ("dark"));
            theme_menu.append_item (dark_item);
            options.append_submenu ("Theme", theme_menu);

            menu.append_section (null, options);

            return menu;
        }

        private async void open_document () {
            var dialog = new Gtk.FileDialog ();
            dialog.set_title ("Open File");
            dialog.set_modal (true);
            dialog.set_accept_label ("Open");

            var filter = new Gtk.FileFilter ();
            filter.set_filter_name ("Text files");
            filter.add_suffix ("md");
            dialog.set_default_filter (filter);

            try {
                GLib.File file = yield dialog.open (window, null);
                if (file == null) {
                    return;
                }

                string? path = file.get_path ();
                if (path == null) {
                    window.show_toast ("Open file failed: unsupported destination");
                    return;
                }

                string contents;
                size_t length;
                if (!GLib.FileUtils.get_contents (path, out contents, out length)) {
                    window.show_toast ("Open file failed: unable to read file");
                    return;
                }

                document.set_source_file_path (path);
                document.set_saved_markdown (contents);
                window.set_markdown (contents);
                update_save_action_state ();
            } catch (Error error) {
                window.show_toast (error.message);
            }
        }

        private void save_document () {
            if (!document.has_source_file ()) {
                return;
            }

            if (!document.can_save ()) {
                return;
            }

            var file = GLib.File.new_for_path (document.get_source_file_path ());
            export_service.export_markdown (document.get_markdown (), file, (success, message) => {
                if (!success && message != null) {
                    window.show_toast (message);
                    return;
                }

                document.set_saved_markdown (document.get_markdown ());
                update_save_action_state ();
            });
        }

        private async void export_markdown_document () {
            var dialog = new Gtk.FileDialog ();
            dialog.set_title ("Export Markdown");
            dialog.set_modal (true);
            dialog.set_accept_label ("Export");
            dialog.set_initial_name (document.get_markdown_export_name ());

            var filter = new Gtk.FileFilter ();
            filter.set_filter_name ("Markdown files");
            filter.add_suffix ("md");
            dialog.set_default_filter (filter);

            try {
                GLib.File file = yield dialog.save (window, null);
                if (file == null) {
                    return;
                }

                export_service.export_markdown (document.get_markdown (), file, (success, message) => {
                    if (!success && message != null) {
                        window.show_toast (message);
                    }
                });
            } catch (Error error) {
                window.show_toast (error.message);
            }
        }

        private async void export_document () {
            var dialog = new Gtk.FileDialog ();
            dialog.set_title ("Export PDF");
            dialog.set_modal (true);
            dialog.set_accept_label ("Export");
            dialog.set_initial_name (document.get_pdf_export_name ());

            var filter = new Gtk.FileFilter ();
            filter.set_filter_name ("PDF files");
            filter.add_suffix ("pdf");
            dialog.set_default_filter (filter);

            try {
                GLib.File file = yield dialog.save (window, null);
                if (file == null) {
                    return;
                }

                export_service.export_pdf (window.get_preview_web_view (), file, (success, message) => {
                    if (!success && message != null) {
                        window.show_toast (message);
                    }
                });
            } catch (Error error) {
                window.show_toast (error.message);
            }
        }

        private void update_markdown (string markdown) {
            document.set_markdown (markdown);
            update_save_action_state ();
            pending_markdown = markdown;
            schedule_render ();
        }

        private void update_save_action_state () {
            save_action.set_enabled (document.can_save ());
        }

        private void schedule_render () {
            if (render_timeout_id != 0) {
                GLib.Source.remove (render_timeout_id);
                render_timeout_id = 0;
            }

            string markdown = pending_markdown;

            /* Debounce typing so the preview updates with the newest stable snapshot instead
             * of re-rendering on every keystroke.
             */
            render_timeout_id = GLib.Timeout.add (90, () => {
                render_timeout_id = 0;
                engine.render_async (markdown, (html) => {
                    document.set_html (html);
                });

                return false;
            });
        }
    }
}
