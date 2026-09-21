# Word packs

Built by `Tools/packs/build.py` on 2026-09-22. One term per line. They ship inside the app and are only
ever read from disk: no pack is fetched at runtime. Each pack lists spellings the speech model
tends to get wrong; ordinary dictionary words are left out on purpose.

| Pack | Terms | Sources | Licence |
|---|---|---|---|
| developer-tools.txt | 3656 | A hand-picked core list (Tools/packs/core-dev.txt), the 1,500 most-installed Homebrew formulae and casks (formulae.brew.sh analytics), the top 1,500 PyPI packages (hugovk/top-pypi-packages), Wikidata software, languages, libraries, services and software/tech companies with 5+ sitelinks | Homebrew BSD-2-Clause · top-pypi-packages MIT · Wikidata CC0 |
| internet-slang.txt | 83 | Hand-picked (Tools/packs/core-slang.txt); Wiktionary's slang categories were evaluated and rejected as a source | our own list, GPL v3 like the rest of the app |

Wikidata is a project of the Wikimedia Foundation; Homebrew is the Homebrew project. Neither is
affiliated with TypeVoice.
