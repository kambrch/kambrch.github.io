module SiteUtils

using Dates
using Franklin
using Franklin: pagevar
using Base: Filesystem

export blog_posts,
  all_blog_tags,
  hfun_blog_index,
  hfun_blog_nav,
  hfun_post_header,
  hfun_canonical_url,
  hfun_schema_jsonld,
  hfun_rss_link,
  hfun_cv_metrics,
  hfun_cv_downloads,
  hfun_cv_publications,
  hfun_cv_teaching,
  hfun_cv_skills,
  hfun_cv_timeline,
  hfun_cv_employment,
  hfun_cv_education,
  hfun_cv_conferences,
  hfun_cv_anchor

const BlogPostTuple = NamedTuple{
  (
    :slug,
    :rpath,
    :url,
    :title,
    :date,
    :tags,
    :snippet,
    :word_count,
    :reading_minutes,
  ),
  Tuple{String, String, String, String, Date, Vector{String}, String, Int, Int},
}

const PROJECT_ROOT = normpath(joinpath(dirname(@__FILE__), ".."))
const BLOG_CACHE = Ref{Union{Nothing, NamedTuple{(:signature, :posts), Tuple{String, Vector{BlogPostTuple}}}}}(nothing)
const FileRecord = NamedTuple{(:entry, :filepath, :statinfo), Tuple{String, String, Filesystem.StatStruct}}

include("../data/cv_data.jl")
using .CVData

# hfun_img is injected directly into the Franklin module so that Franklin's
# template engine can resolve {{img ...}} without going through SiteUtils.
# It cannot be listed in the SiteUtils export block for the same reason.
@eval Franklin begin
  function hfun_img(args)
    _esc(s) = begin
      s = replace(String(s), "&" => "&amp;")
      s = replace(s, "<" => "&lt;")
      s = replace(s, ">" => "&gt;")
      s = replace(s, "\"" => "&quot;")
      replace(s, "'" => "&#39;")
    end
    path = args[1]
    alt = _esc(length(args) ≥ 2 ? args[2] : "")
    width = length(args) ≥ 3 ? args[3] : ""
    align = length(args) ≥ 4 ? args[4] : "center"
    class = length(args) ≥ 5 ? args[5] : ""
    class = occursin("framed", class) ? replace(class, "bordered" => "") : class
    class = _esc(class)
    # 6th arg opts an above-the-fold image out of lazy loading; lazy stays the
    # default because every current caller is below the fold.
    eager = length(args) ≥ 6 && lowercase(strip(String(args[6]))) in ("eager", "true")

    # Intrinsic pixel size of the source, read straight from the file header so
    # the <img> can reserve layout space (avoids cumulative layout shift).
    # Returns nothing when the format is unknown or the file is unreadable, in
    # which case the attributes are simply omitted.
    function _intrinsic_size(file::String)
      isfile(file) || return nothing
      try
        open(file, "r") do io
          magic = read(io, 8)
          length(magic) < 8 && return nothing
          # PNG: IHDR width/height are the 8 bytes at offset 16.
          if magic == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
            seek(io, 16)
            dims = read(io, 8)
            length(dims) < 8 && return nothing
            w = Int(dims[1]) << 24 | Int(dims[2]) << 16 | Int(dims[3]) << 8 | Int(dims[4])
            h = Int(dims[5]) << 24 | Int(dims[6]) << 16 | Int(dims[7]) << 8 | Int(dims[8])
            return (w, h)
          end
          # JPEG: walk the marker chain to the first start-of-frame segment.
          if magic[1] == 0xff && magic[2] == 0xd8
            seek(io, 2)
            while !eof(io)
              read(io, UInt8) == 0xff || continue
              marker = read(io, UInt8)
              while marker == 0xff && !eof(io)
                marker = read(io, UInt8)
              end
              # Standalone markers carry no length field.
              (marker == 0xd8 || marker == 0xd9 || (0xd0 ≤ marker ≤ 0xd7)) && continue
              eof(io) && break
              lenbytes = read(io, 2)
              length(lenbytes) < 2 && break
              seglen = Int(lenbytes[1]) << 8 | Int(lenbytes[2])
              isSOF = (0xc0 ≤ marker ≤ 0xcf) && marker ∉ (0xc4, 0xc8, 0xcc)
              if isSOF
                sof = read(io, 5)
                length(sof) < 5 && break
                h = Int(sof[2]) << 8 | Int(sof[3])
                w = Int(sof[4]) << 8 | Int(sof[5])
                return (w, h)
              end
              seglen < 2 && break
              skip(io, seglen - 2)
            end
          end
          return nothing
        end
      catch
        return nothing
      end
    end

    resolved = "/" * path

    base_path = replace(resolved, r"\.[^.]*$" => "")
    original_ext_match = match(r"\.([^.]+)$", String(path))
    original_ext = isnothing(original_ext_match) ? "jpg" : lowercase(original_ext_match.captures[1])
    source_path = startswith(String(path), "assets/") ? replace(String(path), r"^assets/" => "_assets/") : String(path)
    source_base_path = replace(source_path, r"\.[^.]*$" => "")

    widths = (480, 800, 1200)
    function responsive_srcset(ext::String)
      variants = String[]
      for w in widths
        candidate_local = "$(source_base_path)-$(w).$(ext)"
        if isfile(candidate_local)
          candidate_url = "$(base_path)-$(w).$(ext)"
          push!(variants, "$(_esc(candidate_url)) $(w)w")
        end
      end
      return join(variants, ", ")
    end

    avif_srcset = responsive_srcset("avif")
    webp_srcset = responsive_srcset("webp")
    fallback_srcset = responsive_srcset(original_ext)
    # 720px is the content column (.franklin-content max-width: 45rem in
    # _assets/css/site.css); a smaller hint makes the browser pick an
    # undersized srcset candidate and upscale it.
    sizes = "(max-width: 768px) 100vw, 720px"
    style_width = isempty(strip(String(width))) ? "" : "width:$(_esc(String(width))); "
    style_attr = "style=\"$(style_width)max-width:100%; height:auto;\""
    loading_attr = eager ? "loading=\"eager\" fetchpriority=\"high\"" : "loading=\"lazy\""

    intrinsic = _intrinsic_size(source_path)
    dimension_attr = intrinsic === nothing ? "" : "width=\"$(intrinsic[1])\" height=\"$(intrinsic[2])\""

    align_style = align == "left"  ? "float:left;" :
                  align == "right" ? "float:right;" :
                                     "display:block; margin-left:auto; margin-right:auto;"

    if !isempty(avif_srcset) || !isempty(webp_srcset)
      picture_sources = IOBuffer()
      if !isempty(avif_srcset)
        write(
          picture_sources,
          "<source srcset=\"$(avif_srcset)\" sizes=\"$(sizes)\" type=\"image/avif\">",
        )
      end
      if !isempty(webp_srcset)
        write(
          picture_sources,
          "<source srcset=\"$(webp_srcset)\" sizes=\"$(sizes)\" type=\"image/webp\">",
        )
      end
      fallback_attr = isempty(fallback_srcset) ? "" : "srcset=\"$(fallback_srcset)\" sizes=\"$(sizes)\""
      return """
      <div class="framed" style="$(align_style)">
        <picture>
          $(String(take!(picture_sources)))
          <img src="$(_esc(resolved))" alt="$(alt)"
               class="$(class)"
               $(loading_attr)
               $(dimension_attr)
               $(fallback_attr)
               $(style_attr)>
        </picture>
      </div>
      """
    else
      fallback_attr = isempty(fallback_srcset) ? "" : "srcset=\"$(fallback_srcset)\" sizes=\"$(sizes)\""
      return """
      <div class="framed" style="$(align_style)">
        <img src="$(_esc(resolved))" alt="$(alt)"
             class="$(class)"
             $(loading_attr)
             $(dimension_attr)
             $(fallback_attr)
             $(style_attr)>
      </div>
      """
    end
  end
