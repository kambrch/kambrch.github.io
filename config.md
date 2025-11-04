<!--
Add here global page variables to use throughout your website.
-->
+++
author = "Kamil 'Kamash' Bruchal"
mintoclevel = 2

schema_job_title = "Physicist"
schema_url = "https://kambr.pl"
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
  "https://www.qrz.com/db/SP6WRN",
  "https://phobia.pwr.edu.pl/kamil-bruchal",
  "https://iam.pwr.edu.pl/people/kamil-bruchal",
  "https://hswro.org"
]"""

base_url = "https://www.kambr.pl/"

ignore = ["node_modules/"]

## RSS (the website_{title, descr, url} must be defined to get RSS)
generate_rss = true
website_title = "Kamash Site"
website_descr = "My personal website generated with Franklin."
website_url = "https://kambrch.github.io/"
+++

<!--
Add here global latex commands to use throughout your pages.
-->
\newcommand{\R}{\mathbb R}
\newcommand{\scal}[1]{\langle #1 \rangle}
