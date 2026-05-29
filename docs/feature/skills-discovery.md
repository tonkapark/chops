## Discover / Browse Registry

A major re-write of skills registry browsing after 1.15.0

**Instant browse on open**
  - Opening Discovery browse registry modal now lands on a populated Trending list instead of a blank "Search the registry" placeholder
  - Shows ~600 skills ranked by install count, scraped once from skills.sh's trending page (no API key required)

**Fast, broader local search**
  - Typing filters the trending set locally and instantly — substring match across skill name, ID, and source
  - Matches far more than the old API alone (e.g. image → 28 results locally vs ~1–2 from the fuzzy name-search API)
  - Long-tail skills not in the trending set are still fetched via the live /api/search API and merged in below the local
  matches

**Caching (fast + good-netizen)**
  - Trending data is cached in memory for the session and on disk with a 6-hour TTL (~/Library/Application Support/Chops/trending-cache.json)
  - Survives app relaunches — reopening Browse shows results instantly without re-scraping
  - Requests send an honest Chops/macOS User-Agent and avoid per-keystroke network hits

**Trust & popularity signals**
  - Official only toggle to filter to verified skills
  - A blue checkmark.seal.fill badge marks official skills in the list
  - Install counts shown per row (e.g. 16.7K installs)

**Resilience**
  - If the trending scrape fails, the sheet falls back cleanly to the live search path — Browse never breaks
  - An expired cache simply re-scrapes; no stale data is served