end

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

normalize_site_url(url::AbstractString) = begin
  normalized = strip(String(url))
  normalized = replace(normalized, r"/index\.html$" => "/")
  return normalized
end

"""
    json_string_escape(s) -> String

Escape a value for use inside a JSON string literal. Also breaks up `</`, so a
value containing `</script>` cannot terminate the surrounding script element.
"""
function json_string_escape(s::AbstractString)
  out = replace(String(s), "\\" => "\\\\")
  out = replace(out, "\"" => "\\\"")
  out = replace(out, "\n" => "\\n")
  out = replace(out, "\r" => "\\r")
  out = replace(out, "\t" => "\\t")
  return replace(out, "</" => "<\\/")
end

"""
    hfun_schema_jsonld()

Emit the JSON-LD Person block as a complete `<script>` element.

This exists because Franklin does not expand `{{...}}` inside `<script>` tags:
the block previously lived inline in `_layout/head.html` and shipped literal
`{{fill author}}` placeholders to every page, so the structured data was invalid
everywhere. Building the element here keeps interpolation outside the script
context, where Franklin does resolve it.

Returns an empty string when `schema_job_title` is undefined, matching the
`{{isdef schema_job_title}}` guard the template used to carry.
"""
function hfun_schema_jsonld()
  gv(name) = begin
    value = Franklin.globvar(name)
    value isa AbstractString ? strip(value) : ""
  end

  job_title = gv("schema_job_title")
  isempty(job_title) && return ""

  # These three are authored as raw JSON literals in config.md, so they are
  # inserted verbatim rather than quoted -- but only if they actually parse as
  # JSON-ish, to avoid emitting a broken document.
  raw_json(name, fallback) = begin
    value = gv(name)
    isempty(value) && return fallback
    (startswith(value, "[") || startswith(value, "{")) ? value : fallback
  end

  io = IOBuffer()
  write(io, "<script type=\"application/ld+json\">\n")
  write(io, "{\n")
  write(io, "  \"@context\": \"https://schema.org\",\n")
  write(io, "  \"@type\": \"Person\",\n")
  write(io, "  \"name\": \"$(json_string_escape(gv("author")))\",\n")
  write(io, "  \"alternateName\": $(raw_json("schema_alternate_names_json", "[]")),\n")
  write(io, "  \"jobTitle\": \"$(json_string_escape(job_title))\",\n")
  write(io, "  \"affiliation\": $(raw_json("schema_affiliations_json", "[]")),\n")
  write(io, "  \"url\": \"$(json_string_escape(gv("schema_url")))\",\n")
  write(io, "  \"image\": \"$(json_string_escape(gv("schema_image")))\",\n")
  write(io, "  \"email\": \"$(json_string_escape(gv("schema_email")))\",\n")
  write(io, "  \"sameAs\": $(raw_json("schema_sameas_json", "[]")),\n")
  write(io, "  \"address\": {\n")
  write(io, "    \"@type\": \"PostalAddress\",\n")
  write(io, "    \"addressLocality\": \"$(json_string_escape(gv("schema_address_locality")))\",\n")
  write(io, "    \"addressCountry\": \"$(json_string_escape(gv("schema_address_country")))\"\n")
  write(io, "  }\n")
  write(io, "}\n")
  write(io, "</script>")
  return String(take!(io))
end

function hfun_canonical_url()
  page_url = Franklin.locvar(:fd_full_url)
  if page_url isa String && !isempty(strip(page_url))
    return html_escape(normalize_site_url(page_url))
  end
  site_url = Franklin.globvar("website_url")
  if site_url isa String && !isempty(strip(site_url))
    url = strip(site_url)
    return html_escape(endswith(url, "/") ? url : url * "/")
  end
  return ""
end

