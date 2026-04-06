@def title = "Page Refactor Notes"
@def published = Date(2026, 4, 6)
@def tags = ["franklin", "meta"]
@def rss = "Notes on the visual language refactor for my webpage."

{{post_header}}

I returned to tinkering around this webpage recently. My fight was about making the visual style slightly more distinctive, while simultaneously keeping the page static, lightweight and close to bare Franklin.

### The visual language

All pages now share three layout primitives:

- **dark-zone** — a dark, slightly bordered block for hero content and headers.
- **accent-card** — a left-bordered card on a light background.
- **compact-rows** — a tight two-column label/value grid.

### Franklin compliance: ~~~fences~~~

Franklin does not pass bare `<div>` blocks through in `.md` files — they get HTML-escaped into visible text.
The fix is to wrap every raw HTML block in `~~~...~~~` fences:

```html
~~~
<div class="dark-zone">...</div>
~~~
```

Initially I missed this on several pages. Honestly, I would prefer to stick to bare Markdown, but some of the new features were simpler to write in HTML.

### RSS and tag links

Two things that were configured but not wired up.

**RSS.** `generate_rss = true` in `config.md` means Franklin builds `/feed.xml` automatically.
I never wired it up because I never used it myself, but apparently all I lacked was one line in `_layout/head.html`:

```html
<link rel="alternate" type="application/rss+xml"
      title="{{fill website_title}}" href="/feed.xml">
```

**Tag pages.** Franklin generates a static page for every tag at `/tag/<slug>/`.
The tag pills on blog cards were plain `<span>` elements — decorative only.
Changed them to `<a href="/tag/<slug>/">`, so they actually go somewhere now.

### Notes to self

The blog engine still has no pagination and no search, but that's fine for the current stage.

{{blog_nav}}
