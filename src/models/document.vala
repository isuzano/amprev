/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Markdown document state shared across services and views.
 */

namespace Astware.Amprev {
    /* Source of truth for the editor and preview; it tracks the active text, rendered HTML,
     * and save/export identity without knowing anything about the window.
     */
    public class Document : Object {
        private string markdown = "";
        private string html = "";
        private string file_stem = "untitled";
        private string source_file_path = "";
        private string saved_markdown = "";

        public signal void markdown_changed (string markdown);
        public signal void html_changed (string html);

        public string get_markdown () {
            return markdown;
        }

        public string get_html () {
            return html;
        }

        public string get_file_stem () {
            return file_stem;
        }

        public string get_source_file_path () {
            return source_file_path;
        }

        public bool has_source_file () {
            return source_file_path != "";
        }

        /* The save action is only meaningful when a source file exists and the buffer diverged
         * from the last persisted snapshot.
         */
        public bool can_save () {
            return has_source_file () && markdown != saved_markdown;
        }

        public string get_markdown_export_name () {
            return "%s.md".printf (file_stem);
        }

        public string get_pdf_export_name () {
            return "%s.pdf".printf (file_stem);
        }

        public void set_markdown (string markdown) {
            this.markdown = markdown;
            markdown_changed (markdown);
        }

        public void set_html (string html) {
            this.html = html;
            html_changed (html);
        }

        public void set_source_file_name (string file_name) {
            file_stem = stem_from_name (file_name);
        }

        public void set_source_file_path (string path) {
            source_file_path = path;
            set_source_file_name (GLib.Path.get_basename (path));
        }

        public void set_saved_markdown (string markdown) {
            saved_markdown = markdown;
        }

        private string stem_from_name (string file_name) {
            string stem = file_name;
            int last_dot = stem.last_index_of_char ('.');
            if (last_dot > 0) {
                stem = stem.substring (0, last_dot);
            }

            if (stem == "") {
                return "untitled";
            }

            return stem;
        }
    }
}
