/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 *
 * Lightweight Markdown to HTML renderer used by the live preview.
 *
 * This is a deliberate subset renderer, not a full CommonMark engine.
 */

namespace Astware.Amprev {
    public delegate void RenderCallback (string html);

    /* Renders the editor snapshot into preview HTML.
     * This is a deliberate subset renderer and it keeps the preview side isolated from UI state.
     */
    public class MarkdownEngine : Object {
        private string css;

        public MarkdownEngine (string css) {
            this.css = css;
        }

        public void render_async (string markdown, RenderCallback callback) {
            string snapshot = markdown;
            try {
                new Thread<void*>.try ("amprev-markdown-render", () => {
                    string html = build_page (snapshot);
                    GLib.Idle.add (() => {
                        callback (html);
                        return false;
                    });
                    return null;
                });
            } catch (Error error) {
                warning ("markdown render thread failed: %s", error.message);
                callback (build_page (snapshot));
            }
        }

        public string build_error_page (string message) {
            var escaped = GLib.Markup.escape_text (message, -1);

            return """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>""" + css + """</style>
</head>
<body>
  <div class="error-page markdown-body">
    <h1>Preview error</h1>
    <p>""" + escaped + """</p>
  </div>
</body>
</html>
""";
        }

        private string build_page (string markdown) {
            string body = render_markdown (markdown ?? "");
            return """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>""" + css + """</style>
</head>
<body>
  <div class="markdown-body">""" + body + """</div>
</body>
</html>
""";
        }

        private string render_markdown (string markdown) {
            string normalized = markdown.replace ("\r\n", "\n").replace ("\r", "\n");
            string[] lines = normalized.split ("\n");
            var output = new StringBuilder ();

            int index = 0;
            while (index < lines.length) {
                string line = lines[index];
                string trimmed = line.strip ();

                if (trimmed.length == 0) {
                    index++;
                    continue;
                }

                if (is_code_fence (trimmed)) {
                    index = append_code_block (lines, index, output);
                    continue;
                }

                int level;
                if (is_heading (trimmed, out level)) {
                    string heading_text = trimmed.substring (level + 1, -1).strip ();
                    output.append ("<h");
                    output.append_printf ("%d", level);
                    output.append (">");
                    output.append (render_inline (heading_text));
                    output.append ("</h");
                    output.append_printf ("%d", level);
                    output.append (">\n");
                    index++;
                    continue;
                }

                if (is_blockquote (trimmed)) {
                    index = append_blockquote (lines, index, output);
                    continue;
                }

                if (is_list_item (trimmed)) {
                    index = append_list_block (lines, index, output);
                    continue;
                }

                index = append_paragraph (lines, index, output);
            }

            return output.str;
        }

        private int append_code_block (string[] lines, int start_index, StringBuilder output) {
            var code = new StringBuilder ();
            int index = start_index + 1;

            while (index < lines.length) {
                string line = lines[index];
                if (is_code_fence (line.strip ())) {
                    break;
                }

                code.append (line);
                if (index + 1 < lines.length) {
                    code.append_c ('\n');
                }
                index++;
            }

            output.append ("<pre><code>");
            output.append (GLib.Markup.escape_text (code.str, -1));
            output.append ("</code></pre>\n");

            return (index < lines.length) ? index + 1 : index;
        }

        private int append_blockquote (string[] lines, int start_index, StringBuilder output) {
            var quote = new StringBuilder ();
            int index = start_index;

            while (index < lines.length) {
                string trimmed = lines[index].strip ();
                if (!is_blockquote (trimmed)) {
                    break;
                }

                string content = trimmed.substring (1, -1).strip ();
                if (quote.len > 0) {
                    quote.append ("<br>");
                }
                quote.append (render_inline (content));
                index++;
            }

            output.append ("<blockquote><p>");
            output.append (quote.str);
            output.append ("</p></blockquote>\n");

            return index;
        }

        private int append_list_block (string[] lines, int start_index, StringBuilder output) {
            string first = lines[start_index].strip ();
            bool ordered = is_ordered_list_item (first);
            output.append (ordered ? "<ol>\n" : "<ul>\n");

            int index = start_index;
            while (index < lines.length) {
                string trimmed = lines[index].strip ();
                bool matches = ordered ? is_ordered_list_item (trimmed) : is_unordered_list_item (trimmed);
                if (!matches) {
                    break;
                }

                string item = ordered ? strip_ordered_prefix (trimmed) : strip_unordered_prefix (trimmed);
                output.append ("<li>");
                output.append (render_inline (item));
                output.append ("</li>\n");
                index++;
            }

            output.append (ordered ? "</ol>\n" : "</ul>\n");
            return index;
        }

        private int append_paragraph (string[] lines, int start_index, StringBuilder output) {
            var paragraph = new StringBuilder ();
            int index = start_index;

            while (index < lines.length) {
                string trimmed = lines[index].strip ();
                if (trimmed.length == 0 || is_block_start (trimmed)) {
                    break;
                }

                if (paragraph.len > 0) {
                    paragraph.append ("<br>");
                }
                paragraph.append (render_inline (trimmed));
                index++;
            }

            output.append ("<p>");
            output.append (paragraph.str);
            output.append ("</p>\n");

            return index;
        }

        private bool is_block_start (string trimmed) {
            int level;
            return is_code_fence (trimmed)
                || is_heading (trimmed, out level)
                || is_blockquote (trimmed)
                || is_list_item (trimmed);
        }

