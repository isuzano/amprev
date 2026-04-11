/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Markdown syntax highlighter for the editor buffer.
 */

namespace Astware.Amprev {
    /* Keeps Markdown styling local to the editor buffer.
     * Highlighting is rebuilt from the buffer snapshot and uses Unicode character offsets.
     */
    public class EditorHighlightService : Object {
        private const string heading_dark = "#8ab4ff";
        private const string accent_dark = "#7aa2ff";
        private const string muted_dark = "#a9b0bf";
        private const string code_bg_dark = "#1d2230";
        private const string code_fg_dark = "#eef2f7";
        private const string quote_bg_dark = "#191e29";

        private const string heading_light = "#0f62fe";
        private const string accent_light = "#0969da";
        private const string muted_light = "#57606a";
        private const string code_bg_light = "#eef2f7";
        private const string code_fg_light = "#1f2328";
        private const string quote_bg_light = "#f3f5f8";

        private Gtk.TextBuffer? buffer;
        private Adw.StyleManager style_manager;
        private uint update_timeout_id = 0;
        private bool applying = false;

        private Gtk.TextTag? heading_tag;
        private Gtk.TextTag? bold_tag;
        private Gtk.TextTag? italic_tag;
        private Gtk.TextTag? inline_code_tag;
        private Gtk.TextTag? code_block_tag;
        private Gtk.TextTag? blockquote_tag;
        private Gtk.TextTag? list_tag;
        private Gtk.TextTag? link_tag;
        private Gtk.TextTag? fence_tag;

        public void bind (Gtk.TextBuffer buffer) {
            this.buffer = buffer;
            style_manager = Adw.StyleManager.get_default ();
            ensure_tags ();
            buffer.changed.connect (() => {
                schedule_update ();
            });
            style_manager.notify["color-scheme"].connect (() => {
                ensure_tags ();
                apply_highlight ();
            });
            apply_highlight ();
        }

        private void ensure_tags () {
            if (buffer == null) {
                return;
            }

            if (heading_tag == null) {
                heading_tag = buffer.create_tag ("amprev-heading", null);
                bold_tag = buffer.create_tag ("amprev-bold", null);
                italic_tag = buffer.create_tag ("amprev-italic", null);
                inline_code_tag = buffer.create_tag ("amprev-inline-code", null);
                code_block_tag = buffer.create_tag ("amprev-code-block", null);
                blockquote_tag = buffer.create_tag ("amprev-blockquote", null);
                list_tag = buffer.create_tag ("amprev-list", null);
                link_tag = buffer.create_tag ("amprev-link", null);
                fence_tag = buffer.create_tag ("amprev-fence", null);
            }

            bool dark = style_manager != null && style_manager.dark;
            apply_tag_colors (
                dark ? heading_dark : heading_light,
                dark ? accent_dark : accent_light,
                dark ? muted_dark : muted_light,
                dark ? code_bg_dark : code_bg_light,
                dark ? code_fg_dark : code_fg_light,
                dark ? quote_bg_dark : quote_bg_light
            );
        }

        private void apply_tag_colors (
            string heading_color,
            string accent_color,
            string muted_color,
            string code_background,
            string code_foreground,
            string quote_background
        ) {
            if (heading_tag != null) {
                heading_tag.weight = Pango.Weight.BOLD;
                heading_tag.foreground_rgba = color_for (heading_color);
            }

            if (bold_tag != null) {
                bold_tag.weight = Pango.Weight.BOLD;
                bold_tag.foreground_rgba = color_for (code_foreground);
            }

            if (italic_tag != null) {
                italic_tag.style = Pango.Style.ITALIC;
                italic_tag.foreground_rgba = color_for (muted_color);
            }

            if (inline_code_tag != null) {
                inline_code_tag.family = "monospace";
                inline_code_tag.foreground_rgba = color_for (code_foreground);
                inline_code_tag.background_rgba = color_for (code_background);
            }

            if (code_block_tag != null) {
                code_block_tag.family = "monospace";
                code_block_tag.foreground_rgba = color_for (code_foreground);
                code_block_tag.background_rgba = color_for (code_background);
                code_block_tag.paragraph_background_rgba = color_for (code_background);
            }

            if (blockquote_tag != null) {
                blockquote_tag.foreground_rgba = color_for (muted_color);
                blockquote_tag.style = Pango.Style.ITALIC;
                blockquote_tag.paragraph_background_rgba = color_for (quote_background);
            }

            if (list_tag != null) {
                list_tag.foreground_rgba = color_for (muted_color);
            }

            if (link_tag != null) {
                link_tag.foreground_rgba = color_for (accent_color);
                link_tag.underline = Pango.Underline.SINGLE;
            }

            if (fence_tag != null) {
                fence_tag.family = "monospace";
                fence_tag.foreground_rgba = color_for (muted_color);
            }
        }

        private Gdk.RGBA color_for (string hex) {
            var rgba = Gdk.RGBA ();
            rgba.parse (hex);
            return rgba;
        }

        private void schedule_update () {
            if (applying) {
                return;
            }

            if (update_timeout_id != 0) {
                GLib.Source.remove (update_timeout_id);
                update_timeout_id = 0;
            }

            update_timeout_id = GLib.Timeout.add (35, () => {
                update_timeout_id = 0;
                apply_highlight ();
                return false;
            });
        }

