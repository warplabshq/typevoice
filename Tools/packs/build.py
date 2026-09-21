#!/usr/bin/env python3
"""Builds the word packs the app ships: words the speech model tends to mangle, from open data.

    python3 Tools/packs/build.py            # writes Sources/TypeVoice/Resources/Packs/*.txt (+ SOURCES.md)

Runs on a developer's Mac, never inside the app. Sources and licences are listed in SOURCES.md.
A pack is one term per line, UTF-8, sorted case-insensitively. Anything the model already
spells (a word in the system dictionary) is dropped: packs hold only what needs help.
"""
import json, re, sys, time, urllib.request, urllib.parse, pathlib

UA = "TypeVoicePacks/1.0 (+https://typevoice.ai; mail@warplabs.co)"
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Sources" / "TypeVoice" / "Resources" / "Packs"

def get(url, tries=3):
    # curl rather than urllib: python.org builds often lack the system root certificates.
    import subprocess
    for i in range(tries):
        r = subprocess.run(["curl", "-sSL", "--max-time", "180", "-A", UA, "-H", "Accept: application/json", url],
                           capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout
        if i == tries - 1: raise RuntimeError(r.stderr.strip() or "empty response")
        time.sleep(2 + 3 * i)

# ---- the words the model already knows: the system dictionary plus a few we add by hand
KNOWN = set(w.strip().lower() for w in open("/usr/share/dict/words", errors="ignore"))
KNOWN |= {"app", "apps", "api", "apis", "cli", "gui", "ai", "ui", "ux", "url", "http", "https", "json", "html", "css", "sql",
          "wifi", "email", "emails", "online", "offline", "website", "websites", "internet", "google", "apple", "amazon",
          "microsoft", "facebook", "twitter", "youtube", "instagram", "netflix", "iphone", "ipad", "mac", "macbook", "linux",
          "windows", "android", "chrome", "safari", "firefox", "python", "java", "javascript", "swift", "github", "gitlab",
          "docker", "kubernetes", "react", "node", "npm", "pip", "git", "vim", "emacs", "slack", "zoom", "discord", "reddit",
          "tiktok", "whatsapp", "telegram", "spotify", "uber", "airbnb", "tesla", "openai", "chatgpt", "gpt", "llm", "llms"}

OK_CHARS = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 .'+#&-]{1,39}$")

def clean(term):
    t = re.sub(r"\s+", " ", term.strip())
    if not OK_CHARS.match(t): return None
    if t.isdigit() or len(t) < 3: return None
    words = t.split(" ")
    if len(words) > 3: return None
    # Every word already in the dictionary → the model can spell it → not our job.
    if all(w.lower().strip(".'+#&-") in KNOWN for w in words): return None
    if re.fullmatch(r"[A-Z]{1,2}", t): return None
    if re.search(r"\b(Inc|Ltd|LLC|GmbH|Corp|Corporation|Company|Group|Holdings|Limited|AG|SA|plc|Co)\.?$", t): return None
    if re.search(r"\b(TV|Broadcasting|Channel|Radio|Television|Network)\b", t): return None
    return t

def dedupe(terms):
    seen, out = set(), []
    for t in terms:
        k = t.lower()
        if k in seen: continue
        seen.add(k); out.append(t)
    return sorted(out, key=str.lower)

# ---- sources
def homebrew():
    """The formulae and casks people actually install (Homebrew's 30-day analytics), by name."""
    names = []
    inst = json.loads(get("https://formulae.brew.sh/api/analytics/install/30d.json"))["items"]
    for row in inst[:1500]:
        n = row["formula"]
        if "/" in n: continue                                   # third-party taps
        n = n.split("@")[0]                                     # openssl@3 → openssl
        if n.count("-") > 1 or re.search(r"\d", n) or ("-" in n and min(len(p) for p in n.split("-")) < 3): continue
        if n.startswith("lib") or len(n) <= 3: continue                 # dependencies nobody says out loud
        names.append(n)
    casks = {c["token"]: c for c in json.loads(get("https://formulae.brew.sh/api/cask.json"))}
    for row in json.loads(get("https://formulae.brew.sh/api/analytics/cask-install/30d.json"))["items"][:1500]:
        c = casks.get(row["cask"].split("/")[-1])
        if not c: continue
        for n in c.get("name", [])[:1]:
            if re.fullmatch(r"[\d.]+", n): continue
            names.append(n)
    return names

def wikidata(min_sitelinks=5):
    classes = {"Q7397": "software", "Q166142": "application", "Q9143": "programming language", "Q188860": "software library",
               "Q193424": "web service", "Q1058914": "software company"}
    names = []
    for q, label in classes.items():
        query = f"""SELECT ?l WHERE {{ ?x wdt:P31 wd:{q} ; wikibase:sitelinks ?s ; rdfs:label ?l .
                    FILTER(?s >= {min_sitelinks}) FILTER(LANG(?l) = "en") }} LIMIT 25000"""
        url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": query, "format": "json"})
        try:
            rows = json.loads(get(url))["results"]["bindings"]
        except Exception as e:
            print(f"  wikidata {label}: skipped ({e})", file=sys.stderr); continue
        names += [r["l"]["value"] for r in rows]
        print(f"  wikidata {label}: {len(rows)}", file=sys.stderr)
        time.sleep(1)
    return names

def wiktionary_category(cat):
    titles, cont = [], ""
    while True:
        url = ("https://en.wiktionary.org/w/api.php?" + urllib.parse.urlencode({
            "action": "query", "list": "categorymembers", "cmtitle": f"Category:{cat}", "cmlimit": "500",
            "cmnamespace": "0", "format": "json", **({"cmcontinue": cont} if cont else {})}))
        d = json.loads(get(url))
        titles += [m["title"] for m in d["query"]["categorymembers"]]
        cont = d.get("continue", {}).get("cmcontinue")
        if not cont: break
        time.sleep(0.3)
    return titles

# Edgy corners of internet slang that no dictation app should ever type on its own. Wiktionary's
# offensive categories catch most slurs; this catches the meme suffixes and dog whistles they miss.
BLOCK = re.compile(r"(jew|goy|gay|fag|tard|nig|chink|spic|kike|tran+y|dyke|rape|nazi|hitler|cuck|incel|coomer|"
                   r"oid$|slop$|maxx|mog$|mogger|cel$|pilled$|jak$|pedo|groom|cope$|seethe)", re.I)

def popular(title, min_views=1000):
    """Wiktionary page views over the last two full months: a word nobody looks up is not slang
    people use, it's a curiosity; leaving it out avoids a false correction."""
    import datetime
    today = datetime.date.today().replace(day=1)
    end = today - datetime.timedelta(days=1)
    start = (end.replace(day=1) - datetime.timedelta(days=1)).replace(day=1)
    url = ("https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wiktionary/all-access/user/"
           f"{urllib.parse.quote(title)}/monthly/{start:%Y%m%d}00/{end:%Y%m%d}00")
    try:
        views = sum(i["views"] for i in json.loads(get(url, tries=1)).get("items", []))
    except Exception:
        return False
    return views >= min_views

def pypi_top():
    try:
        d = json.loads(get("https://hugovk.github.io/top-pypi-packages/top-pypi-packages.min.json"))
        return [r["project"] for r in d["rows"][:1500] if "-" not in r["project"] and "_" not in r["project"]]
    except Exception as e:
        print(f"  pypi: skipped ({e})", file=sys.stderr); return []

def count(name):
    f = OUT / name
    return sum(1 for l in f.read_text().splitlines() if l.strip()) if f.exists() else 0

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("dev", "all"):
        print("developer tools…", file=sys.stderr)
        core = [l.strip() for l in (ROOT / "Tools" / "packs" / "core-dev.txt").read_text().splitlines() if l.strip() and not l.startswith("#")]
        dev = core + homebrew() + pypi_top() + wikidata()
        dev = dedupe(t for t in (clean(x) for x in dev) if t)
        (OUT / "developer-tools.txt").write_text("\n".join(dev) + "\n")
        print(f"  {len(dev)} terms", file=sys.stderr)
    if which in ("slang", "all"):
        # Wiktionary's slang categories skew hard toward the ugliest corners of the internet
        # (even after its offensive categories are removed), and a dictation app must never
        # type those on its own. The slang pack is therefore a hand-picked list.
        print("internet slang…", file=sys.stderr)
        core = [l.strip() for l in (ROOT / "Tools" / "packs" / "core-slang.txt").read_text().splitlines() if l.strip() and not l.startswith("#")]
        slang = dedupe(t for t in (clean(x) for x in core) if t and not BLOCK.search(t))
        (OUT / "internet-slang.txt").write_text("\n".join(slang) + "\n")
        print(f"  {len(slang)} terms", file=sys.stderr)
    dev, slang = count("developer-tools.txt"), count("internet-slang.txt")

    (OUT / "SOURCES.md").write_text(f"""# Word packs

Built by `Tools/packs/build.py` on {time.strftime('%Y-%m-%d')}. One term per line. They ship inside the app and are only
ever read from disk: no pack is fetched at runtime. Each pack lists spellings the speech model
tends to get wrong; ordinary dictionary words are left out on purpose.

| Pack | Terms | Sources | Licence |
|---|---|---|---|
| developer-tools.txt | {dev} | A hand-picked core list (Tools/packs/core-dev.txt), the 1,500 most-installed Homebrew formulae and casks (formulae.brew.sh analytics), the top 1,500 PyPI packages (hugovk/top-pypi-packages), Wikidata software, languages, libraries, services and software/tech companies with 5+ sitelinks | Homebrew BSD-2-Clause · top-pypi-packages MIT · Wikidata CC0 |
| internet-slang.txt | {slang} | Hand-picked (Tools/packs/core-slang.txt); Wiktionary's slang categories were evaluated and rejected as a source | our own list, GPL v3 like the rest of the app |

Wikidata is a project of the Wikimedia Foundation; Homebrew is the Homebrew project. Neither is
affiliated with TypeVoice.
""")

if __name__ == "__main__":
    main()