        private bool is_code_fence (string trimmed) {
            return trimmed.has_prefix ("```");
        }

        private bool is_heading (string trimmed, out int level) {
            level = 0;

            int count = 0;
            while (count < trimmed.length && trimmed.get_char (count) == '#') {
                count++;
            }

            if (count == 0 || count > 6) {
                return false;
            }

            if (count >= trimmed.length || trimmed.get_char (count) != ' ') {
                return false;
            }

            level = count;
            return true;
        }

        private bool is_blockquote (string trimmed) {
            return trimmed.has_prefix (">");
        }

        private bool is_list_item (string trimmed) {
            return is_unordered_list_item (trimmed) || is_ordered_list_item (trimmed);
        }

        private bool is_unordered_list_item (string trimmed) {
            return trimmed.has_prefix ("- ")
                || trimmed.has_prefix ("* ")
                || trimmed.has_prefix ("+ ");
        }

        private bool is_ordered_list_item (string trimmed) {
            return Regex.match_simple ("^\\d+\\.\\s+", trimmed);
        }

        private string strip_unordered_prefix (string trimmed) {
            return trimmed.substring (2, -1).strip ();
        }

        private string strip_ordered_prefix (string trimmed) {
            int dot = trimmed.index_of (". ");
            if (dot < 0) {
                return trimmed;
            }

            return trimmed.substring (dot + 2, -1).strip ();
        }

        private string render_inline (string text) {
            var output = new StringBuilder ();
            int index = 0;

            while (index < text.length) {
                int next = find_next_marker (text, index);
                if (next < 0) {
                    output.append (GLib.Markup.escape_text (text.substring (index, -1), -1));
                    break;
                }

                if (next > index) {
                    output.append (GLib.Markup.escape_text (text.substring (index, next - index), -1));
                    index = next;
                }

                if (try_append_code (text, ref index, output)) {
                    continue;
                }

                if (try_append_link (text, ref index, output)) {
                    continue;
                }

                if (try_append_bold (text, ref index, output)) {
                    continue;
                }

                if (try_append_italic (text, ref index, output)) {
                    continue;
                }

                output.append (GLib.Markup.escape_text (text.substring (index, 1), -1));
                index++;
            }

            return output.str;
        }

        private int find_next_marker (string text, int start_index) {
            int next = -1;
            int candidate;

            candidate = text.index_of_char ('`', start_index);
            next = choose_next (next, candidate);

            candidate = text.index_of_char ('[', start_index);
            next = choose_next (next, candidate);

            candidate = text.index_of_char ('*', start_index);
            next = choose_next (next, candidate);

            candidate = text.index_of_char ('_', start_index);
            next = choose_next (next, candidate);

            return next;
        }

        private int choose_next (int current, int candidate) {
            if (candidate < 0) {
                return current;
            }

            if (current < 0 || candidate < current) {
                return candidate;
            }

            return current;
        }

        private bool try_append_code (string text, ref int index, StringBuilder output) {
            if (text.get_char (index) != '`') {
                return false;
            }

            int end = text.index_of_char ('`', index + 1);
            if (end < 0) {
                return false;
            }

            string inner = text.substring (index + 1, end - index - 1);
            output.append ("<code>");
            output.append (GLib.Markup.escape_text (inner, -1));
            output.append ("</code>");
            index = end + 1;
            return true;
        }

        private bool try_append_link (string text, ref int index, StringBuilder output) {
            if (text.get_char (index) != '[') {
                return false;
            }

            int close_bracket = text.index_of_char (']', index + 1);
            if (close_bracket < 0 || close_bracket + 1 >= text.length || text.get_char (close_bracket + 1) != '(') {
                return false;
            }

            int close_paren = text.index_of_char (')', close_bracket + 2);
            if (close_paren < 0) {
                return false;
            }

            string label = text.substring (index + 1, close_bracket - index - 1);
            string url = text.substring (close_bracket + 2, close_paren - close_bracket - 2);

            output.append ("<a href=\"");
            output.append (GLib.Markup.escape_text (url, -1));
            output.append ("\">");
            output.append (render_inline (label));
            output.append ("</a>");
            index = close_paren + 1;
            return true;
        }

        private bool try_append_bold (string text, ref int index, StringBuilder output) {
            if (text.get_char (index) != '*' || index + 1 >= text.length || text.get_char (index + 1) != '*') {
                return false;
            }

            int end = text.index_of ("**", index + 2);
            if (end < 0) {
                return false;
            }

            string inner = text.substring (index + 2, end - index - 2);
            output.append ("<strong>");
            output.append (render_inline (inner));
            output.append ("</strong>");
            index = end + 2;
            return true;
        }

        private bool try_append_italic (string text, ref int index, StringBuilder output) {
            unichar marker = text.get_char (index);
            if (marker != '*' && marker != '_') {
                return false;
            }

            int end = text.index_of_char (marker, index + 1);
            while (end >= 0) {
                if (marker == '*' && end + 1 < text.length && text.get_char (end + 1) == '*') {
                    end = text.index_of_char (marker, end + 1);
                    continue;
                }

                string inner = text.substring (index + 1, end - index - 1);
                output.append ("<em>");
                output.append (render_inline (inner));
                output.append ("</em>");
                index = end + 1;
                return true;
            }

            return false;
        }

    }
}
