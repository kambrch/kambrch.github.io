module SiteUtils

using Dates
using Franklin
using Franklin: pagevar
using Base: Filesystem

export blog_posts,
  all_blog_tags,
  hfun_blog_index,
  hfun_blog_nav,
  hfun_cv_metrics,
  hfun_cv_downloads,
  hfun_cv_publications,
  hfun_cv_teaching,
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

const PROJECT_ROOT = dirname(@__FILE__)
const BLOG_CACHE = Ref{Union{Nothing, NamedTuple{(:signature, :posts), Tuple{String, Vector{BlogPostTuple}}}}}(nothing)
const FileRecord = NamedTuple{(:entry, :filepath, :statinfo), Tuple{String, String, Filesystem.StatStruct}}

include("cv_data.jl")
using .CVData

@eval Franklin begin
  function hfun_img(args)
    path = args[1]
    alt = length(args) ≥ 2 ? args[2] : ""
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

function parse_post_date(date_val, slug, statinfo)
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
  return Date(Dates.unix2datetime(statinfo.mtime))
end

function count_words(text::AbstractString)
  stripped = strip(String(text))
  isempty(stripped) && return 0
  return length(split(stripped, r"\s+", keepempty = false))
end

function extract_post_summary(filepath)
  content = read(filepath, String)
  lines = split(content, '\n')
  snippet_lines = String[]
  body_tokens = String[]
  for line in lines
    stripped = strip(line)
    startswith(stripped, "@def") && continue
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
  for entry in sort(readdir(blog_dir))
    endswith(entry, ".md") || continue
    filepath = joinpath(blog_dir, entry)
    statinfo = stat(filepath)
    push!(file_records, (; entry, filepath, statinfo))
    push!(signature_parts, string(statinfo.mtime))
  end

  signature = string(length(file_records)) * ":" * join(signature_parts, ";")
  cached = BLOG_CACHE[]
  if cached !== nothing && cached.signature == signature
    return cached.posts
  end

  posts = BlogPostTuple[]
  for record in file_records
    slug = replace(record.entry, r"\.md$" => "")
    rpath = "blog/" * slug
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
  end

  sort!(posts, by = p -> p.date)
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
  write(io, "<div class=\"blog-summary\">")
  write(
    io,
    "<span class=\"blog-summary__count\">$(html_escape(summary_label))</span>",
  )
  write(
    io,
    "<span class=\"blog-summary__sep\" aria-hidden=\"true\">&bull;</span>",
  )
  write(
    io,
    "<span class=\"blog-summary__latest\">Updated $(html_escape(latest_label))</span>",
  )
  write(io, "</div>")
  tag_counts = Dict{String, Int}()
  for post in posts
    for tag in post.tags
      tag_counts[tag] = get(tag_counts, tag, 0) + 1
    end
  end
  tags = all_blog_tags()
  write(
    io,
    "<div class=\"blog-filters\" role=\"group\" aria-label=\"Filter posts by tag\">",
  )
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
  write(io, "<div class=\"blog-list\">")
  for post in posts
    tag_slug_list = join(slugify_tag.(post.tags), " ")
    date_iso = Dates.format(post.date, dateformat"yyyy-mm-dd")
    date_display = long_date_label(post.date)
    write(
      io,
      "<article class=\"blog-card\" data-tags=\"$(html_escape(tag_slug_list))\">",
    )
    write(
      io,
      "<div class=\"blog-card__meta\"><time class=\"blog-card__meta-item\" " *
      "datetime=\"$date_iso\">$date_display</time>",
    )
    reading_label = format_reading_time(post.reading_minutes)
    if !isempty(reading_label)
      write(
        io,
        "<span class=\"blog-card__meta-item\">$(html_escape(reading_label))</span>",
      )
    end
    write(io, "</div>")
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
    write(
      io,
      "<a class=\"blog-card__cta\" href=\"$(html_escape(post.url))\" " *
      "aria-label=\"Read $(html_escape(post.title))\">Read more &rarr;</a>",
    )
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
  function setActiveButton(activeButton) {
    buttons.forEach(function (btn) {
      var isActive = btn === activeButton;
      btn.classList.toggle("is-active", isActive);
      btn.setAttribute("aria-pressed", isActive ? "true" : "false");
    });
  }
  function activateFilter(target) {
    var button = buttons.find(function (btn) {
      return btn.dataset.filter === target;
    });
    if (!button) {
      return;
    }
    setActiveButton(button);
    applyFilter(target);
    if (target === "all") {
      history.replaceState(null, "", window.location.pathname);
    } else {
      history.replaceState(null, "", window.location.pathname + "#tag=" + target);
    }
  }
  buttons.forEach(function (button) {
    button.addEventListener("click", function () {
      activateFilter(button.dataset.filter);
    });
  });
  var initialTarget = "all";
  var hashMatch = window.location.hash.match(/^#tag=([\\w-]+)/);
  if (hashMatch && hashMatch[1]) {
    initialTarget = hashMatch[1];
  }
  if (!buttons.some(function (btn) { return btn.dataset.filter === initialTarget; })) {
    initialTarget = "all";
  }
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
  write(io, "<nav class=\"blog-nav\" aria-label=\"Post navigation\">")

  write(io, "<div class=\"blog-nav__slot blog-nav__slot--prev\">")
  if prev_post !== nothing
    prev_title = html_escape(prev_post.title)
    write(
      io,
      "<a class=\"blog-nav__link\" href=\"$(html_escape(prev_post.url))\" " *
      "aria-label=\"Previous: $prev_title\">")
    write(io, "<span class=\"blog-nav__hint\">&larr; Previous</span>")
    write(io, "<span class=\"blog-nav__title\">$prev_title</span>")
    write(io, "</a>")
  else
    write(
      io,
      "<span class=\"blog-nav__link is-disabled\" role=\"text\">" *
      "<span class=\"blog-nav__hint\">&larr; Previous</span>" *
      "<span class=\"blog-nav__title\">Start of archive</span>" *
      "</span>",
    )
  end
  write(io, "</div>")

  write(io, "<div class=\"blog-nav__slot blog-nav__slot--all\">")
  write(
    io,
    "<a class=\"blog-nav__link blog-nav__link--all\" href=\"$(html_escape(back_href))\" " *
    "aria-label=\"Browse all posts\">" *
    "<span class=\"blog-nav__hint\">Archive</span>" *
    "<span class=\"blog-nav__title\">$(html_escape(back_label))</span>" *
    "</a>",
  )
  write(io, "</div>")

  write(io, "<div class=\"blog-nav__slot blog-nav__slot--next\">")
  if next_post !== nothing
    next_title = html_escape(next_post.title)
    write(
      io,
      "<a class=\"blog-nav__link\" href=\"$(html_escape(next_post.url))\" " *
      "aria-label=\"Next: $next_title\">")
    write(io, "<span class=\"blog-nav__hint\">Next &rarr;</span>")
    write(io, "<span class=\"blog-nav__title\">$next_title</span>")
    write(io, "</a>")
  else
    write(
      io,
      "<span class=\"blog-nav__link is-disabled\" role=\"text\">" *
      "<span class=\"blog-nav__hint\">Next &rarr;</span>" *
      "<span class=\"blog-nav__title\">End of archive</span>" *
      "</span>",
    )
  end
  write(io, "</div>")

  write(io, "</nav>")
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
    attrs = ["href=\"$(html_escape(item.href))\""]
    if !item.available
      push!(classes, "is-disabled")
      push!(attrs, "tabindex=\"-1\"", "aria-disabled=\"true\"")
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
  isempty(CV_PUBLICATIONS) && return "<p>No publications listed yet.</p>"
  io = IOBuffer()
  write(io, "<div class=\"cv-publications\">")
  for pub in sort(CV_PUBLICATIONS, by = p -> p.year, rev = true)
    write(io, "<article class=\"cv-publications__item\">")
    write(io, "<header class=\"cv-publications__header\">")
    write(
      io,
      "<h3 class=\"cv-publications__title\">$(html_escape(pub.title))</h3>",
    )
    write(
      io,
      "<p class=\"cv-publications__meta\">$(html_escape(pub.authors)) · " *
      "$(html_escape(pub.venue)) · $(pub.year)</p>",
    )
    write(io, "</header>")
    if !isempty(strip(pub.summary))
      write(
        io,
        "<p class=\"cv-publications__summary\">$(html_escape(pub.summary))</p>",
      )
    end
    if !isempty(pub.doi)
      write(
        io,
        "<p class=\"cv-publications__links\"><a href=\"$(html_escape(pub.doi))\">DOI link</a></p>",
      )
    end
    write(io, "</article>")
  end
  write(io, "</div>")
  return String(take!(io))
end

function hfun_cv_teaching(_=nothing)
  isempty(CV_TEACHING) && return ""
  io = IOBuffer()
  write(io, "<div class=\"cv-teaching\">")
  for course in CV_TEACHING
    write(io, "<div class=\"cv-teaching__item\">")
    write(
      io,
      "<h3 class=\"cv-teaching__title\">$(html_escape(course.course))</h3>",
    )
    if !isempty(course.audience)
      write(
        io,
        "<p class=\"cv-teaching__audience\">$(html_escape(course.audience))</p>",
      )
    end
    write(io, "</div>")
  end
  write(io, "</div>")
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
  isempty(CV_EMPLOYMENT) && return "<p>No employment history yet.</p>"
  items = sort(CV_EMPLOYMENT, by = job -> job.start_date, rev = true)
  io = IOBuffer()
  write(io, "<div class=\"cv-section-list\">")
  for job in items
    period = format_date_range(job.start_date, job.end_date)
    status = job.end_date === nothing ? "Present" : nothing
    write(io, "<article class=\"cv-section-item\">")
    write(
      io,
      "<header class=\"cv-section__header\">" *
      "<span class=\"cv-section__period\">$period</span>" *
      "</header>",
    )
    write(
      io,
      "<h3 class=\"cv-section__title\">$(html_escape(job.role))</h3>",
    )
    info = html_escape(job.organization)
    if !isempty(job.location)
      info *= " · " * html_escape(job.location)
    end
    if status !== nothing
      info *= " · " * status
    end
    write(io, "<p class=\"cv-section__subtitle\">$info</p>")
    render_highlights(io, job.highlights)
    write(io, "</article>")
  end
  write(io, "</div>")
  return String(take!(io))
end

function hfun_cv_education(_=nothing)
  isempty(CV_EDUCATION) && return ""
  items = sort(CV_EDUCATION, by = entry -> entry.start_date, rev = true)
  io = IOBuffer()
  write(io, "<div class=\"cv-section-list\">")
  for entry in items
    period = format_date_range(entry.start_date, entry.end_date)
    status = entry.end_date === nothing ? "In progress" : nothing
    write(io, "<article class=\"cv-section-item\">")
    write(
      io,
      "<header class=\"cv-section__header\">" *
      "<span class=\"cv-section__period\">$period</span>" *
      "</header>",
    )
    write(
      io,
      "<h3 class=\"cv-section__title\">$(html_escape(entry.program))</h3>",
    )
    info = html_escape(entry.institution)
    if !isempty(entry.location)
      info *= " · " * html_escape(entry.location)
    end
    if status !== nothing
      info *= " · " * status
    end
    write(io, "<p class=\"cv-section__subtitle\">$info</p>")
    render_highlights(io, entry.notes)
    write(io, "</article>")
  end
  write(io, "</div>")
  return String(take!(io))
end

function hfun_cv_conferences(_=nothing)
  isempty(CV_CONFERENCES) && return ""
  items = sort(CV_CONFERENCES, by = event -> event.start_date, rev = true)
  io = IOBuffer()
  write(io, "<div class=\"cv-section-list\">")
  for event in items
    period = format_event_period(event.start_date, event.end_date)
    write(io, "<article class=\"cv-section-item\">")
    write(
      io,
      "<header class=\"cv-section__header\">" *
      "<span class=\"cv-section__period\">$period</span>" *
      "</header>",
    )
    write(
      io,
      "<h3 class=\"cv-section__title\">$(html_escape(event.name))</h3>",
    )
    parts = String[]
    !isempty(event.role) && push!(parts, html_escape(event.role))
    !isempty(event.location) && push!(parts, html_escape(event.location))
    info = join(parts, " · ")
    if !isempty(info)
      write(io, "<p class=\"cv-section__subtitle\">$info</p>")
    end
    highlights = String[]
    if !isempty(strip(event.topic))
      push!(highlights, event.topic)
    end
    render_highlights(io, highlights)
    write(io, "</article>")
  end
  write(io, "</div>")
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
