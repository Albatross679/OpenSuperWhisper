# Dashboard presentation checks

The cost chart uses one centered series when only reported or estimated charges are positive in the displayed range. When both categories contain positive charges, it keeps separate side-by-side series. Bar values are unchanged. The adaptive USD axis is unchanged.

All three charts use calendar-bucket midpoint ticks with daily dates, weekly start dates and month/year labels. Daily and Monthly sample at most four labels; Weekly labels every bucket, including every occupied week. Weekly labels use the short date, rotating vertically for more than six weeks instead of skipping dates. The scale includes complete boundary buckets and 32-point plot padding. Fixed four-point ticks stop above the text. All three charts reserve the same plot width, independent of their y-axis label widths. A bucket picker below the cost chart displays round-trip decimal dollar values and an explicit unknown-cost count, independent of bar height. This makes subpixel charges readable without enlarging their bars.

## Offline regression checks

Run `npm test` and `scripts/test_shortcuts.sh`. `test_usage_presentation.swift` compiles with the production store, aggregation and SwiftUI chart code, with assertions enabled. It tests reported-only, estimate-only, mixed, zero, unknown and empty fixtures across Daily/Weekly/Monthly and all/OpenRouter/Cloudflare/no-matching-provider filters. It checks exact values, separate series in disjoint buckets, endpoint ticks, complete weekly tick coverage, Sunday/Monday week boundaries and 23/25-hour DST days. Native screenshot review checks that count, minutes and cost bar edges align. Existing tests cover request accounting, cleanup/retries, privacy, count/minutes and repeatable root generation.

To render isolated native windows with synthetic metadata:

```sh
mkdir -p runs/presentation
swiftc -parse-as-library -o runs/presentation/probe \
  src/client/UsageMetrics.swift src/client/UsageDashboard.swift \
  scripts/test_usage_presentation.swift
runs/presentation/probe runs/presentation/test-profile
runs/presentation/probe runs/presentation/images reported daily 450
runs/presentation/probe runs/presentation/images reported monthly 800
runs/presentation/probe runs/presentation/images mixed monthly 450
```

Arguments are output directory, fixture, period, width, optional provider and optional range. For example, `reported weekly 450 all 90` checks longer weekly labels. Use a fresh output directory for new fixtures. The render clock is fixed at October 4, 2026. Synthetic daily charges are $0.022, $0.005, $0.000056 and $0.0006. Each request belongs to one of four synthetic dictations, not a copied user ledger. Mixed fixtures add separate estimated cleanup charges. Only the named isolated profile is written. These probes do not access recordings, credentials, installed app state or provider APIs.

## Native screenshot review

Reviewed count, minutes and cost charts at 800 and 450 points for all three periods. Date labels fit at both edges. Monthly reported-only and estimate-only bars occupy their full centered bucket; mixed positive bars remain separate blue/orange columns. The narrow daily picker shows `0.000056 USD` beside the much larger $0.022 charge without changing either bar's height. Zero, unknown, empty and provider-filtered probes were also inspected. The revised weekly view includes Sep 13 and Sep 27 and stops tick lines before the text. A 90-day narrow weekly probe confirms vertical labels remain legible. Native screenshots show identical count/minutes/cost bar edges at both widths. Firstmate accepted the uncrossed complete weekly labels and aligned monthly bars. A color-dependent raster assertion was removed as instructed; alignment verification is visual, not an automated raster assertion.

- [Monthly, 800 points](monthly.png)
- [Daily tiny charge, 450 points](daily-narrow.png)
- [Mixed categories, 450 points](mixed-narrow.png)
- [All weekly buckets, 450 points](weekly-narrow.png)

These are isolated production-view probes, not verification of the installed application. The existing installed-dashboard diagnosis remains the evidence for the original symptom. The installed dashboard was closed when this task resumed; no restart, recording action, installation or real-ledger write was performed.
