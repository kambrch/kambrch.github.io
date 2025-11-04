@def title = "How the Blog Engine Works"
@def published = Date(2025, 11, 4)
@def tags = ["franklin", "meta"]
@def rss = "Implementation notes on the Franklin helpers that drive the blog index and navigation."

## How the Blog Engine Works

Wrapped up the first iteration of a lightweight blog engine inside this Franklin.jl site.
Leaving notes here so I remember how it’s wired together when I inevitably forget six months from now.

### Folder layout

All posts live in `blog/` as plain Markdown files.
Franklin turns each filename into a `/blog/<slug>/` URL. The *slug* is just the filename minus the `.md`.
Example: `2025-11-04-my-first-post.md` → `/blog/2025-11-04-my-first-post/`.
Straightforward and easy to manage with grep or shell scripts.

### Front matter

Each post carries minimal metadata so the macros know what to do:

```julia
@def title = "First Post"
@def published = Date(2025, 11, 4)
@def tags = ["blog", "personal"]
```

`published` drives the timeline and defaults to the ISO date if missing.
`tags` are for filtering on the index page.

### Index generation

The index page (`menu3.md`) calls `{{blog_index}}`. Behind that:

1. `compute_blog_posts()` walks the `blog/` folder and grabs metadata via `pagevar`.
2. It caches the results as a vector of named tuples, sorted by date.
3. `hfun_blog_index` renders article cards (title, date, snippet, tags).
4. A short JS snippet toggles cards by tag.

No databases, no build chain—just Franklin and a few helper functions.

### Navigation

I wrote a small `{{blog_nav}}` macro, that expands into `< Previous | All posts | Next >` for quick post-to-post navigation.

The macro looks up the current post’s identifiers (slug, path, URL) in the cached list, so it keeps working even if Franklin adjusts URLs or folders move.

### Notes to self

Keep the setup minimal. Markdown in, static HTML out.
If the blog ever grows, consider adding pagination or RSS, but not yet. The current setup is small, predictable, and completely under control.

{{blog_nav}}
