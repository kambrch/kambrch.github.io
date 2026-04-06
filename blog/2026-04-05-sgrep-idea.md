@def title = "sgrep — semantic-aware grep"
@def published = Date(2026, 4, 5)
@def tags = ["LLM", "tools", "coding"]
@def rss = "Notes on sgrep — a local semantic search tool that stays grep-shaped: one binary, no daemon, composable output."

{{post_header}}

Recently I started getting interested in embedding text into vector spaces.
My initial interests were guided by observation of a familiar mathematical
framework (vectors in linear space as representation of known state of system)
to a disjointed field (natural language processing). In the last few weeks
this field also helps me to pay for living, which is a nice bonus.

Today I've read Shrimple's note on ["proper natural language `grep`"][shrimple]
in which she's reverse-engineering an existing semantic-search tool, extracting
the essential pipeline, and sketching how to build a version that behaves more
like real grep. This inspired me to ponder on my own bottom-to-top approach.

The underlying problem is ordinary enough: *I know I wrote something down, I
remember what it meant, but I no longer remember the exact words.* Yet once you
start looking for solutions, you quickly end up in a world of source-code
indexers, background daemons, chat frontends, and other machinery that no
longer feels like `grep` at all. That was also part of Shrimple's complaint:
not enough command-line directness, not enough composability, and too much
surrounding infrastructure for what should be a simple search tool.

## General idea

I'm still trying to work out what *natural language grep* should mean in
detail, but I can imagine some concrete use-case. I know I wrote something
down. I remember roughly what it was about. Maybe I remember the situation,
the conclusion, or the phrasing I would use now. But the exact wording I used
at the time is gone. In that situation, `grep` stops being a search tool and
becomes a test of memory. If I can reconstruct the original string closely
enough, great. If I cannot, it quietly stops being useful. I could still find
my missing note with a semantic search tool -- one that looks for files based
on meaning rather than exact content.

I'm calling it `sgrep`: grep, but semantic.

Index notes, docs, logs, or other plain text into a local embedding store,
then query them *grep-style* in natural language.

I do not want this to be a service. I do not want it running in the background.
I do not want to "chat with my notes." I do not want an interface that assumes
the real user is another language model. I want one binary, explicit
subcommands, line-oriented output, predictable exit status, and something I
can drop into a shell pipeline without fighting somebody else's product
decisions.

## First version sketch

The first version is intentionally narrow. No approximate nearest-neighbour
index yet. I want a baseline that is boring enough to understand and solid
enough to evaluate: store chunk records, store embeddings locally, run an
exact cosine scan, and emit stable grep-like or JSON output.

The first thing to figure out is chunking. Chunks should map to coherent
logical units and stay small enough to be useful. I looked at a few benchmarks.
Vecta [tested seven strategies][vecta] across 50 academic papers: recursive
splitting at 512 tokens won with 69% accuracy, ahead of fixed-size chunks
(67%) and semantic chunking (54%) -- the semantic approach fragmented the
corpus into 17,000 pieces averaging 43 tokens each, which collapsed document
coherence. NVIDIA's [five-dataset study][nvidia] found page-level chunking
most consistent, though it didn't include recursive splitting. Good enough
argument for the simple approach: split by paragraphs first (*blank lines*),
fall back to *newlines*, then to *sentence terminators* if chunks are still
too long.

For the embedding model, I'm leaning towards
`sentence-transformers/all-MiniLM-L6-v2`. An embedding model takes a piece of
text an maps it to a dense vector -- a list of numbers that encodes meaning
rather than words. Two sentences that say the same thing should land close
together in that space; two that don't should sit far apart. That's the thing
you measure with cosine similarity: the angle between two vectors.

`all-MiniLM-L6-v2` is small (~80 MB), fast on CPU, and maps text to a
384-dimensional space. It was trained specifically for semantic similarity,
which is exactly the task. There are better models, but they are larger and
slower -- for a pile of personal notes on a laptop, this is the right
tradeoff.

## Does it even make any sense?

I think Shrimple's post helped me see that the interesting constraint is not
just "semantic search, locally." It is "semantic search without ceasing to be
grep-shaped." That's what sets it apart from the whole zoo of RAG-shaped tools
already available.

Semantic search works -- that's not the question. The question is whether it
can stay composable: one binary, no daemon, predictable exit status, something
you can drop into a pipeline. Most tools quietly answer that with "no." The
grep-shaped constraint is the bet. Only a real pile of notes tells you if it
pays off.

[shrimple]: https://www.shrimple.pl/2026/03/embeddings-grep-approach/
[vecta]: https://www.runvecta.com/blog/we-benchmarked-7-chunking-strategies-most-advice-was-wrong
[nvidia]: https://developer.nvidia.com/blog/finding-the-best-chunking-strategy-for-accurate-ai-responses/

{{blog_nav}}
