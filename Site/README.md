# Site

Static landing page plus the legal pages App Store Connect asks for.

- `index.html` — marketing page (Marketing URL)
- `support.html` — support + FAQ (Support URL)
- `privacy.html` — privacy policy (Privacy Policy URL)
- `terms.html` — terms of use
- `eula.html` — end-user license agreement including Apple's required minimum terms
  (paste its URL, or its text, into the app's EULA field in App Store Connect)

Everything brand-specific is in `site.js` (`SITE`): name, company, email, domain, App Store
link, date, jurisdiction. Change it there and every page updates.

Deploy: it's plain HTML. Drop the folder on Vercel, Netlify, Cloudflare Pages or GitHub Pages.
`assets/summary.png` is a screenshot of the app; refresh it after the rebrand.
