using Dates

function hfun_bar(vname)
  val = Meta.parse(vname[1])
  return round(sqrt(val), digits=2)
end

function hfun_m1fill(vname)
  var = vname[1]
  return pagevar("index", var)
end

function lx_baz(com, _)
  # keep this first line
  brace_content = Franklin.content(com.braces[1]) # input string
  # do whatever you want here
  return uppercase(brace_content)
end


# Macro for images:

@eval Franklin begin
  function hfun_img(args)
    path  = args[1]
    alt   = length(args) ≥ 2 ? args[2] : ""
    width = length(args) ≥ 3 ? args[3] : ""
    align = length(args) ≥ 4 ? args[4] : "center"
    class = length(args) ≥ 5 ? args[5] : ""
    class = occursin("framed", class) ? replace(class, "bordered" => "") : class


    resolved = "/" * path

    align_style = align == "left"  ? "float:left;" :
                  align == "right" ? "float:right;" :
                                     "display:block; margin-left:auto; margin-right:auto;"

    return """
    <div class="framed" style="$(align_style)">
      <img src="$(resolved)" alt="$(alt)"
           class="$(class)"
           style="width:$(width); max-width:100%; height:auto;">
    </div>
    """
  end
end

const BlogPostTuple = NamedTuple{
  (:slug, :rpath, :url, :title, :date, :tags, :snippet),
  Tuple{String, String, String, String, Date, Vector{String}, String}
}

const PROJECT_ROOT = dirname(@__FILE__)

slugify_tag(tag::AbstractString) = begin
  lowered = lowercase(strip(String(tag)))
  slug = replace(lowered, r"[^a-z0-9]+" => "-")
  slug = replace(slug, r"^-+" => "")
  slug = replace(slug, r"-+$" => "")
  return isempty(slug) ? lowered : slug
end

html_escape(s::AbstractString) = begin
  escaped = replace(s, "&" => "&amp;")
  escaped = replace(escaped, "<" => "&lt;")
  escaped = replace(escaped, ">" => "&gt;")
  escaped = replace(escaped, "\"" => "&quot;")
  return replace(escaped, "'" => "&#39;")
end

function normalize_identifier(value::AbstractString)
  clean = strip(String(value))
  isempty(clean) && return ""
  clean = replace(clean, r"\.(md|html)$" => "")
  clean = strip(clean, '/')
  clean = replace(clean, r"/index$" => "")
  clean = strip(clean, '/')
  clean == "index" && return ""
  return clean
end

function add_identifier!(store::Vector{String}, seen::Set{String}, value::AbstractString)
  candidate = strip(String(value))
  isempty(candidate) && return
  if !(candidate in seen)
    push!(store, candidate)
    push!(seen, candidate)
  end
end

function gather_identifiers(values::Vector{String})
  result = String[]
  seen = Set{String}()
  for raw in values
    add_identifier!(result, seen, raw)
    normalized = normalize_identifier(raw)
    !isempty(normalized) && add_identifier!(result, seen, normalized)
    if !isempty(normalized)
      parts = split(normalized, '/')
      tail = parts[end]
      add_identifier!(result, seen, tail)
    end
  end
  return result
end

function normalize_tags(raw_tags)
  if raw_tags isa AbstractVector
    cleaned = String[]
    for tag in raw_tags
      value = strip(String(tag))
      isempty(value) && continue
      push!(cleaned, value)
    end
    return cleaned
  elseif raw_tags isa AbstractString
    cleaned = String[]
    for part in split(raw_tags, ',')
      value = strip(part)
      isempty(value) && continue
      push!(cleaned, String(value))
    end
    return cleaned
  end
  return String[]
end

function parse_post_date(date_val, slug, filepath)
  if date_val isa Date
    return date_val
  elseif date_val isa AbstractString && !isempty(strip(date_val))
    try
      return Date(date_val)
    catch
    end
  elseif date_val isa Tuple && length(date_val) == 3
    try
      return Date(date_val...)
    catch
    end
  end
  if (m = match(r"^(\d{4})-(\d{2})-(\d{2})", slug)) !== nothing
    y = parse(Int, m.captures[1])
    mth = parse(Int, m.captures[2])
    d = parse(Int, m.captures[3])
    return Date(y, mth, d)
  end
  statinfo = stat(filepath)
  return Date(Dates.unix2datetime(statinfo.mtime))
