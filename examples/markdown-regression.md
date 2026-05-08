# amprev Markdown Regression

## Thematic Break

Before

---

***

___

After

## Headings

# Heading 1

## Heading 2

### Heading 3

## Text Styles

This is **bold**.

This is *italic*.

This is `inline code`.

This is ~~strikethrough~~.

## Lists

- Unordered item one
- Unordered item two

1. Ordered item one
2. Ordered item two

## Task List (GFM)

- [ ] Pending item
- [x] Completed item

## Blockquote

> This is a simple blockquote.
>
> > Nested blockquote level 2.

## Code Block

```c
#include <stdio.h>

int main (void) {
    puts ("hello from amprev");
    return 0;
}
```

## Basic Table

| Feature | Status |
| --- | --- |
| Thematic breaks | Supported |
| Tables | Supported |

## Aligned Table

| Left | Center | Right |
| :--- | :---: | ---: |
| alpha | beta | gamma |
| left | center | right |

## Links

This is a [simple link](https://example.com).

## Autolink Literals (GFM)

https://example.com/docs

contact@example.com

## Badge

![badge](https://img.shields.io/badge/amprev-gfm-success)

## Image

![sample image](https://picsum.photos/640/220)

## HTML Align Block

<div align="center">
  <img src="https://img.shields.io/badge/centered-html-blue" alt="centered badge">
</div>

## Details / Summary

<details>
  <summary>Show more</summary>
  <p>Inline HTML content should render.</p>
</details>
