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
        private string app_css;
        private string github_css;
        private static string? chroma_path = null;
        private static bool chroma_checked = false;
#if HAVE_CMARK_GFM
        [CCode (cname = "amprev_markdown_gfm_render", cheader_filename = "internal/markdown_gfm.h")]
        private static extern string? render_with_gfm_backend (string markdown);
#endif

        public MarkdownEngine (string app_css, string github_css) {
            this.app_css = app_css;
            this.github_css = github_css;
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

        private string build_page (string markdown) {
            string body = render_markdown_best_effort (markdown ?? "");
            string html = "<!doctype html>\n"
                + "<html>\n"
                + "<head>\n"
                + "  <meta charset=\"utf-8\">\n"
                + "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
                + "  <style>" + build_styles () + "</style>\n"
                + "</head>\n"
                + "<body class=\"markdown-body\">\n"
                + body + "\n"
                + "</body>\n"
                + "</html>\n";
            string final_html = syntax_highlight_postprocess (html);
            return final_html;
        }

        private string build_styles () {
            return github_css + "\n" + app_css;
        }

        private string syntax_highlight_postprocess (string html) {
            string? path = chroma_program_path ();
            if (path == null) {
                return html;
            }

            try {
                var regex = new Regex ("(?s)<pre><code(?: class=\"language-([^\"]+)\")?>(.*?)</code></pre>");
                MatchInfo match_info;
                if (!regex.match (html, 0, out match_info)) {
                    return html;
                }

                var output = new StringBuilder ();
                int last_end = 0;
                do {
                    int start_pos;
                    int end_pos;
                    match_info.fetch_pos (0, out start_pos, out end_pos);
                    output.append (html.substring (last_end, start_pos - last_end));

                    string? language = match_info.fetch (1);
                    string? escaped_code = match_info.fetch (2);
                    output.append (highlight_code_block (
                        language != null ? language : "",
                        escaped_code != null ? escaped_code : ""
                    ));

                    last_end = end_pos;
                } while (match_info.next ());

                output.append (html.substring (last_end));
                return output.str;
            } catch (Error error) {
                warning ("syntax highlight postprocess failed: %s", error.message);
                return html;
            }
        }

        private string highlight_code_block (string language, string escaped_code) {
            string raw_code = unescape_html_entities (escaped_code);
            string? highlighted = run_chroma (language, raw_code);
            if (highlighted != null && highlighted.length > 0) {
                return highlighted;
            }

            string class_attr = "";
            if (language.length > 0) {
                class_attr = " class=\"language-" + GLib.Markup.escape_text (language, -1) + "\"";
            }

            return "<pre><code" + class_attr + ">" + GLib.Markup.escape_text (raw_code, -1) + "</code></pre>";
        }

        private string unescape_html_entities (string text) {
            string unescaped = text;
            unescaped = unescaped.replace ("&lt;", "<");
            unescaped = unescaped.replace ("&gt;", ">");
            unescaped = unescaped.replace ("&amp;", "&");
            unescaped = unescaped.replace ("&quot;", "\"");
            unescaped = unescaped.replace ("&apos;", "'");
            unescaped = unescaped.replace ("&#39;", "'");
            unescaped = unescaped.replace ("&#x27;", "'");
            return unescaped;
        }

        private string? run_chroma (string language, string code) {
            string? path = chroma_program_path ();
            if (path == null || language.length == 0) {
                return null;
            }

            string lexer = chroma_lexer_for (language);
            try {
                var subprocess = new Subprocess (
                    SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
                    ,
                    path,
                    "--lexer",
                    lexer,
                    "--html",
                    "--html-only",
                    "--style",
                    "vulcan",
                    "--fail"
                );

                string? stdout_text;
                string? stderr_text;
                bool ok = subprocess.communicate_utf8 (code, null, out stdout_text, out stderr_text);
                if (!ok) {
                    return null;
                }

                if (stdout_text == null || stdout_text.length == 0) {
                    return null;
                }

                return stdout_text;
            } catch (Error error) {
                warning ("chroma execution failed: %s", error.message);
                return null;
            }
        }

        private string chroma_lexer_for (string language) {
            string lexer = language.strip ().down ();
            switch (lexer) {
            case "vala":
                return "csharp";
            default:
                return lexer;
            }
        }

        private string? chroma_program_path () {
            if (chroma_checked) {
                return chroma_path;
            }

            chroma_checked = true;
            chroma_path = GLib.Environment.find_program_in_path ("chroma");
            if (chroma_path == null) {
                string[] candidates = {
                    "/usr/bin/chroma",
                    "/usr/local/bin/chroma",
                };

                foreach (string candidate in candidates) {
                    if (GLib.FileUtils.test (candidate, GLib.FileTest.EXISTS | GLib.FileTest.IS_EXECUTABLE)) {
                        chroma_path = candidate;
                        break;
                    }
                }
            }
            return chroma_path;
        }

        private string render_markdown_best_effort (string markdown) {
#if HAVE_CMARK_GFM
            string? rendered = render_with_gfm_backend (markdown);
            if (rendered != null) {
                return rendered;
            }
#endif
            return render_markdown (markdown);
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

                if (is_thematic_break (trimmed)) {
                    output.append ("<hr>\n");
                    index++;
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

                if (is_table_block_start (lines, index)) {
                    index = append_table_block (lines, index, output);
                    continue;
                }

                if (is_raw_html_block_start (trimmed)) {
                    index = append_raw_html_block (lines, index, output);
                    continue;
                }

                index = append_paragraph (lines, index, output);
            }

            return output.str;
        }

        private int append_code_block (string[] lines, int start_index, StringBuilder output) {
            var code = new StringBuilder ();
            string info = lines[start_index].strip ();
            string language_class = "";
            int index = start_index + 1;

            if (info.length > 3) {
                string fence_info = info.substring (3, -1).strip ();
                if (fence_info.length > 0) {
                    string[] parts = fence_info.split (" ");
                    string language = parts[0].strip ().down ();
                    if (language.length > 0) {
                        language_class = " class=\"language-" + GLib.Markup.escape_text (language, -1) + "\"";
                    }
                }
            }
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

            output.append ("<pre><code");
            output.append (language_class);
            output.append (">");
            output.append (GLib.Markup.escape_text (code.str, -1));
            output.append ("</code></pre>\n");

            return (index < lines.length) ? index + 1 : index;
        }

        private int append_blockquote (string[] lines, int start_index, StringBuilder output) {
            int index = start_index;
            int current_level = 0;

            while (index < lines.length) {
                string trimmed = lines[index].strip ();
                if (!is_blockquote (trimmed)) {
                    break;
                }

                int level = blockquote_level (trimmed);
                while (current_level < level) {
                    output.append ("<blockquote>\n");
                    current_level++;
                }
                while (current_level > level) {
                    output.append ("</blockquote>\n");
                    current_level--;
                }

                string content = strip_blockquote_prefix (trimmed, level);
                output.append ("<p>");
                output.append (render_inline (content));
                output.append ("</p>\n");
                index++;
            }

            while (current_level > 0) {
                output.append ("</blockquote>\n");
                current_level--;
            }

            return index;
        }

        private int blockquote_level (string trimmed) {
            int level = 0;
            int index = 0;
            while (index < trimmed.length && trimmed.get_char (index) == '>') {
                level++;
                index++;
                if (index < trimmed.length && trimmed.get_char (index) == ' ') {
                    index++;
                }
            }

            return level > 0 ? level : 1;
        }

        private string strip_blockquote_prefix (string trimmed, int level) {
            int removed = 0;
            int index = 0;
            while (index < trimmed.length && removed < level) {
                if (trimmed.get_char (index) == '>') {
                    removed++;
                    index++;
                    if (index < trimmed.length && trimmed.get_char (index) == ' ') {
                        index++;
                    }
                    continue;
                }
                break;
            }

            return trimmed.substring (index, -1).strip ();
        }

        private int append_list_block (string[] lines, int start_index, StringBuilder output) {
            string first = lines[start_index].strip ();
            bool ordered = is_ordered_list_item (first);
            bool is_task_list = !ordered;
            output.append (ordered ? "<ol>\n" : "<ul");
            if (is_task_list) {
                output.append (" class=\"contains-task-list\"");
            }
            output.append (">\n");

            int index = start_index;
            while (index < lines.length) {
                string trimmed = lines[index].strip ();
                bool matches = ordered ? is_ordered_list_item (trimmed) : is_unordered_list_item (trimmed);
                if (!matches) {
                    break;
                }

                string item = ordered ? strip_ordered_prefix (trimmed) : strip_unordered_prefix (trimmed);
                bool task_checked;
                string? task_text = task_item_content (item, out task_checked);

                if (task_text != null) {
                    output.append ("<li class=\"task-list-item\"><input type=\"checkbox\" disabled");
                    if (task_checked) {
                        output.append (" checked");
                    }
                    output.append ("> ");
                    output.append (render_inline (task_text));
                } else {
                    output.append ("<li>");
                    output.append (render_inline (item));
                }
                output.append ("</li>\n");
                index++;
            }

            output.append (ordered ? "</ol>\n" : "</ul>\n");
            return index;
        }

        private string? task_item_content (string item, out bool checked) {
            checked = false;
            string trimmed = item.strip ();
            if (trimmed.length < 4 || trimmed.get_char (0) != '[' || trimmed.get_char (2) != ']') {
                return null;
            }

            unichar marker = trimmed.get_char (1);
            if (marker == ' ') {
                checked = false;
            } else if (marker == 'x' || marker == 'X') {
                checked = true;
            } else {
                return null;
            }

            if (trimmed.length > 3 && trimmed.get_char (3) != ' ') {
                return null;
            }

            return trimmed.length > 4 ? trimmed.substring (4, -1) : "";
        }

        private int append_paragraph (string[] lines, int start_index, StringBuilder output) {
            var paragraph = new StringBuilder ();
            int index = start_index;

            while (index < lines.length) {
                string trimmed = lines[index].strip ();
                if (trimmed.length == 0 || is_block_start_at (lines, index)) {
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
                || is_thematic_break (trimmed)
                || is_heading (trimmed, out level)
                || is_blockquote (trimmed)
                || is_list_item (trimmed)
                || is_raw_html_block_start (trimmed);
        }

        private bool is_block_start_at (string[] lines, int index) {
            string trimmed = lines[index].strip ();
            return is_block_start (trimmed) || is_table_block_start (lines, index);
        }

        private bool is_code_fence (string trimmed) {
            return trimmed.has_prefix ("```");
        }

        private bool is_thematic_break (string trimmed) {
            if (trimmed.length < 3) {
                return false;
            }

            unichar marker = trimmed.get_char (0);
            if (marker != '-' && marker != '*' && marker != '_') {
                return false;
            }

            int marker_count = 0;
            for (int index = 0; index < trimmed.length; index++) {
                unichar ch = trimmed.get_char (index);
                if (ch == marker) {
                    marker_count++;
                    continue;
                }

                if (ch == ' ') {
                    continue;
                }

                return false;
            }

            return marker_count >= 3;
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

        private bool is_raw_html_block_start (string trimmed) {
            return sanitize_raw_html_tag (trimmed) != null;
        }

        private bool is_table_block_start (string[] lines, int index) {
            if (index + 1 >= lines.length) {
                return false;
            }

            string header = lines[index].strip ();
            string delimiter = lines[index + 1].strip ();

            if (header.length == 0 || delimiter.length == 0) {
                return false;
            }

            return is_table_row (header) && is_table_delimiter_row (delimiter);
        }

        private bool is_table_row (string trimmed) {
            return trimmed.index_of_char ('|') >= 0;
        }

        private bool is_table_delimiter_row (string trimmed) {
            string[] cells = split_table_cells (trimmed);
            if (cells.length == 0) {
                return false;
            }

            foreach (string cell in cells) {
                string delimiter = cell.strip ();
                if (!is_valid_table_delimiter (delimiter)) {
                    return false;
                }
            }

            return true;
        }

        private bool is_valid_table_delimiter (string delimiter) {
            if (delimiter.length < 3) {
                return false;
            }

            int start = 0;
            int end = delimiter.length;

            if (delimiter.has_prefix (":")) {
                start++;
            }

            if (delimiter.has_suffix (":")) {
                end--;
            }

            if ((end - start) < 3) {
                return false;
            }

            for (int index = start; index < end; index++) {
                if (delimiter.get_char (index) != '-') {
                    return false;
                }
            }

            return true;
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

        private string[] split_table_cells (string line) {
            string[] raw = line.split ("|");
            string[] cells = {};
            bool leading_pipe = line.has_prefix ("|");
            bool trailing_pipe = line.has_suffix ("|");

            for (int index = 0; index < raw.length; index++) {
                bool skip_leading = leading_pipe && index == 0;
                bool skip_trailing = trailing_pipe && index == raw.length - 1;
                if (skip_leading || skip_trailing) {
                    continue;
                }

                cells += raw[index];
            }

            return cells;
        }

        private int append_table_block (string[] lines, int start_index, StringBuilder output) {
            string[] header_cells = split_table_cells (lines[start_index].strip ());
            string[] delimiter_cells = split_table_cells (lines[start_index + 1].strip ());
            int index = start_index + 2;

            output.append ("<table>\n");
            output.append ("<thead>\n<tr>\n");
            append_table_row (output, "th", header_cells, delimiter_cells);
            output.append ("</tr>\n</thead>\n");

            output.append ("<tbody>\n");
            while (index < lines.length) {
                string trimmed = lines[index].strip ();
                if (trimmed.length == 0 || !is_table_row (trimmed)) {
                    break;
                }

                string[] body_cells = split_table_cells (trimmed);
                output.append ("<tr>\n");
                append_table_row (output, "td", body_cells, delimiter_cells);
                output.append ("</tr>\n");
                index++;
            }
            output.append ("</tbody>\n</table>\n");

            return index;
        }

        private void append_table_row (
            StringBuilder output,
            string cell_tag,
            string[] cells,
            string[] delimiter_cells
        ) {
            int column_count = cells.length > delimiter_cells.length ? cells.length : delimiter_cells.length;
            for (int index = 0; index < column_count; index++) {
                string cell = index < cells.length ? cells[index] : "";
                string? align = index < delimiter_cells.length ? table_alignment_for_cell (delimiter_cells[index]) : null;
                output.append ("<");
                output.append (cell_tag);
                if (align != null) {
                    output.append (" style=\"text-align: ");
                    output.append (align);
                    output.append (";\"");
                }
                output.append (">");
                output.append (render_inline (cell.strip ()));
                output.append ("</");
                output.append (cell_tag);
                output.append (">\n");
            }
        }

        private string? table_alignment_for_cell (string cell) {
            string trimmed = cell.strip ();
            bool leading = trimmed.has_prefix (":");
            bool trailing = trimmed.has_suffix (":");

            if (leading && trailing) {
                return "center";
            }

            if (leading) {
                return "left";
            }

            if (trailing) {
                return "right";
            }

            return null;
        }

        private string render_inline (string text) {
            var output = new StringBuilder ();
            int index = 0;

            while (index < text.length) {
                int next = find_next_marker (text, index);
                if (next < 0) {
                    output.append (render_plain_with_autolinks (text.substring (index, -1)));
                    break;
                }

                if (next > index) {
                    output.append (render_plain_with_autolinks (text.substring (index, next - index)));
                    index = next;
                }

                if (try_append_code (text, ref index, output)) {
                    continue;
                }

                if (try_append_image (text, ref index, output)) {
                    continue;
                }

                if (try_append_link (text, ref index, output)) {
                    continue;
                }

                if (try_append_raw_html (text, ref index, output)) {
                    continue;
                }

                if (try_append_bold (text, ref index, output)) {
                    continue;
                }

                if (try_append_strikethrough (text, ref index, output)) {
                    continue;
                }

                if (try_append_italic (text, ref index, output)) {
                    continue;
                }

                output.append (render_plain_with_autolinks (text.substring (index, 1)));
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

            candidate = text.index_of_char ('~', start_index);
            next = choose_next (next, candidate);

            candidate = text.index_of_char ('!', start_index);
            next = choose_next (next, candidate);

            candidate = text.index_of_char ('<', start_index);
            next = choose_next (next, candidate);

            return next;
        }

        private string render_plain_with_autolinks (string text) {
            var output = new StringBuilder ();
            int index = 0;

            while (index < text.length) {
                int url_start;
                int url_end;
                int email_start;
                int email_end;
                find_next_autolink (text, index, out url_start, out url_end, out email_start, out email_end);

                int match_start = -1;
                int match_end = -1;
                bool is_email = false;

                if (url_start >= 0) {
                    match_start = url_start;
                    match_end = url_end;
                }

                if (email_start >= 0 && (match_start < 0 || email_start < match_start)) {
                    match_start = email_start;
                    match_end = email_end;
                    is_email = true;
                }

                if (match_start < 0) {
                    output.append (GLib.Markup.escape_text (text.substring (index, -1), -1));
                    break;
                }

                if (match_start > index) {
                    output.append (GLib.Markup.escape_text (text.substring (index, match_start - index), -1));
                }

                string literal = text.substring (match_start, match_end - match_start);
                if (is_email) {
                    output.append ("<a href=\"mailto:");
                    output.append (GLib.Markup.escape_text (literal, -1));
                    output.append ("\">");
                    output.append (GLib.Markup.escape_text (literal, -1));
                    output.append ("</a>");
                } else {
                    output.append ("<a href=\"");
                    output.append (GLib.Markup.escape_text (literal, -1));
                    output.append ("\">");
                    output.append (GLib.Markup.escape_text (literal, -1));
                    output.append ("</a>");
                }

                index = match_end;
            }

            return output.str;
        }

        private void find_next_autolink (
            string text,
            int start_index,
            out int url_start,
            out int url_end,
            out int email_start,
            out int email_end
        ) {
            url_start = -1;
            url_end = -1;
            email_start = -1;
            email_end = -1;

            try {
                var url_regex = new Regex ("https?://[^\\s<>()]+");
                MatchInfo url_match;
                if (url_regex.match_full (text, -1, start_index, 0, out url_match)) {
                    url_match.fetch_pos (0, out url_start, out url_end);
                }

                var email_regex = new Regex ("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}");
                MatchInfo email_match;
                if (email_regex.match_full (text, -1, start_index, 0, out email_match)) {
                    email_match.fetch_pos (0, out email_start, out email_end);
                }
            } catch (Error error) {
                warning ("autolink detection failed: %s", error.message);
            }
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

        private bool try_append_image (string text, ref int index, StringBuilder output) {
            if (text.get_char (index) != '!' || index + 1 >= text.length || text.get_char (index + 1) != '[') {
                return false;
            }

            int close_bracket = text.index_of_char (']', index + 2);
            if (close_bracket < 0 || close_bracket + 1 >= text.length || text.get_char (close_bracket + 1) != '(') {
                return false;
            }

            int close_paren = text.index_of_char (')', close_bracket + 2);
            if (close_paren < 0) {
                return false;
            }

            string alt = text.substring (index + 2, close_bracket - index - 2);
            string url = text.substring (close_bracket + 2, close_paren - close_bracket - 2);
            if (!is_safe_url (url)) {
                return false;
            }

            output.append ("<img src=\"");
            output.append (GLib.Markup.escape_text (url, -1));
            output.append ("\" alt=\"");
            output.append (GLib.Markup.escape_text (alt, -1));
            output.append ("\" />");
            index = close_paren + 1;
            return true;
        }

        private bool try_append_raw_html (string text, ref int index, StringBuilder output) {
            if (text.get_char (index) != '<') {
                return false;
            }

            string tail = text.substring (index, -1);
            string? safe_tag = sanitize_raw_html_tag (tail);
            if (safe_tag == null) {
                return false;
            }

            output.append (safe_tag);
            index = index + tail.index_of_char ('>') + 1;
            return true;
        }

        private int append_raw_html_block (string[] lines, int start_index, StringBuilder output) {
            int index = start_index;
            while (index < lines.length) {
                string line = lines[index];
                string trimmed = line.strip ();
                if (trimmed.length == 0) {
                    break;
                }

                string? safe_line = sanitize_raw_html_inline_fragment (trimmed);
                if (safe_line == null) {
                    safe_line = sanitize_raw_html_tag (trimmed);
                }
                if (safe_line == null) {
                    break;
                }

                string indent = line.substring (0, line.index_of (trimmed));
                output.append (indent);
                output.append (safe_line);
                output.append ("\n");
                index++;
            }

            return index;
        }

        private string? sanitize_raw_html_inline_fragment (string raw) {
            string trimmed = raw.strip ();
            try {
                var inline_regex = new Regex ("^<\\s*([A-Za-z][A-Za-z0-9]*)\\b([^>]*)>(.*)</\\s*([A-Za-z][A-Za-z0-9]*)\\s*>$");
                MatchInfo match;
                if (!inline_regex.match (trimmed, 0, out match)) {
                    return null;
                }

                string open_tag = match.fetch (1).down ();
                string attrs = match.fetch (2);
                string inner = match.fetch (3);
                string close_tag = match.fetch (4).down ();

                if (open_tag != close_tag || !is_allowed_raw_html_tag (open_tag) || is_forbidden_raw_html_tag ("<" + open_tag + ">")) {
                    return null;
                }

                string? sanitized_attrs = sanitize_raw_html_attributes (attrs);
                if (sanitized_attrs == null) {
                    return null;
                }

                var output = new StringBuilder ();
                output.append ("<");
                output.append (open_tag);
                if (sanitized_attrs.length > 0) {
                    output.append (" ");
                    output.append (sanitized_attrs);
                }
                output.append (">");
                output.append (inner);
                output.append ("</");
                output.append (close_tag);
                output.append (">");
                return output.str;
            } catch (Error error) {
                warning ("raw html inline sanitize failed: %s", error.message);
                return null;
            }
        }

        private string? sanitize_raw_html_tag (string raw) {
            string trimmed = raw.strip ();
            if (!trimmed.has_prefix ("<") || !trimmed.has_suffix (">")) {
                return null;
            }

            if (is_forbidden_raw_html_tag (trimmed)) {
                return null;
            }

            try {
                var tag_regex = new Regex ("^<\\s*(/?)\\s*([A-Za-z][A-Za-z0-9]*)\\b([^>]*)\\s*(/?)\\s*>$");
                MatchInfo tag_match;
                if (!tag_regex.match (trimmed, 0, out tag_match)) {
                    return null;
                }

                string is_closing = tag_match.fetch (1);
                string tag_name = tag_match.fetch (2).down ();
                string attrs = tag_match.fetch (3);
                string is_self_closing = tag_match.fetch (4);

                if (!is_allowed_raw_html_tag (tag_name)) {
                    return null;
                }

                if (is_closing == "/") {
                    return "</" + tag_name + ">";
                }

                if (tag_name == "br") {
                    return "<br>";
                }

                var result = new StringBuilder ();
                result.append ("<");
                result.append (tag_name);

                if (is_self_closing == "/" && attrs.has_suffix ("/")) {
                    attrs = attrs.substring (0, attrs.length - 1);
                }

                string? sanitized_attrs = sanitize_raw_html_attributes (attrs);
                if (sanitized_attrs == null) {
                    return null;
                }

                if (sanitized_attrs.length > 0) {
                    result.append (" ");
                    result.append (sanitized_attrs);
                }

                if (is_self_closing == "/" || tag_name == "img") {
                    result.append (" />");
                } else {
                    result.append (">");
                }

                return result.str;
            } catch (Error error) {
                warning ("raw html sanitize failed: %s", error.message);
                return null;
            }
        }

        private bool is_allowed_raw_html_tag (string tag_name) {
            switch (tag_name) {
            case "p":
            case "div":
            case "span":
            case "img":
            case "a":
            case "br":
            case "center":
            case "details":
            case "summary":
            case "kbd":
            case "sup":
            case "sub":
            case "small":
            case "strong":
            case "em":
            case "b":
            case "i":
            case "table":
            case "thead":
            case "tbody":
            case "tr":
            case "th":
            case "td":
                return true;
            default:
                return false;
            }
        }

        private bool is_forbidden_raw_html_tag (string trimmed) {
            string lower = trimmed.down ();
            return lower.has_prefix ("<script")
                || lower.has_prefix ("</script")
                || lower.has_prefix ("<style")
                || lower.has_prefix ("</style")
                || lower.has_prefix ("<iframe")
                || lower.has_prefix ("</iframe")
                || lower.has_prefix ("<object")
                || lower.has_prefix ("</object")
                || lower.has_prefix ("<embed")
                || lower.has_prefix ("</embed");
        }

        private string? sanitize_raw_html_attributes (string attrs) {
            string cleaned_attrs = attrs.strip ();
            if (cleaned_attrs.has_suffix ("/")) {
                cleaned_attrs = cleaned_attrs.substring (0, cleaned_attrs.length - 1).strip ();
            }
            if (cleaned_attrs.length == 0) {
                return "";
            }

            try {
                var attr_regex = new Regex ("([A-Za-z_:][A-Za-z0-9:_.-]*)(?:\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+)))?");
                MatchInfo match;
                if (!attr_regex.match (cleaned_attrs, 0, out match)) {
                    return null;
                }

                var sanitized = new StringBuilder ();
                int last_end = 0;
                do {
                    int start_pos;
                    int end_pos;
                    match.fetch_pos (0, out start_pos, out end_pos);

                    string prefix = cleaned_attrs.substring (last_end, start_pos - last_end);
                    if (prefix.strip ().length > 0) {
                        return null;
                    }

                    string attr_name = match.fetch (1).down ();
                    string attr_value = match.fetch (3);
                    if (attr_value == null || attr_value.length == 0) {
                        attr_value = match.fetch (4);
                    }
                    if (attr_value == null || attr_value.length == 0) {
                        attr_value = match.fetch (5);
                    }

                    string? emitted = sanitize_raw_html_attribute (attr_name, attr_value != null ? attr_value : "");
                    if (emitted == null) {
                        return null;
                    }

                    if (sanitized.len > 0) {
                        sanitized.append_c (' ');
                    }
                    sanitized.append (emitted);

                    last_end = end_pos;
                } while (match.next ());

                if (cleaned_attrs.substring (last_end, -1).strip ().length > 0) {
                    return null;
                }

                return sanitized.str;
            } catch (Error error) {
                warning ("raw html attribute sanitize failed: %s", error.message);
                return null;
            }
        }

        private string? sanitize_raw_html_attribute (string attr_name, string attr_value) {
            switch (attr_name) {
            case "align":
            case "alt":
            case "class":
            case "height":
            case "id":
            case "rel":
            case "target":
            case "title":
            case "width":
                return attr_name + "=\"" + GLib.Markup.escape_text (attr_value, -1) + "\"";
            case "href":
            case "src":
                if (!is_safe_url (attr_value)) {
                    return null;
                }
                return attr_name + "=\"" + GLib.Markup.escape_text (attr_value, -1) + "\"";
            default:
                return null;
            }
        }

        private bool is_safe_url (string url) {
            string lower = url.down ();
            if (lower.has_prefix ("javascript:")) {
                return false;
            }

            if (lower.has_prefix ("http://")
                || lower.has_prefix ("https://")
                || lower.has_prefix ("file://")) {
                return true;
            }

            if (url.has_prefix ("//")) {
                return true;
            }

            if (url.has_prefix ("/")
                || url.has_prefix ("./")
                || url.has_prefix ("../")
                || url.index_of (":") < 0) {
                return true;
            }

            return false;
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

        private bool try_append_strikethrough (string text, ref int index, StringBuilder output) {
            if (text.get_char (index) != '~' || index + 1 >= text.length || text.get_char (index + 1) != '~') {
                return false;
            }

            int end = text.index_of ("~~", index + 2);
            if (end < 0) {
                return false;
            }

            string inner = text.substring (index + 2, end - index - 2);
            output.append ("<del>");
            output.append (render_inline (inner));
            output.append ("</del>");
            index = end + 2;
            return true;
        }

    }
}