end

function extract_post_snippet(filepath)
  content = read(filepath, String)
  snippet_lines = String[]
  for line in split(content, '\n')
    stripped = strip(line)
    isempty(stripped) && !isempty(snippet_lines) && break
    startswith(stripped, "@def") && continue
    startswith(stripped, "#") && !isempty(snippet_lines) && break
    startswith(stripped, "#") && isempty(snippet_lines) && continue
    push!(snippet_lines, stripped)
    !isempty(snippet_lines) && isempty(stripped) && break
    length(snippet_lines) ≥ 2 && break
  end
  snippet = strip(join(snippet_lines, " "))
  return snippet
end

function compute_blog_posts()
  blog_dir = joinpath(PROJECT_ROOT, "blog")
  isdir(blog_dir) || return BlogPostTuple[]
  posts = BlogPostTuple[]
  for entry in sort(readdir(blog_dir))
    endswith(entry, ".md") || continue
    slug = replace(entry, r"\.md$" => "")
    rpath = "blog/" * slug
    filepath = joinpath(blog_dir, entry)
    raw_title = pagevar(rpath, :title)
    title = if raw_title isa AbstractString && !isempty(strip(raw_title))
      String(raw_title)
    else
      words = split(replace(slug, '-' => ' '))
      join(uppercasefirst.(words), " ")
    end
    tags = normalize_tags(pagevar(rpath, :tags))
    date_val = pagevar(rpath, :published)
    if isnothing(date_val)
      date_val = pagevar(rpath, :date)
    end
    date = parse_post_date(date_val, slug, filepath)
    snippet = extract_post_snippet(filepath)
    url = "/" * rpath * "/"
    push!(posts, (; slug, rpath, url, title, date, tags, snippet))
  end
  sort!(posts, by = p -> p.date)
  return posts
end

function blog_posts(; ascending::Bool=true)
  posts = compute_blog_posts()
  return ascending ? posts : reverse(posts)
end

function all_blog_tags()
  tags = Set{String}()
  for post in blog_posts()
    foreach(tag -> push!(tags, tag), post.tags)
  end
  return sort(collect(tags))
end

"""
    hfun_blog_index()

Render the blog index with optional tag filters. Use as `{{blog_index}}`.
"""
function hfun_blog_index(_=nothing)
  posts = blog_posts(ascending=false)
  isempty(posts) && return "<p class=\"blog-empty\">No posts yet.</p>"
  tags = all_blog_tags()
  io = IOBuffer()
  if !isempty(tags)
    write(io, "<div class=\"blog-filters\">")
    write(
      io,
      "<button class=\"blog-filter__btn is-active\" data-filter=\"all\">All</button>",
    )
    for tag in tags
      tag_slug = slugify_tag(tag)
      write(
        io,
        "<button class=\"blog-filter__btn\" data-filter=\"$(html_escape(tag_slug))\">" *
        "$(html_escape(tag))</button>",
      )
    end
    write(io, "</div>")
  end
  write(io, "<div class=\"blog-list\">")
  for post in posts
    tag_slug_list = join(slugify_tag.(post.tags), " ")
    date_iso = Dates.format(post.date, dateformat"yyyy-mm-dd")
    date_display = Dates.format(post.date, dateformat"u d, yyyy")
    write(
      io,
      "<article class=\"blog-card\" data-tags=\"$(html_escape(tag_slug_list))\">",
    )
    write(
      io,
      "<div class=\"blog-card__meta\"><time datetime=\"$date_iso\">$date_display" *
      "</time></div>",
    )
    write(
      io,
      "<h2 class=\"blog-card__title\"><a href=\"$(html_escape(post.url))\">" *
      "$(html_escape(post.title))</a></h2>",
    )
    if !isempty(post.snippet)
      write(
        io,
        "<p class=\"blog-card__snippet\">$(html_escape(post.snippet))</p>",
      )
    end
    if !isempty(post.tags)
      chips = join(
        ["<span class=\"blog-card__tag\">$(html_escape(tag))</span>" for tag in post.tags],
        " ",
      )
      write(io, "<div class=\"blog-card__tags\">$chips</div>")
    end
    write(io, "</article>")
  end
  write(io, "</div>")
  write(io, """
<script>
document.addEventListener("DOMContentLoaded", function () {
  const buttons = Array.from(document.querySelectorAll(".blog-filter__btn"));
  const cards = Array.from(document.querySelectorAll(".blog-card"));
  if (buttons.length === 0 || cards.length === 0) {
    return;
  }
  function applyFilter(target) {
    cards.forEach(function (card) {
      if (target === "all") {
        card.classList.remove("is-hidden");
        return;
      }
      var tags = (card.dataset.tags || "").split(/\\s+/).filter(Boolean);
      if (tags.includes(target)) {
        card.classList.remove("is-hidden");
      } else {
        card.classList.add("is-hidden");
      }
    });
  }
  buttons.forEach(function (button) {
    button.addEventListener("click", function () {
      buttons.forEach(function (btn) {
        btn.classList.remove("is-active");
      });
      button.classList.add("is-active");
      applyFilter(button.dataset.filter);
    });
  });
});
</script>
""")
  return String(take!(io))
