# Kamash's Personal Website

This is the source code for my personal website built with [Franklin.jl](https://franklinjl.org/), a static site generator for Julia.

## Setup

To run this site locally, you'll need to have [Julia](https://julialang.org/) installed on your system.

1. Clone this repository:
   ```bash
   git clone https://github.com/kambrch/kambrch.github.io.git
   cd kambrch.github.io
   ```

2. Install the required Julia packages:
   ```bash
   julia --project=@. -e 'import Pkg; Pkg.instantiate();'
   ```

3. Install build dependencies used by Franklin optimizations (minifier):
   ```bash
   python3 -m pip install -r requirements.txt
   ```

4. Serve the site locally:
   ```bash
   julia --project=@. -e 'using Franklin; serve()'
   ```

The site will be available at `http://localhost:8000`.

## Building the Site

To build the static site for production:

```bash
julia --project=@. -e 'using Franklin; optimize()'
```

If you want code-block prerendering during optimize, also install highlight.js once:
```bash
julia --project=@. -e 'using NodeJS; run(`$(npm_cmd()) install highlight.js`)'
```

## Project Structure

- `config.md` - Global configuration and variables
- `index.md` - Main landing page
- `projects.md` - Projects page
- `cv.md` - Curriculum Vitae page
- `blog.md` - Blog index page
- `kamsoft/index.md` - Business services page
- `_layout/` - HTML templates and layouts
- `_css/` - Stylesheets
- `_assets/` - Images and other assets
- `blog/` - Individual blog posts
- `utils.jl` - Custom Julia functions for the site
- `cv_data.jl` - CV data in Julia format

## Custom Features

- CV display system with structured data
- Blog with tagging and filtering
- Responsive design
- Business services page

## Image Optimization

For optimal performance, all images should be optimized before adding them to the site:

- Resize images to the display size needed
- Use appropriate formats (WebP for photos, SVG for graphics when possible)
- Compress images using tools like ImageOptim, TinyPNG, or command-line tools like ImageMagick
- Consider lazy loading for images below the fold

Example of including an optimized image in a page:
```html
{{img assets/img/example.jpg "Alt text" "600px" "center" "rounded soft shadow framed"}}
```

Generate responsive image variants (480/800/1200 widths by default):
```bash
./scripts/optimize-images.sh
```

The `{{img ...}}` helper will automatically pick up generated `*.avif`, `*.webp`, and
same-format responsive variants when present.

## Deployment

This site is deployed to GitHub Pages via the `main` branch. The CI pipeline in `.gitlab-ci.yml` builds and deploys the site automatically.
