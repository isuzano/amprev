/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * PDF export service backed by WebKit print output.
 */

namespace Astware.Amprev {
    public delegate void ExportCallback (bool success, string? message);

    /* Owns the file export boundary. Markdown writes are direct; PDF export stays tied to
     * WebKit's print backend and keeps the operation alive until the backend finishes.
     */
    public class ExportService : Object {
        private WebKit.PrintOperation? active_operation = null;

        public void export_markdown (string markdown, GLib.File target, ExportCallback callback) {
            string? target_path = target.get_path ();
            if (target_path == null) {
                callback (false, "Markdown export failed: unsupported destination");
                return;
            }

            try {
                string? new_etag = null;
                uint8[] contents = markdown.data;
                target.replace_contents (
                    contents,
                    null,
                    false,
                    GLib.FileCreateFlags.REPLACE_DESTINATION,
                    out new_etag
                );
                callback (true, null);
            } catch (Error error) {
                warning ("markdown export failed: %s", error.message);
                callback (false, "Markdown export failed: %s".printf (error.message));
            }
        }

        public void export_pdf (WebKit.WebView web_view, GLib.File target, ExportCallback callback) {
            if (active_operation != null) {
                callback (false, "PDF export already in progress");
                return;
            }

            active_operation = new WebKit.PrintOperation (web_view);
            var settings = new Gtk.PrintSettings ();

            string? target_path = target.get_path ();
            if (target_path == null) {
                clear_active_operation ();
                callback (false, "PDF export failed: unsupported destination");
                return;
            }

            string basename = target.get_basename ();
            string stem = strip_pdf_suffix (basename);
            string target_uri = target.get_uri ();
            settings.set (Gtk.PRINT_SETTINGS_PRINTER, "Print to File");
            settings.set (Gtk.PRINT_SETTINGS_OUTPUT_URI, target_uri);
            settings.set (Gtk.PRINT_SETTINGS_OUTPUT_FILE_FORMAT, "pdf");
            settings.set (Gtk.PRINT_SETTINGS_OUTPUT_BASENAME, stem);

            string? parent_path = GLib.Path.get_dirname (target_path);
            if (parent_path != null && parent_path != "") {
                settings.set (Gtk.PRINT_SETTINGS_OUTPUT_DIR, parent_path);
            }

            active_operation.set_print_settings (settings);
            active_operation.set_page_setup (new Gtk.PageSetup ());

            active_operation.failed.connect ((error) => {
                callback (false, error_message ((int) error));
                clear_active_operation ();
            });

            active_operation.finished.connect (() => {
                /* WebKit signals completion before the filesystem entry is always visible.
                 * This short verification loop makes the user-facing result explicit.
                 */
                verify_export_result (target, callback, 10);
            });

            active_operation.print ();
        }

        private void clear_active_operation () {
            active_operation = null;
        }

        private string error_message (int error) {
            if (error == (int) WebKit.PrintError.PRINTER_NOT_FOUND) {
                return "PDF export failed: printer not found";
            }

            if (error == (int) WebKit.PrintError.INVALID_PAGE_RANGE) {
                return "PDF export failed: invalid page range";
            }

            return "PDF export failed";
        }

        private string strip_pdf_suffix (string basename) {
            if (basename.has_suffix (".pdf")) {
                return basename.substring (0, basename.length - 4);
            }

            return basename;
        }

        private void verify_export_result (
            GLib.File target,
            ExportCallback callback,
            int attempts_left
        ) {
            if (target.query_exists ()) {
                callback (true, null);
                clear_active_operation ();
                return;
            }

            if (attempts_left <= 0) {
                callback (false, "PDF export failed: file was not created");
                clear_active_operation ();
                return;
            }

            GLib.Timeout.add (100, () => {
                verify_export_result (target, callback, attempts_left - 1);
                return false;
            });
        }
    }
}
