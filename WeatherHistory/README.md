# Then & Now: a weather comparison app for iPhone

A SwiftUI app that shows **today's weather next to the same calendar day in each of the last 5 years**,
plus an **AI summary (Claude)** that explains why today is different from, or similar to, last year.

## Features
- Today's temperature at your current local hour, with today's high and low
- A chip such as "4° warmer than this time last year"
- A chart with low–high bars for each year, a dot for the temperature at this hour, and a dashed 5-year average
- Year-by-year rows showing high/low, rain, wind speed and wind direction, and a condition icon
- **AI explanation**: Claude gets each year's temperature, rain, humidity, cloud cover, pressure and
  prevailing wind, and explains the difference from last year in plain language (for example, a wind shift
  bringing in colder air, or higher pressure giving clear skies)
- Current location (CoreLocation) or city search
- Metric/imperial toggle. Pull to refresh.

## Requirements
- Xcode 16 or later; the app runs on iOS 17 or later
- A Claude API key from https://console.anthropic.com (only needed for the AI summary)
- Weather data comes from [Open-Meteo](https://open-meteo.com), which is free and needs no key

## Run it
1. Open `WeatherHistory.xcodeproj` in Xcode.
2. Select the **WeatherHistory** target, open **Signing & Capabilities**, and choose your Team.
   If the bundle ID `com.example.WeatherHistory` is taken, change it.
3. Choose an iPhone simulator or your own device, then press **Run**.
4. In the app, tap the gear icon, paste your Claude API key, then tap Done.

## How it works
| File | Purpose |
|---|---|
| `Services/WeatherService.swift` | Gets today's data from Open-Meteo's forecast API (in the location's own time zone) and the same date in each of the past 5 years from the archive API, all in parallel. It turns the hourly data into daily figures. |
| `Services/ClaudeService.swift` | Sends one request to the Claude Messages API (`claude-opus-5-5`) over plain HTTPS, with a data table and a meteorologist prompt. |
| `Services/KeychainStore.swift` | Stores the API key in the iOS Keychain. |
| `Services/LocationManager.swift` | Gets a one-time location fix using async/await. |
| `Models/WeatherViewModel.swift` | Tracks app state and runs loading and summarizing. |
| `Views/*` | The SwiftUI screens and the Swift Charts chart. |

Notes:
- Feb 29 is compared with Feb 28 in years that aren't leap years.
- Today's later hours are forecast, so today's high and low can still change.
- The AI request uses `effort: "low"` to keep responses fast. To get more detailed reasoning, raise it to `"medium"` in `ClaudeService.swift`.
- The request turns on server-side refusal fallbacks (`fallbacks: "default"`). If Claude declines a request, the API retries it on a suitable fallback model.

## Before shipping to the App Store
In this version, each user enters their own API key on their device. That's fine for personal use.
For a public app, **don't put your API key inside the app**. Run a small backend (for example a
Cloudflare Worker or a serverless function) that keeps the key and forwards the request. Then change
`ClaudeService.endpoint` to point at your backend.