# Franklin fills `fd_full_url` in `write_page`, right before it queues the RSS
# item. Pages whose conversion was triggered by another page's `pagevar` call
# can reach that point with the variable still empty, which emits an empty
# `<link>` in feed.xml. Rebuild the URL from `fd_rpath` instead, which is
# always set, and keep `fd_full_url` only as a fallback.
function hfun_rss_link()
  site_url = Franklin.globvar("website_url")
  base = site_url isa String ? String(strip(site_url)) : ""
  rpath = Franklin.locvar(:fd_rpath)
  if !isempty(base) && rpath isa String && !isempty(strip(rpath))
    endswith(base, "/") || (base *= "/")
    slug = replace(strip(String(rpath), '/'), r"\.(md|html)$" => "")
    slug = replace(slug, r"(^|/)index$" => "")
    slug = strip(slug, '/')
    return html_escape(isempty(slug) ? base : base * slug * "/")
  end
  return hfun_canonical_url()
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

"""
    getfield_safe(obj, field, default)

Safely get a field from an object, returning a default value if the field doesn't exist.
"""
function getfield_safe(obj, field::Symbol, default)
  try
    return getproperty(obj, field)
  catch
    return default
  end
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

function parse_post_date(date_val, slug, statinfo)
  if date_val isa Date
    return date_val
  elseif date_val isa AbstractString && !isempty(strip(date_val))
    try
      return Date(date_val)
    catch e
      @warn "Unparseable `date` in frontmatter; falling back to the slug" slug date=date_val exception=e
    end
  elseif date_val isa Tuple && length(date_val) == 3
    try
      return Date(date_val...)
    catch e
      @warn "Invalid `date` tuple in frontmatter; falling back to the slug" slug date=date_val exception=e
    end
  end
  if (m = match(r"^(\d{4})-(\d{2})-(\d{2})", slug)) !== nothing
    try
      y = parse(Int, m.captures[1])
      mth = parse(Int, m.captures[2])
      d = parse(Int, m.captures[3])
      return Date(y, mth, d)
    catch e
      # e.g. 2026-13-40 — matches the pattern but is not a real date.
      @warn "Slug date is not a valid calendar date; falling back to file mtime" slug exception=e
    end
  end
  @warn "No usable post date; using the file's mtime, which changes on every edit" slug
  return Date(Dates.unix2datetime(statinfo.mtime))
end

function count_words(text::AbstractString)
  stripped = strip(String(text))
  isempty(stripped) && return 0
  return length(split(stripped, r"\s+", keepempty = false))
end

function extract_frontmatter_title(filepath)
  for line in eachline(filepath)
    m = match(r"^@def\s+title\s*=\s*\"(.+)\"", line)
    m !== nothing && return String(m[1])
  end
  @warn "No `@def title` found; the post will fall back to its slug" file=filepath
  return nothing
end

function extract_frontmatter_tags(filepath)
  for line in eachline(filepath)
    m = match(r"^@def\s+tags\s*=\s*\[(.+)\]", line)
    m === nothing && continue
    tags = String[]
    for part in split(m[1], ',')
      s = strip(part, [' ', '"', '\''])
      isempty(s) || push!(tags, String(s))
    end
    return tags
  end
  return String[]
end

function extract_post_summary(filepath)
  content = read(filepath, String)
  lines = split(content, '\n')
  snippet_lines = String[]
  body_tokens = String[]
  for line in lines
    stripped = strip(line)
    startswith(stripped, "@def") && continue
    startswith(stripped, "{{") && continue
    if !isempty(stripped) && !startswith(stripped, "#")
      push!(body_tokens, stripped)
    end
    if isempty(snippet_lines)
      if isempty(stripped) || startswith(stripped, "#")
        continue
      end
    elseif isempty(stripped) || startswith(stripped, "#")
      break
    end
    isempty(stripped) && continue
    push!(snippet_lines, stripped)
    length(snippet_lines) ≥ 2 && break
  end
  body_text = join(filter(token -> !isempty(token), body_tokens), " ")
  word_count = count_words(body_text)
  snippet = strip(join(snippet_lines, " "))
  return snippet, word_count
end

function compute_blog_posts()
  blog_dir = joinpath(PROJECT_ROOT, "blog")
  isdir(blog_dir) || return BlogPostTuple[]

  file_records = FileRecord[]
  signature_parts = String[]
  try
    for entry in sort(readdir(blog_dir))
      endswith(entry, ".md") || continue
      filepath = joinpath(blog_dir, entry)
      statinfo = stat(filepath)
      push!(file_records, (; entry, filepath, statinfo))
      # Filename must be part of the signature: count+mtimes alone collide when
      # a post is renamed without its mtime changing, serving a stale cache.
      push!(signature_parts, string(entry, ":", statinfo.mtime))
    end
  catch e
    @error "Error reading blog directory" exception=(e, catch_backtrace())
    return BlogPostTuple[]
  end

  signature = string(length(file_records)) * ":" * join(signature_parts, ";")
  cached = BLOG_CACHE[]
  if cached !== nothing && cached.signature == signature
    return cached.posts
  end

  posts = BlogPostTuple[]
  for record in file_records
    try
      slug = replace(record.entry, r"\.md$" => "")
      rpath = "blog/" * slug
      raw_title = pagevar(rpath, :title)
      title = if raw_title isa AbstractString && !isempty(strip(raw_title))
        String(raw_title)
      else
        something(extract_frontmatter_title(record.filepath), let
          words = split(replace(slug, '-' => ' '))
          join(uppercasefirst.(words), " ")
        end)
      end
      raw_tags = pagevar(rpath, :tags)
      tags = if raw_tags !== nothing
        normalize_tags(raw_tags)
      else
        extract_frontmatter_tags(record.filepath)
      end
      date_val = pagevar(rpath, :published)
      if isnothing(date_val)
        date_val = pagevar(rpath, :date)
      end
      date = parse_post_date(date_val, slug, record.statinfo)
      snippet, word_count = extract_post_summary(record.filepath)
      reading_minutes = word_count == 0 ? 0 : max(1, (word_count + 199) ÷ 200)
      url = "/" * rpath * "/"
      push!(
        posts,
        (
          ;
          slug,
          rpath,
          url,
          title,
          date,
          tags,
          snippet,
          word_count,
          reading_minutes,
        ),
      )
    catch e
      @error "Error processing blog post $(record.entry)" exception=(e, catch_backtrace())
      # Continue processing other posts even if one fails
      continue
    end
  end

  sort!(posts, by = p -> getfield_safe(p, :date, Date(1900, 1, 1)))
  BLOG_CACHE[] = (signature = signature, posts = posts)
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

