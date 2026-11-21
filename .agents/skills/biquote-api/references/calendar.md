# Biquote Economic Calendar Reference

The Biquote Economic Calendar aggregates scheduled macroeconomic announcements across **54 countries** with actual, forecast, previous, and revised figures over a rolling ~180-day window (90 days past, 90 days forward).

---

## 1. Dual-Feed Architecture & Normalization

The economic calendar combines two distinct sources into one normalized model:
1. **MetaTrader 5 (MQL5) Calendar Feed**: Covers the 22 major global economies. Event IDs are prefixed with `mql5:` (e.g. `mql5:840`).
2. **Extended Emerging Markets Feed**: Covers Turkey, Central & Eastern Europe, smaller Eurozone members, Southeast Asia, and Gulf economies.

Both feeds are mapped to the unified `CalendarEvent` model with identical field names, UTC timestamps, and unit descriptors.

---

## 2. Reading Numbers & Nuances

### Handling Null Values
- `actual`, `forecast`, `previous`, `revisedPrevious` will often be `null`.
- `null` strictly means **"Not published yet"** or **"Not applicable"** (e.g. bank holidays or events with no consensus estimate).
- **CRITICAL**: Never treat `null` as `0.0`. An interest rate release with `actual: null` is forthcoming; an interest rate of `0.0` is zero interest.

### Comparing Figures
- Evaluate market reaction by comparing `actual` against `forecast` (the consensus estimate), **NOT** against `previous`.
- If a statistical agency amended the prior release, `revisedPrevious` is populated and `revision` is incremented.

### Multipliers and Units
- `unit`: Specifies the suffix or measure (e.g. `"percent"`, `"job"`, `"currency"`, `"barrel"`).
- `multiplier`: Indicates scaling for human display (e.g. `"thousands"`, `"millions"`, `"billions"`).
  - *Example*: US Nonfarm Payrolls arrives with `actual: 152000` and `multiplier: "thousands"`.
  - *Display format*: Render as `152,000K` (or 152.0M). **Do not multiply `152000 * 1000` internally.**

### Time Modes (`timeMode`)
Macro releases have different timing guarantees:
- `"exact"`: The event will occur at the exact hour and minute specified in `time`.
- `"date"`: The date is confirmed, but no exact release time is scheduled.
- `"notime"`: Tentative intraday release.
- `"tentative"`: The release date and time are subject to change.
- **Rule**: If `timeMode` is NOT `"exact"`, do not display the clock hours/minutes in the UI.

---

## 3. Recommended Filtering Strategy

Because 54 countries produce dozens of minor updates daily (e.g. 4-week Treasury bill yields), an unfiltered calendar can be noisy.

### Recommended Filters:
1. **High Impact Releases**: `?importance=high`
2. **Core Trading Economies**: `?countries=US,EU,GB,JP,TR`
3. **Specific Type**: `?type=indicator` (omits general bank holidays and political summits)
4. **Upcoming Releases**: Use `/api/calendar/upcoming?limit=20&importance=high` for widgets and status bars.
