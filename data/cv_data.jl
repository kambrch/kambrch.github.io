module CVData

using Dates

export CV_PUBLICATIONS,
  CV_CONFERENCES,
  CV_EMPLOYMENT,
  CV_EDUCATION,
  CV_TEACHING,
  CV_DOWNLOADS

const CV_PUBLICATIONS = [
  (
    ;
    title = "Laser refrigeration and anti-Stokes luminescence of Ytterbium-doped YVO4 and CaF2 microcrystals",
    authors = "Pawel Karpinski, Kamil Bruchal, Magdalena Dudek, Vitor Paschoal",
    venue = "Proc. SPIE 13703, Optical Manipulation and Structured Materials Conference 2025",
    year = 2025,
    doi = "https://doi.org/10.1117/12.3072294",
    tags = ["research", "optics"],
    summary = "Presented experimental evidence of anti-Stokes cooling pathways in microcrystals.",
  ),
]

const CV_CONFERENCES = [
  (
    ;
    name = "OPTO 2024",
    location = "Prague, CZ",
    start_date = Date(2024, 7, 22),
    end_date = Date(2024, 7, 26),
    role = "Speaker",
    topic = "Spectroscopic routes to optical refrigeration in microcrystals",
    tags = ["conference", "talk", "optics"],
  ),
  (
    ;
    name = "Fizyczno-Astronomiczna Konferencja",
    location = "Karpacz, PL",
    start_date = Date(2024, 3, 15),
    end_date = Date(2024, 3, 17),
    role = "Speaker",
    topic = "Compact cryogenic instrumentation for optical diagnostics",
    tags = ["conference", "talk", "instrumentation"],
  ),
  (
    ;
    name = "FuNaM-4",
    location = "Cracow, PL",
    start_date = Date(2023, 9, 26),
    end_date = Date(2023, 9, 29),
    role = "Participant",
    topic = "Functional nanomaterials symposium",
    tags = ["conference", "nanomaterials"],
  ),
  (
    ;
    name = "Kryształki Molekularne",
    location = "Poznań, PL",
    start_date = Date(2023, 9, 13),
    end_date = Date(2023, 9, 15),
    role = "Participant",
    topic = "Molecular crystals workshop",
    tags = ["conference", "materials"],
  ),
  (
    ;
    name = "NCLas Summer School",
    location = "Cracow, PL",
    start_date = Date(2023, 8, 27),
    end_date = Date(2023, 9, 1),
    role = "Participant",
    topic = "Next-generation cryogenic lasers",
    tags = ["school", "optics"],
  ),
]

const CV_EMPLOYMENT = [
  (
    ;
    role = "University Teacher",
    organization = "Wrocław University of Science and Technology (WUST)",
    location = "Wrocław, PL",
    start_date = Date(2024, 1, 1),
    end_date = nothing,
    tags = ["employment", "teaching", "physics"],
    highlights = [
      "Delivered undergraduate laboratory classes covering solid-state physics and measurement techniques",
      "Coordinated lab equipment maintenance and calibration routines",
    ],
  ),
  (
    ;
    role = "PhD Researcher",
    organization = "Wrocław University of Science and Technology (WUST)",
    location = "Wrocław, PL",
    start_date = Date(2022, 1, 1),
    end_date = nothing,
    tags = ["employment", "research", "optics"],
    highlights = [
      "Investigating optical refrigeration pathways in rare-earth-doped crystals",
      "Built custom cryogenic setups integrating spectroscopy and RF diagnostics",
    ],
  ),
  (
    ;
    role = "Student Researcher",
    organization = "Wrocław University of Science and Technology (WUST)",
    location = "Wrocław, PL",
    start_date = Date(2021, 1, 1),
    end_date = Date(2022, 12, 31),
    tags = ["employment", "research"],
    highlights = [
      "Assisted in nanoparticle synthesis experiments for photonic applications",
    ],
  ),
  (
    ;
    role = "Research Intern",
    organization = "LNCMI - Toulouse",
    location = "Toulouse, FR",
    start_date = Date(2021, 6, 1),
    end_date = Date(2021, 9, 30),
    tags = ["employment", "internship", "magnetics"],
    highlights = [
      "Worked on high-field magneto-optical measurements for semiconductor structures",
    ],
  ),
  (
    ;
    role = "Research Intern",
    organization = "Julius-Maximilians-Universität Würzburg",
    location = "Würzburg, DE",
    start_date = Date(2019, 6, 1),
    end_date = Date(2019, 9, 30),
    tags = ["employment", "internship", "semiconductors"],
    highlights = [
      "Characterised semiconductor quantum wells for photonic devices",
    ],
  ),
]

const CV_EDUCATION = [
  (
    ;
    program = "PhD in Chemical Sciences",
    institution = "Wrocław University of Science and Technology (WUST)",
    location = "Wrocław, PL",
    start_date = Date(2022, 1, 1),
    end_date = nothing,
    tags = ["education", "doctoral"],
    notes = [
      "Doctoral research on optical refrigeration in rare-earth-doped microcrystals",
      "Combines spectroscopy, cryogenics, and embedded control systems",
    ],
  ),
  (
    ;
    program = "MSc in Quntum Engineering",
    institution = "Wrocław University of Science and Technology (WUST)",
    location = "Wrocław, PL",
    start_date = Date(2017, 10, 1),
    end_date = Date(2022, 7, 1),
    tags = ["education", "masters"],
    notes = [
      "Focused on optoelectronics and photonic materials",
      "Thesis explored cryogenic measurement methods for luminescent crystals",
    ],
  ),
]

const CV_TEACHING = [
  (
    ;
    course = "Introductory physics",
    audience = "Undergraduate engineering cohorts",
    tags = ["teaching", "physics"],
  ),
  (
    ;
    course = "Laboratories of physics",
    audience = "First- and second-year students",
    tags = ["teaching", "lab"],
  ),
]

const CV_DOWNLOADS = [
  (
    ;
    label = "Full CV (PDF)",
    href = "/results/cv/kamil-bruchal-cv.pdf",
    format = "PDF",
    updated = Date(2025, 11, 5),
    available = false,
  ),
  (
    ;
    label = "Résumé snapshot (TXT)",
    href = "/results/cv/kamil-bruchal-resume.txt",
    format = "TXT",
    updated = Date(2025, 11, 5),
    available = false,
  ),
]

end
