/*
 * SPDX-FileCopyrightText: 2026 Iuri Suzano <iuri@astware.bar>
 * SPDX-License-Identifier: MIT
 */

#include "internal/markdown_gfm.h"

#include <glib.h>

#ifdef HAVE_CMARK_GFM
#include <cmark-gfm-core-extensions.h>
#include <cmark-gfm.h>
#endif

char *
amprev_markdown_gfm_render(const char *markdown)
{
#ifdef HAVE_CMARK_GFM
    const char *input = markdown != NULL ? markdown : "";
    cmark_parser *parser = cmark_parser_new(CMARK_OPT_DEFAULT);
    cmark_node *document;
    char *html;

    if (parser == NULL) {
        return NULL;
    }

    cmark_gfm_core_extensions_ensure_registered();

    {
        const char *extensions[] = {
            "table",
            "strikethrough",
            "autolink",
            "tasklist",
        };
        gsize i;

        for (i = 0; i < G_N_ELEMENTS(extensions); i++) {
            cmark_syntax_extension *extension = cmark_find_syntax_extension(extensions[i]);
            if (extension != NULL) {
                cmark_parser_attach_syntax_extension(parser, extension);
            }
        }
    }

    cmark_parser_feed(parser, input, strlen(input));
    document = cmark_parser_finish(parser);
    cmark_parser_free(parser);

    if (document == NULL) {
        return NULL;
    }

    html = cmark_render_html(document, CMARK_OPT_DEFAULT, NULL);
    cmark_node_free(document);

    if (html == NULL) {
        return NULL;
    }

    return html;
#else
    (void) markdown;
    return NULL;
#endif
}
