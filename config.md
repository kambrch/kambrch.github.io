<!--
Add here global page variables to use throughout your website.
-->
+++
author = "Kamil 'Kamash' Bruchal"
mintoclevel = 2

schema_job_title = "Physicist"
schema_url = "https://www.kambr.pl"
schema_image = "https://kambr.pl/assets/img/kamash_komodka.jpg"
schema_email = "mailto:kambr@kambr.pl"
schema_address_locality = "Wrocław"
schema_address_country = "PL"
schema_alternate_names_json = """["Kamaś", "Kamash"]"""
schema_affiliations_json = """[
  {"@type": "Organization", "name": "PhoBiA"},
  {"@type": "Organization", "name": "Institute of Advanced Materials"},
  {"@type": "Organization", "name": "Hackerspace Wrocław"}
]"""
schema_sameas_json = """[
  "https://github.com/kambrch",
  "https://www.linkedin.com/in/kamil-bruchal",
  "https://www.qrz.com/db/SP6WRN",
  "https://phobia.pwr.edu.pl/kamil-bruchal",
  "https://iam.pwr.edu.pl/people/kamil-bruchal",
  "https://hswro.org"
]"""

base_url = "https://www.kambr.pl/"

## Franklin does not read .gitignore — files left in the working tree get
## published even when git never sees them, so build metadata, tooling and
## private notes must be excluded here explicitly
ignore = ["node_modules/", ".venv/", "docs/", "scripts/",
          # hidden dirs are copied too: .julia_depot alone is ~87 MB locally
          ".claude/", ".superpowers/", ".julia_depot/",
          "README.md", "Project.toml", "Manifest.toml", "requirements.txt",
          "package.json", "package-lock.json",
          ".markdownlint.json", ".markdownlint-cli2.yaml", ".gitlab-ci.yml",
          # assistant / notes files, mirrors ~/.gitignore_global
          "CLAUDE.md", "AGENTS.md", "notes.md", "Notes.md",
          "private/", ".private/", "reports/", "logs/", "tmp/"]

## RSS (the website_{title, descr, url} must be defined to get RSS)
generate_rss = true
website_title = "Kamash Site"
website_descr = "Physicist, Julia developer, and hardware hacker based in Wrocław."
website_url = "https://www.kambr.pl/"
+++

<!--
Add here global latex commands to use throughout your pages.
-->
\newcommand{\R}{\mathbb R}
\newcommand{\scal}[1]{\langle #1 \rangle}
