# Weather in conversation — build 19

“What's the weather today?” previously reached free-form local generation with
no current forecast. A plausible sunny answer was not backed by live data.
Weather questions now use a read-only Open-Meteo client before local generation.

- Ask “今日の天気は？”; Mate asks for a city when it does not have one.
- “横浜の今日の天気は？” or “What's the weather in London tomorrow?” can supply
  the city directly. Ambiguous results require a numbered choice.
- “明日は？” / “What about tomorrow?” reuses the city within this conversation,
  while making a new forecast request. Clearing the conversation clears it.
- The supported periods are current conditions and daily forecasts for today,
  tomorrow and the day after tomorrow, using the destination's timezone.
  Unsupported periods receive an explicit scope response.
- Replies use returned weather codes, temperatures and precipitation probability,
  with the date and provider named. They do not ask the LLM to invent or rewrite
  the forecast. The conversation sheet links to the provider, response and licence.
- Missing, stale, malformed or unavailable forecasts produce an unavailable
  answer. There is no cached-sunny or generated-weather fallback.

Weather lookup remains a separate service. Build 20 adds [optional general Web search](web-search.md). The local model's
instructions also prohibit claiming current news or prices without evidence;
that instruction alone does not establish general hallucination prevention.

## Privacy and service scope

The extracted city name, or a short location answer after Mate asks for a city,
goes to `geocoding-api.open-meteo.com`; the selected city's public coordinates go
to `api.open-meteo.com`. The client has no access to GPS, microphone audio, prior
conversation history, notes, card information or wallet details. A location
answer is user-provided text, not a guarantee that it contains no personal data. Requests use an ephemeral, cookie-free session without redirects
or local response caching. The provider still receives the network IP and may
log queries/coordinates under its privacy terms. No new paid service or API key
is configured.

The public API is for non-commercial use with documented request limits. This
personal test build is not evidence of commercial release readiness: a commercial
release needs an appropriate provider subscription/deployment. Forecast data is
CC BY 4.0; links and attribution remain visible. Japanese municipalities use
formal city names where needed because bare place names can match a different
settlement. Candidates are restricted to populated places/administrative areas;
Mate does not silently select one of multiple locations.

## Validation

A [fixed-city live API run](evidence/weather-live-api-2026-09-22.json) retrieved
a real forecast for 横浜市 on September 22. This is Mac/network evidence; it
does not establish a successful phone update or microphone interaction.

Core regressions cover returned rain instead of invented sun, destination-local
dates, stale/future timestamps, wrong units, malformed arrays, impossible values,
query minimization and endpoint restrictions. Native regressions cover missing
cities, follow-ups, history reset, translations and unavailable data without
entering free-form model generation. Live checks use a fixed public city query;
they do not infer or collect the owner's current location.

Sources reviewed on September 22, 2026:
[Forecast API](https://open-meteo.com/en/docs),
[Geocoding API](https://open-meteo.com/en/docs/geocoding-api),
[Terms and privacy](https://open-meteo.com/en/terms),
[Data licence](https://creativecommons.org/licenses/by/4.0/).
