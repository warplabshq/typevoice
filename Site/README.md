# Site

Static landing page plus the legal pages App Store Connect asks for.

- `index.html` — marketing page (Marketing URL)
- `support.html` — support + FAQ (Support URL)
- `privacy.html` — privacy policy (Privacy Policy URL)
- `terms.html` — terms of use
- `eula.html` — end-user license agreement including Apple's required minimum terms
  (paste its URL, or its text, into the app's EULA field in App Store Connect)

Everything brand-specific is in `site.js` (`SITE`): name, company, email, domain, App Store
link, date, jurisdiction, postal address. Change it there and every page updates.

SEO lives in the `<head>` of each page and can't come from JS: canonical and Open Graph URLs,
the JSON-LD (`SoftwareApplication` + `FAQPage` on the home page), `robots.txt` and
`sitemap.xml`. They carry the same `https://REPLACE-ME.example` placeholder as `site.js`;
when the domain exists, replace it everywhere in one go:

    grep -rl "REPLACE-ME.example" Site | xargs sed -i '' 's|https://REPLACE-ME.example|https://your.domain|g'

On a rebrand, also replace "Murmur" in the `<title>`, `og:*` and JSON-LD tags, and re-render
`assets/og.png` (1200×630, the social preview). The display font is self-hosted in
`assets/fonts/` (SIL OFL) so the site makes no third-party requests, which the privacy
policy promises.

Deploy: it's plain HTML. Drop the folder on Vercel, Netlify, Cloudflare Pages or GitHub Pages.