function format_reading_time(minutes::Int)
  minutes <= 0 && return ""
  minutes == 1 && return "1 min read"
  return string(minutes, " min read")
end

format_year(date::Date) = Dates.year(date)

const MONTH_ABBR = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

month_year_label(date::Date) = string(MONTH_ABBR[Dates.month(date)], " ", Dates.year(date))

long_date_label(date::Date) =
  string(MONTH_ABBR[Dates.month(date)], " ", Dates.day(date), ", ", Dates.year(date))

function format_date_range(start_date::Date, end_date::Union{Date, Nothing})
  start_label = string(Dates.year(start_date))
  if end_date === nothing
    return start_label * " – present"
  end
  end_label = string(Dates.year(end_date))
  return start_label == end_label ? start_label : string(start_label, " – ", end_label)
end

function format_event_period(start_date::Date, end_date::Union{Date, Nothing})
  if end_date === nothing || end_date == start_date
    return month_year_label(start_date)
  end
  start_label = month_year_label(start_date)
  end_label = month_year_label(end_date)
  return string(start_label, " – ", end_label)
end

const CVTimelineEntry = NamedTuple{
  (
    :sort_key,
    :year,
    :period,
    :title,
    :subtitle,
    :location,
    :highlights,
    :tags,
    :kind,
  ),
  Tuple{Date, Int, String, String, String, String, Vector{String}, Vector{String}, String},
}

function gather_timeline_entries()
  entries = CVTimelineEntry[]
  for job in CV_EMPLOYMENT
    highlights = copy(job.highlights)
    entry_tags = copy(job.tags)
    push!(entry_tags, "career")
    push!(
      entries,
      (
        ;
        sort_key = job.start_date,
        year = format_year(job.start_date),
        period = format_date_range(job.start_date, job.end_date),
        title = job.role,
        subtitle = job.organization,
        location = job.location,
        highlights,
        tags = unique(entry_tags),
        kind = "role",
      ),
    )
  end
  for event in CV_CONFERENCES
    highlights = String[]
    !isempty(strip(event.topic)) && push!(highlights, event.topic)
    entry_tags = copy(event.tags)
    push!(entry_tags, "events")
    push!(
      entries,
      (
        ;
        sort_key = event.start_date,
        year = format_year(event.start_date),
        period = format_event_period(event.start_date, event.end_date),
        title = event.name,
        subtitle = event.role,
        location = event.location,
        highlights,
        tags = unique(entry_tags),
        kind = "event",
      ),
    )
  end
  sort!(entries, by = entry -> entry.sort_key, rev = true)
  return entries
end

function cv_timeline_tag_counts(entries)
  counts = Dict{String, Int}()
  for entry in entries
    for tag in entry.tags
      counts[tag] = get(counts, tag, 0) + 1
    end
  end
  return counts
end

function cv_teaching_years()
  teaching_roles = filter(job -> "teaching" in job.tags, CV_EMPLOYMENT)
  isempty(teaching_roles) && return 0
  min_start = minimum(job.start_date for job in teaching_roles)
  max_end = maximum(job.end_date === nothing ? Dates.today() : job.end_date for job in teaching_roles)
  return max(1, Dates.year(max_end) - Dates.year(min_start) + 1)
end

function cv_metrics()
  publications = length(CV_PUBLICATIONS)
  conferences = count(event -> "conference" in event.tags || "talk" in event.tags, CV_CONFERENCES)
  teaching_years = cv_teaching_years()
  roles = length(CV_EMPLOYMENT)
  return [
    (; label = "Publications", value = string(publications), caption = "Peer-reviewed"),
    (; label = "Conference talks", value = string(conferences), caption = "International & local"),
    (
      ;
      label = "Teaching",
      value = string(teaching_years),
      suffix = " yrs",
      caption = "Undergraduate labs",
    ),
    (; label = "Research roles", value = string(roles), caption = "Academia & industry"),
  ]
end