        private void apply_highlight () {
            if (buffer == null || applying) {
                return;
            }

            applying = true;

            Gtk.TextIter start;
            Gtk.TextIter end;
            buffer.get_bounds (out start, out end);
            buffer.remove_all_tags (start, end);

            string text = buffer.get_text (start, end, true);
            highlight_text (text);

            applying = false;
        }

        private void highlight_text (string text) {
            if (buffer == null) {
                return;
            }

            string[] lines = text.split ("\n");
            int offset = 0;
            bool in_code_block = false;

            foreach (string line in lines) {
                string trimmed = line.strip ();
                int line_start = offset;
                int line_length = line.char_count ();
                int line_end = line_start + line_length;

                if (in_code_block) {
                    apply_tag (line_start, line_end, code_block_tag);
                    if (is_code_fence (trimmed)) {
                        apply_tag (line_start, line_end, fence_tag);
                        in_code_block = false;
                    }
                } else if (is_code_fence (trimmed)) {
                    apply_tag (line_start, line_end, fence_tag);
                    in_code_block = true;
                } else {
                    if (is_heading (trimmed)) {
                        apply_tag (line_start, line_end, heading_tag);
                    } else if (is_blockquote (trimmed)) {
                        apply_tag (line_start, line_end, blockquote_tag);
                    } else if (is_list_item (trimmed)) {
                        apply_tag (line_start, line_end, list_tag);
                    }

                    highlight_inline (line, line_start);
                }

                offset += line_length + 1;
            }
        }

        private void highlight_inline (string line, int line_start) {
            int index = 0;
            while (index < line.length) {
                if (try_mark_code (line, line_start, ref index)) {
                    continue;
                }

                if (try_mark_link (line, line_start, ref index)) {
                    continue;
                }

                if (try_mark_bold (line, line_start, ref index)) {
                    continue;
                }

                if (try_mark_italic (line, line_start, ref index)) {
                    continue;
                }

                index++;
            }
        }

        private bool try_mark_code (string line, int line_start, ref int index) {
            if (line.get_char (index) != '`') {
                return false;
            }

            int end = line.index_of_char ('`', index + 1);
            if (end < 0) {
                return false;
            }

            apply_tag (line_start + char_offset_in_line (line, index), line_start + char_offset_in_line (line, end + 1), inline_code_tag);
            index = end + 1;
            return true;
        }

        private bool try_mark_link (string line, int line_start, ref int index) {
            if (line.get_char (index) != '[') {
                return false;
            }

            int close_bracket = line.index_of_char (']', index + 1);
            if (close_bracket < 0 || close_bracket + 1 >= line.length || line.get_char (close_bracket + 1) != '(') {
                return false;
            }

            int close_paren = line.index_of_char (')', close_bracket + 2);
            if (close_paren < 0) {
                return false;
            }

            apply_tag (line_start + char_offset_in_line (line, index), line_start + char_offset_in_line (line, close_paren + 1), link_tag);
            index = close_paren + 1;
            return true;
        }

        private bool try_mark_bold (string line, int line_start, ref int index) {
            if (line.get_char (index) != '*' || index + 1 >= line.length || line.get_char (index + 1) != '*') {
                return false;
            }

            int end = line.index_of ("**", index + 2);
            if (end < 0) {
                return false;
            }

            apply_tag (line_start + char_offset_in_line (line, index), line_start + char_offset_in_line (line, end + 2), bold_tag);
            index = end + 2;
            return true;
        }

        private bool try_mark_italic (string line, int line_start, ref int index) {
            unichar marker = line.get_char (index);
            if (marker != '*' && marker != '_') {
                return false;
            }

            int end = line.index_of_char (marker, index + 1);
            if (end < 0) {
                return false;
            }

            if (marker == '*' && end + 1 < line.length && line.get_char (end + 1) == '*') {
                return false;
            }

            apply_tag (line_start + char_offset_in_line (line, index), line_start + char_offset_in_line (line, end + 1), italic_tag);
            index = end + 1;
            return true;
        }

        private int char_offset_in_line (string line, int byte_index) {
            if (byte_index <= 0) {
                return 0;
            }

            if (byte_index >= line.length) {
                return line.char_count ();
            }

            return line.substring (0, byte_index).char_count ();
        }

        private void apply_tag (int start_offset, int end_offset, Gtk.TextTag? tag) {
            if (buffer == null || tag == null || end_offset <= start_offset) {
                return;
            }

            Gtk.TextIter start_iter;
            Gtk.TextIter end_iter;
            buffer.get_iter_at_offset (out start_iter, start_offset);
            buffer.get_iter_at_offset (out end_iter, end_offset);
            buffer.apply_tag (tag, start_iter, end_iter);
        }

        private bool is_code_fence (string trimmed) {
            return trimmed.has_prefix ("```");
        }

        private bool is_heading (string trimmed) {
            int count = 0;
            while (count < trimmed.length && trimmed.get_char (count) == '#') {
                count++;
            }

            return count > 0 && count <= 6 && count < trimmed.length && trimmed.get_char (count) == ' ';
        }

        private bool is_blockquote (string trimmed) {
            return trimmed.has_prefix (">");
        }

        private bool is_list_item (string trimmed) {
            return trimmed.has_prefix ("- ")
                || trimmed.has_prefix ("* ")
                || trimmed.has_prefix ("+ ")
                || Regex.match_simple ("^\\d+\\.\\s+", trimmed);
        }
    }
}