end

"""
    hfun_blog_nav()

Render previous/next navigation for a blog post. Use as `{{blog_nav}}`.
"""
function hfun_blog_nav(_=nothing)
  rpath_val = Franklin.locvar(:fd_rpath)
  rpath_val isa AbstractString || return ""
  rpath = String(rpath_val)
  slug_val = Franklin.locvar(:slug)
  slug_candidate = slug_val isa AbstractString ? strip(String(slug_val)) : ""
  path_identifier = normalize_identifier(rpath)
  url_val = Franklin.locvar(:fd_url)
  url_candidate = url_val isa AbstractString ? strip(String(url_val)) : ""
  values = String[rpath]
  if !isempty(slug_candidate)
    push!(values, slug_candidate)
  end
  if !isempty(path_identifier) && path_identifier != rpath
    push!(values, path_identifier)
  end
  if !isempty(url_candidate)
    push!(values, url_candidate)
  end
  candidates = gather_identifiers(values)
  candidate_set = Set(candidates)
  posts = blog_posts()
  isempty(posts) && return ""
  idx = nothing
  for (i, post) in enumerate(posts)
    post_values = String[post.slug, post.rpath, post.url]
    post_ids = gather_identifiers(post_values)
    if any(id -> id in candidate_set, post_ids)
      idx = i
      break
    end
  end
  if idx === nothing && !isempty(candidates)
    fallback = candidates[end]
    idx = findfirst(
      post -> begin
        post_values = String[post.slug, post.rpath, post.url]
        fallback in gather_identifiers(post_values)
      end,
      posts,
    )
  end
  prev_post = idx !== nothing && idx > 1 ? posts[idx - 1] : nothing
  next_post = idx !== nothing && idx < length(posts) ? posts[idx + 1] : nothing
  back_url_raw = pagevar("menu3", :fd_url)
  back_href = "/menu3/"
  if back_url_raw isa AbstractString
    cleaned = strip(String(back_url_raw))
    cleaned = replace(cleaned, r"index\.html$" => "")
    cleaned = strip(cleaned, '/')
    back_href = "/" * cleaned * "/"
    if isempty(cleaned)
      back_href = "/"
    end
  end
  back_label = "All posts"
  io = IOBuffer()
  write(io, "<div class=\"blog-nav\">")
  if prev_post !== nothing
    prev_label = "&lt; " * html_escape(prev_post.title)
    write(
      io,
      "<a class=\"blog-nav__item\" href=\"$(html_escape(prev_post.url))\">$prev_label</a>",
    )
  else
    write(io, "<span class=\"blog-nav__item is-disabled\">Start</span>")
  end
  write(io, "<span class=\"blog-nav__sep\">|</span>")
  write(
    io,
    "<a class=\"blog-nav__item\" href=\"$(html_escape(back_href))\">" *
    "$(html_escape(back_label))</a>",
  )
  write(io, "<span class=\"blog-nav__sep\">|</span>")
  if next_post !== nothing
    next_label = html_escape(next_post.title) * " &gt;"
    write(
      io,
      "<a class=\"blog-nav__item\" href=\"$(html_escape(next_post.url))\">$next_label</a>",
    )
  else
    write(io, "<span class=\"blog-nav__item is-disabled\">End</span>")
  end
  write(io, "</div>")
  return String(take!(io))
end