"""
    hfun_blog_index()

Render the blog index with optional tag filters. Use as `{{blog_index}}`.
"""
function hfun_blog_index(_=nothing)
  posts = blog_posts(ascending = false)
  isempty(posts) && return "<p class=\"blog-empty\">No posts yet.</p>"
  io = IOBuffer()
  total_posts = length(posts)
  summary_label = total_posts == 1 ? "1 post" : string(total_posts, " posts")
  latest_label = long_date_label(posts[1].date)

  # Summary line
  write(io, "<div class=\"blog-summary\">")
  write(io, "<span class=\"blog-summary__count\">$(html_escape(summary_label))</span>")
  write(io, "<span class=\"blog-summary__sep\" aria-hidden=\"true\">&bull;</span>")
  write(io, "<span class=\"blog-summary__latest\">Updated $(html_escape(latest_label))</span>")
  write(io, "</div>")

  # Tag filters
  tag_counts = Dict{String, Int}()
  for post in posts
    for tag in post.tags
      tag_counts[tag] = get(tag_counts, tag, 0) + 1
    end
  end
  tags = all_blog_tags()
  write(io, "<div class=\"blog-filters\" role=\"group\" aria-label=\"Filter posts by tag\">")
  write(
    io,
    "<button class=\"blog-filter__btn is-active\" data-filter=\"all\" " *
    "data-count=\"$(total_posts)\" aria-pressed=\"true\">" *
    "<span class=\"blog-filter__label\">All</span>" *
    "<span class=\"blog-filter__count\">$total_posts</span>" *
    "</button>",
  )
  for tag in tags
    tag_slug = slugify_tag(tag)
    count = get(tag_counts, tag, 0)
    write(
      io,
      "<button class=\"blog-filter__btn\" data-filter=\"$(html_escape(tag_slug))\" " *
      "data-count=\"$count\" aria-pressed=\"false\">" *
      "<span class=\"blog-filter__label\">$(html_escape(tag))</span>" *
      "<span class=\"blog-filter__count\">$count</span>" *
      "</button>",
    )
  end
  write(io, "</div>")

  # Post list
  write(io, "<div class=\"blog-list\">")
  for (i, post) in enumerate(posts)
    tag_slug_list = join(slugify_tag.(post.tags), " ")
    date_iso = Dates.format(post.date, dateformat"yyyy-mm-dd")
    date_display = long_date_label(post.date)
    reading_label = format_reading_time(post.reading_minutes)

    if i == 1
      # Featured (latest) post — dark zone
      write(
        io,
        "<article class=\"dark-zone blog-featured\" data-tags=\"$(html_escape(tag_slug_list))\">",
      )
      write(io, "<span class=\"blog-featured__label\">Latest</span>")
      write(
        io,
        "<a class=\"blog-featured__title\" href=\"$(html_escape(post.url))\">" *
        "$(html_escape(post.title))</a>",
      )
      if !isempty(post.snippet)
        write(io, "<p class=\"blog-featured__snippet\">$(html_escape(post.snippet))</p>")
      end
      write(io, "<div class=\"blog-featured__footer\">")
      if !isempty(post.tags)
        write(io, "<div class=\"blog-featured__tags\">")
        for tag in post.tags
          tag_slug = slugify_tag(tag)
          write(io, "<a class=\"blog-featured__tag\" href=\"/tag/$(html_escape(tag_slug))/\">$(html_escape(tag))</a>")
        end
        write(io, "</div>")
      end
      date_str = isempty(reading_label) ? date_display : "$date_display · $reading_label"
      write(io, "<span class=\"blog-featured__date\"><time datetime=\"$date_iso\">$(html_escape(date_str))</time></span>")
      write(io, "</div>")  # footer
      write(io, "</article>")
    else
      # Older posts — accent cards
      write(
        io,
        "<article class=\"accent-card blog-card\" data-tags=\"$(html_escape(tag_slug_list))\">",
      )
      meta = isempty(reading_label) ? date_display : "$date_display · $reading_label"
      write(io, "<div class=\"accent-card__meta\"><time datetime=\"$date_iso\">$(html_escape(meta))</time></div>")
      write(
        io,
        "<div class=\"accent-card__title\"><a href=\"$(html_escape(post.url))\">" *
        "$(html_escape(post.title))</a></div>",
      )
      if !isempty(post.snippet)
        write(io, "<p class=\"accent-card__snippet\">$(html_escape(post.snippet))</p>")
      end
      if !isempty(post.tags)
        write(io, "<div class=\"accent-card__tags\">")
        for tag in post.tags
          tag_slug = slugify_tag(tag)
          write(io, "<a class=\"accent-card__tag\" href=\"/tag/$(html_escape(tag_slug))/\">$(html_escape(tag))</a>")
        end
        write(io, "</div>")
      end
      write(io, "</article>")
    end
  end
  write(io, "</div>")  # blog-list

  # Filter script (unchanged)
  write(io, """
<script>
document.addEventListener("DOMContentLoaded", function () {
  const buttons = Array.from(document.querySelectorAll(".blog-filter__btn"));
  const cards = Array.from(document.querySelectorAll(".blog-list article"));
  if (buttons.length === 0 || cards.length === 0) { return; }
  function applyFilter(target) {
    cards.forEach(function (card) {
      if (target === "all") { card.classList.remove("is-hidden"); return; }
      var tags = (card.dataset.tags || "").split(/\\s+/).filter(Boolean);
      if (tags.includes(target)) { card.classList.remove("is-hidden"); }
      else { card.classList.add("is-hidden"); }
    });
  }
  function setActiveButton(activeButton) {
    buttons.forEach(function (btn) {
      var isActive = btn === activeButton;
      btn.classList.toggle("is-active", isActive);
      btn.setAttribute("aria-pressed", isActive ? "true" : "false");
    });
  }
  function activateFilter(target) {
    var button = buttons.find(function (btn) { return btn.dataset.filter === target; });
    if (!button) { return; }
    setActiveButton(button);
    applyFilter(target);
    if (target === "all") { history.replaceState(null, "", window.location.pathname); }
    else { history.replaceState(null, "", window.location.pathname + "#tag=" + target); }
  }
  buttons.forEach(function (button) {
    button.addEventListener("click", function () { activateFilter(button.dataset.filter); });
  });
  var initialTarget = "all";
  var hashMatch = window.location.hash.match(/^#tag=([\\w-]+)/);
  if (hashMatch && hashMatch[1]) { initialTarget = hashMatch[1]; }
  if (!buttons.some(function (btn) { return btn.dataset.filter === initialTarget; })) { initialTarget = "all"; }
  activateFilter(initialTarget);
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
  back_url_raw = pagevar("blog", :fd_url)
  back_href = "/blog/"
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
  write(io, "<nav class=\"blog-nav\" aria-label=\"Post navigation\">")

  write(io, "<div class=\"blog-nav__slot blog-nav__slot--prev\">")
  if prev_post !== nothing
    prev_title = html_escape(prev_post.title)
    write(
      io,
      "<a class=\"accent-card\" href=\"$(html_escape(prev_post.url))\" " *
      "aria-label=\"Previous: $prev_title\" style=\"display:flex;flex-direction:column;gap:0.2rem;\">")
    write(io, "<span class=\"blog-nav__label\">&larr; Previous</span>")
    write(io, "<span class=\"blog-nav__title\">$prev_title</span>")
    write(io, "</a>")
  else
    write(
      io,
      "<span class=\"accent-card\" style=\"opacity:0.4;cursor:default;pointer-events:none;display:flex;flex-direction:column;gap:0.2rem;\">",
    )
    write(io, "<span class=\"blog-nav__label\">&larr; Previous</span>")
    write(io, "<span class=\"blog-nav__title\">Start of archive</span>")
    write(io, "</span>")
  end
  write(io, "</div>")

  write(io, "<div class=\"blog-nav__slot blog-nav__slot--all\">")
  write(
    io,
    "<a class=\"accent-card\" href=\"$(html_escape(back_href))\" " *
    "aria-label=\"Browse all posts\" style=\"display:flex;flex-direction:column;gap:0.2rem;align-items:center;text-align:center;\">",
  )
  write(io, "<span class=\"blog-nav__label\">Archive</span>")
  write(io, "<span class=\"blog-nav__title\">All posts</span>")
  write(io, "</a>")
  write(io, "</div>")

  write(io, "<div class=\"blog-nav__slot blog-nav__slot--next\">")
  if next_post !== nothing
    next_title = html_escape(next_post.title)
    write(
      io,
      "<a class=\"accent-card\" href=\"$(html_escape(next_post.url))\" " *
      "aria-label=\"Next: $next_title\" style=\"display:flex;flex-direction:column;gap:0.2rem;align-items:flex-end;text-align:right;\">")
    write(io, "<span class=\"blog-nav__label\">Next &rarr;</span>")
    write(io, "<span class=\"blog-nav__title\">$next_title</span>")
    write(io, "</a>")
  else
    write(
      io,
      "<span class=\"accent-card\" style=\"opacity:0.4;cursor:default;pointer-events:none;display:flex;flex-direction:column;gap:0.2rem;align-items:flex-end;text-align:right;\">",
    )
    write(io, "<span class=\"blog-nav__label\">Next &rarr;</span>")
    write(io, "<span class=\"blog-nav__title\">End of archive</span>")
    write(io, "</span>")
  end
  write(io, "</div>")

  write(io, "</nav>")
  return String(take!(io))
end

"""
    hfun_post_header()

Render a dark-zone header for a blog post. Reads title, date, tags, and
reading time from the post cache. Use as `{{post_header}}` at the top of
each blog post body (after frontmatter, before prose).
"""
function hfun_post_header(_=nothing)
  rpath_val = Franklin.locvar(:fd_rpath)
  rpath_val isa AbstractString || return ""
  rpath = String(rpath_val)

  # Look up post in cache for reading_minutes
  posts = blog_posts()
  post = nothing
  path_id = normalize_identifier(rpath)
  for p in posts
    if p.rpath == rpath || p.rpath == path_id || p.slug == path_id
      post = p
      break
    end
  end

  # Fallback: read title/date/tags from Franklin page variables
  title_val = Franklin.locvar(:title)
  title = title_val isa AbstractString && !isempty(strip(title_val)) ?
    String(title_val) : (post !== nothing ? post.title : "Untitled")

  date_val = Franklin.locvar(:published)
  if isnothing(date_val)
    date_val = Franklin.locvar(:date)
  end
  date = if post !== nothing
    post.date
  elseif date_val isa Date
    date_val
  else
    nothing
  end

  tags = post !== nothing ? post.tags : normalize_tags(Franklin.locvar(:tags))
  reading_minutes = post !== nothing ? post.reading_minutes : 0

  io = IOBuffer()
  write(io, "<div class=\"post-header\">")
  write(io, "<h1 class=\"post-header__title\">$(html_escape(title))</h1>")
  write(io, "<div class=\"post-header__meta\">")
  if date !== nothing
    date_iso = Dates.format(date, dateformat"yyyy-mm-dd")
    date_display = long_date_label(date)
    write(io, "<time datetime=\"$date_iso\">$(html_escape(date_display))</time>")
  end
  reading_label = format_reading_time(reading_minutes)
  if !isempty(reading_label)
    write(io, "<span>$(html_escape(reading_label))</span>")
  end
  write(io, "</div>")  # meta
  if !isempty(tags)
    write(io, "<div class=\"post-header__tags\">")
    for tag in tags
      write(io, "<span class=\"post-header__tag\">$(html_escape(tag))</span>")
    end
    write(io, "</div>")
  end
  write(io, "</div>")  # post-header
  return String(take!(io))
end

function hfun_cv_metrics(_=nothing)
  metrics = cv_metrics()
  io = IOBuffer()
  write(io, "<div class=\"cv-metrics\" role=\"list\">")
  for metric in metrics
    suffix = get(metric, :suffix, "")
    value = html_escape(string(metric.value))
    write(io, "<div class=\"cv-metrics__item\" role=\"listitem\">")
    write(io, "<span class=\"cv-metrics__value\">$value$suffix</span>")
    write(
      io,
      "<span class=\"cv-metrics__label\">$(html_escape(metric.label))</span>",
    )
    caption = get(metric, :caption, "")
    if !isempty(caption)
      write(io, "<span class=\"cv-metrics__caption\">$(html_escape(caption))</span>")
    end
    write(io, "</div>")
  end
  write(io, "</div>")
  return String(take!(io))
end

function hfun_cv_downloads(_=nothing)
  isempty(CV_DOWNLOADS) && return ""
  io = IOBuffer()
  write(io, "<div class=\"cv-downloads\" role=\"group\" aria-label=\"Download CV\">")
  for item in CV_DOWNLOADS
    label = html_escape(item.label)
    format = html_escape(item.format)
    updated = long_date_label(item.updated)
    classes = ["cv-downloads__btn"]
    attrs = String[]
    if !item.available
      push!(classes, "is-disabled")
      push!(attrs, "tabindex=\"-1\"", "aria-disabled=\"true\"")
    else
      push!(attrs, "href=\"$(html_escape(item.href))\"")
    end
    write(
      io,
      "<a $(join(attrs, ' ')) class=\"$(join(classes, ' '))\">" *
      "<span class=\"cv-downloads__label\">$label</span>" *
      "<span class=\"cv-downloads__meta\">$format · updated $updated" *
      (item.available ? "" : " · coming soon") *
      "</span></a>",
    )
  end
  write(io, "</div>")
  return String(take!(io))
end

function hfun_cv_publications(_=nothing)
  try
    isempty(CV_PUBLICATIONS) && return "<p>No publications listed yet.</p>"
    io = IOBuffer()
    for pub in sort(CV_PUBLICATIONS, by = p -> getfield_safe(p, :year, 0), rev = true)
      title = html_escape(getfield_safe(pub, :title, "Untitled Publication"))
      authors = html_escape(getfield_safe(pub, :authors, ""))
      venue = html_escape(getfield_safe(pub, :venue, ""))
      year = getfield_safe(pub, :year, "")
      summary = getfield_safe(pub, :summary, "")
      doi = getfield_safe(pub, :doi, "")
      meta_parts = filter(!isempty, [authors, venue, string(year)])
      meta = join(meta_parts, " · ")
      write(io, "<article class=\"accent-card\">")
      write(io, "<div class=\"accent-card__title\">$title</div>")
      if !isempty(meta)
        write(io, "<div class=\"accent-card__meta\">$meta</div>")
      end
      if !isempty(strip(summary))
        write(io, "<p class=\"accent-card__snippet\">$(html_escape(summary))</p>")
      end
      if !isempty(doi)
        write(
          io,
          "<a class=\"accent-card__doi\" href=\"$(html_escape(doi))\">DOI link</a>",
        )
      end
      write(io, "</article>")
    end
    return String(take!(io))
  catch e
    @error "Error in hfun_cv_publications" exception=(e, catch_backtrace())
    return "<p>Error displaying publications.</p>"
  end
end

function hfun_cv_teaching(_=nothing)
  isempty(CV_TEACHING) && return ""
  io = IOBuffer()
  write(io, "<div class=\"compact-rows\">")
  write(io, "<div class=\"compact-rows__heading\">Teaching</div>")
  write(io, "<div class=\"compact-rows__grid\">")
  for course in CV_TEACHING
    name = html_escape(course.course)
    audience = html_escape(course.audience)
    write(io, "<span class=\"compact-rows__key\">ongoing</span>")
    write(io, "<span class=\"compact-rows__val\">$name · $audience</span>")
  end
  write(io, "</div>")  # compact-rows__grid
  write(io, "</div>")  # compact-rows
  return String(take!(io))
end

function hfun_cv_skills(_=nothing)
  isempty(CV_SKILLS) && return ""
  io = IOBuffer()
  write(io, "<div class=\"compact-rows\">")
  write(io, "<div class=\"compact-rows__heading\">Skills</div>")
  write(io, "<div class=\"compact-rows__grid\">")
  for skill in CV_SKILLS
    label = html_escape(skill.label)
    items = html_escape(skill.items)
    write(io, "<span class=\"compact-rows__key\">$label</span>")
    write(io, "<span class=\"compact-rows__val\">$items</span>")
  end
  write(io, "</div>")  # compact-rows__grid
  write(io, "</div>")  # compact-rows
  return String(take!(io))
end

function render_highlights(io::IOBuffer, highlights::Vector{String})
  isempty(highlights) && return
  write(io, "<ul class=\"cv-section__highlights\">")
  for highlight in highlights
    write(io, "<li>$(html_escape(highlight))</li>")
  end
  write(io, "</ul>")
end

function hfun_cv_employment(_=nothing)
  try
    isempty(CV_EMPLOYMENT) && return "<p>No employment history yet.</p>"
    items = sort(CV_EMPLOYMENT, by = job -> getfield_safe(job, :start_date, Date(1900, 1, 1)), rev = true)
    io = IOBuffer()
    write(io, "<div class=\"dark-zone\">")
    write(io, "<span class=\"dark-zone__label\">Employment</span>")
    write(io, "<div class=\"dark-zone__grid\">")
    for job in items
      start_date = getfield_safe(job, :start_date, Date(1900, 1, 1))
      end_date = getfield_safe(job, :end_date, nothing)
      period = format_date_range(start_date, end_date)
      role = html_escape(getfield_safe(job, :role, "Unknown Position"))
      organization = html_escape(getfield_safe(job, :organization, ""))
      location = html_escape(getfield_safe(job, :location, ""))
      sub_parts = filter(!isempty, [organization, location])
      sub = join(sub_parts, " · ")
      write(io, "<span class=\"dark-zone__year\">$(html_escape(period))</span>")
      write(io, "<div>")
      write(io, "<div class=\"dark-zone__role\">$role</div>")
      if !isempty(sub)
        write(io, "<div class=\"dark-zone__sub\">$sub</div>")
      end
      write(io, "</div>")
    end
    write(io, "</div>")  # dark-zone__grid
    write(io, "</div>")  # dark-zone
    return String(take!(io))
  catch e
    @error "Error in hfun_cv_employment" exception=(e, catch_backtrace())
    return "<p>Error displaying employment history.</p>"
  end
end

function hfun_cv_education(_=nothing)
  isempty(CV_EDUCATION) && return ""
  items = sort(CV_EDUCATION, by = entry -> entry.start_date, rev = true)
  io = IOBuffer()
  write(io, "<div class=\"dark-zone dark-zone--secondary\">")
  write(io, "<span class=\"dark-zone__label\">Education</span>")
  write(io, "<div class=\"dark-zone__grid\">")
  for entry in items
    period = format_date_range(entry.start_date, entry.end_date)
    status = entry.end_date === nothing ? " · In progress" : ""
    program = html_escape(entry.program)
    institution = html_escape(entry.institution)
    location = html_escape(entry.location)
    sub_parts = filter(!isempty, [institution, location])
    sub = join(sub_parts, " · ") * status
    write(io, "<span class=\"dark-zone__year\">$(html_escape(period))</span>")
    write(io, "<div>")
    write(io, "<div class=\"dark-zone__role\">$program</div>")
    if !isempty(sub)
      write(io, "<div class=\"dark-zone__sub\">$sub</div>")
    end
    write(io, "</div>")
  end
  write(io, "</div>")  # dark-zone__grid
  write(io, "</div>")  # dark-zone
  return String(take!(io))
end

function hfun_cv_conferences(_=nothing)
  isempty(CV_CONFERENCES) && return ""
  items = sort(CV_CONFERENCES, by = event -> event.start_date, rev = true)
  io = IOBuffer()
  write(io, "<div class=\"compact-rows\">")
  write(io, "<div class=\"compact-rows__heading\">Conferences &amp; Schools</div>")
  write(io, "<div class=\"compact-rows__grid\">")
  for event in items
    year = string(Dates.year(event.start_date))
    name = html_escape(event.name)
    location = html_escape(event.location)
    role = event.role
    role_label = role == "Speaker" ? " <em>(speaker)</em>" : ""
    write(io, "<span class=\"compact-rows__key\">$year</span>")
    write(io, "<span class=\"compact-rows__val\">$name · $location$role_label</span>")
  end
  write(io, "</div>")  # compact-rows__grid
  write(io, "</div>")  # compact-rows
  return String(take!(io))
end

function hfun_cv_timeline(_=nothing)
  entries = gather_timeline_entries()
  isempty(entries) && return "<p>No timeline entries yet.</p>"
  io = IOBuffer()
  tag_counts = cv_timeline_tag_counts(entries)
  tags = sort(collect(keys(tag_counts)))
  write(
    io,
    "<div class=\"cv-timeline\">" *
    "<div class=\"cv-timeline__filters\" role=\"group\" aria-label=\"Filter timeline\">",
  )
  total = length(entries)
  write(
    io,
    "<button class=\"cv-timeline__filter is-active\" data-filter=\"all\" " *
    "aria-pressed=\"true\" data-count=\"$total\">All" *
    "<span class=\"cv-chip cv-chip--count\">$total</span></button>",
  )
  for tag in tags
    tag_slug = slugify_tag(tag)
    count = get(tag_counts, tag, 0)
    write(
      io,
      "<button class=\"cv-timeline__filter\" data-filter=\"$(html_escape(tag_slug))\" " *
      "aria-pressed=\"false\" data-count=\"$count\">$(html_escape(tag))" *
      "<span class=\"cv-chip cv-chip--count\">$count</span></button>",
    )
  end
  write(io, "</div>")
  write(io, "<div class=\"cv-timeline__list\">")
  for entry in entries
    tag_slug_list = join(slugify_tag.(entry.tags), " ")
    write(
      io,
      "<article class=\"cv-timeline__item\" data-tags=\"$(html_escape(tag_slug_list))\">",
    )
    write(
      io,
      "<div class=\"cv-timeline__meta\">" *
      "<span class=\"cv-timeline__year\">$(entry.year)</span>" *
      "<span class=\"cv-timeline__period\">$(html_escape(entry.period))</span>" *
      "</div>",
    )
    write(
      io,
      "<h3 class=\"cv-timeline__title\">$(html_escape(entry.title))</h3>",
    )
    write(
      io,
      "<p class=\"cv-timeline__subtitle\">$(html_escape(entry.subtitle)) · " *
      "$(html_escape(entry.location))</p>",
    )
    if !isempty(entry.highlights)
      write(io, "<ul class=\"cv-timeline__highlights\">")
      for highlight in entry.highlights
        write(
          io,
          "<li>$(html_escape(highlight))</li>",
        )
      end
      write(io, "</ul>")
    end
    # Tags retained in data but hidden by default; re-enable rendering if needed.
    write(io, "</article>")
  end
  write(io, "</div>")
  write(io, "</div>")
  write(io, """
<script>
document.addEventListener("DOMContentLoaded", function () {
  const buttons = Array.from(document.querySelectorAll(".cv-timeline__filter"));
  const items = Array.from(document.querySelectorAll(".cv-timeline__item"));
  if (buttons.length === 0 || items.length === 0) {
    return;
  }
  function applyCvFilter(target) {
    items.forEach(function (item) {
      if (target === "all") {
        item.classList.remove("is-hidden");
        return;
      }
      var tags = (item.dataset.tags || "").split(/\\s+/).filter(Boolean);
      if (tags.includes(target)) {
        item.classList.remove("is-hidden");
      } else {
        item.classList.add("is-hidden");
      }
    });
  }
  function setCvActive(button) {
    buttons.forEach(function (btn) {
      var active = btn === button;
      btn.classList.toggle("is-active", active);
      btn.setAttribute("aria-pressed", active ? "true" : "false");
    });
  }
  function activateCvFilter(target) {
    var button = buttons.find(function (btn) {
      return btn.dataset.filter === target;
    });
    if (!button) {
      return;
    }
    setCvActive(button);
    applyCvFilter(target);
  }
  buttons.forEach(function (button) {
    button.addEventListener("click", function () {
      activateCvFilter(button.dataset.filter);
    });
  });
  activateCvFilter("all");
});
</script>
""")
  return String(take!(io))
end

function hfun_cv_anchor(args)
  isempty(args) && return ""
  raw_id = String(args[1])
  anchor_id = slugify_tag(raw_id)
  title = length(args) ≥ 2 ? String(args[2]) : raw_id
  write_buffer = IOBuffer()
  write(write_buffer, "<span id=\"$(html_escape(anchor_id))\" class=\"cv-anchor__target\"></span>")
  write(
    write_buffer,
    "<a class=\"cv-anchor\" href=\"#$(html_escape(anchor_id))\" " *
    "aria-label=\"Link to $(html_escape(title)) section\">#</a>",
  )
  return String(take!(write_buffer))
end

end # module SiteUtils

using .SiteUtils
