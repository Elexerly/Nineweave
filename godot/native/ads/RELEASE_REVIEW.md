# Advertising release review — not approved for release

Reviewed 2026-11-17. The unsigned native SDK link is not evidence that real ad UX,
consent, reporting, age suitability, or App Review requirements are satisfied.

## Requirements and current gaps

Apple [2.5.18](https://developer.apple.com/app-store/review/guidelines/#software-requirements)
requires ads appropriate for the app's rating, access to targeting information inside
the app, clear identification, visible/easily usable dismissal, and the ability to
report inappropriate or age-inappropriate advertising. No real creative or reporting
flow has been verified on iPhone/iPad. Do not assume merely linking AdMob satisfies it.

Google documents [AdChoices reporting](https://support.google.com/google-ads/answer/7660847).
Verify the actual served Google interstitial has this accessible path. Test ads and
SDK version alone cannot establish every creative's behavior. Ad inspector is for
test-device diagnostics, not the user-facing reporting feature. Publisher
[Ad Review Center](https://support.google.com/admob/answer/7672109) is where the
operator can review/block/report an offending creative; users cannot access our account.

Current source has a native-only Options → Report ad local draft/copy screen. It
does not send reports and is not a complete delivery mechanism or compliance proof.
Follow-up requirements before shipping:
- Options and post-ad results: "Report last ad", with inappropriate content,
  age-inappropriate content, misleading ad, or cannot close categories.
- Present the exact report for consent before submitting. Collect a minimal ad
  response identifier, placement and time, plus optional user's explanation.
- Do not silently attach player email, device token, advertising identifier, or
  account/profile data. Do not upload screenshots without an explicit user action.
- Show delivery success only after actual acknowledgement; offer a retry/fallback
  when offline. A mail-only feature must handle no mail account, not silently fail.
- Owner triage into Ad Review Center, then block/report as appropriate. A player
  submitting a report does not itself guarantee the ad is blocked everywhere.

Poing5.1.0's native interstitial singleton provides `get_response_info(uid)`, and
our adapter captures only its response_id after the SDK showed callback, before
destruction. This remains session-only and does not log impressions or upload data.
The rest of the SDK dictionary is discarded.
Google documents [response IDs](https://developers.google.com/admob/ios/response-info)
for diagnostics and creative review. Reporting transport and retention need to be
implemented and disclosed before activation.

## Pacing and fairness

Google [interstitial guidance](https://support.google.com/admob/answer/6201362)
prohibits ads after every action and back-to-back ads. Use natural content breaks,
not app launch/exit, ongoing play, or delayed appearance after gameplay starts.
The existing one-result/one-boundary gate prevents duplicates and skips unavailable
ads, and now defaults to a 30-second minimum elapsed match and a 120-second interval after
the most recent ad attempt or dismissal/failure. These are conservative product safeguards, not policy-prescribed
thresholds. The clock is monotonic and injectable for tests, but counts intro/background/idle
time, not verified active engagement; cooldown is session-only. A normal match has
many actions; a rapid resignation or short failed match may not. The exact pacing
choice is a product decision; do not present an invented time threshold as Google's
required policy. Skipping an ad must never delay the next match waiting for fill.

Online tournaments remain separately disabled until bounded-hold fairness and
actual close/background behavior are agreed and tested. Never release readiness
while a native ad remains visible simply to satisfy a timeout.

## Native release acceptance evidence still needed

- iPhone and iPad, portrait and landscape: visible ad label, unobstructed close/
  skip/AdChoices; VoiceOver focus and adequately sized touch targets; no misleading
  overlays on SDK UI. Check safe areas, rotation, resumed/background apps.
- Age rating and ad-request max-content-rating/category controls consistent with
  actual audience; no fabricated child-status or consent configuration.
- No ad during match clocks, account flow, purchase/restore, initial launch, exit,
  or immediately after a prior ad. Verify no-fill and consent revocation paths.
- User reporting succeeds without developer tools; offline failure is honest;
  publisher can locate and act on a submitted report.
- Real StoreKit entitlement/restore suppresses ads, unknown remains ad-free, and
  purchase dismissal does not accidentally trigger an interstitial.
- Runtime UMP snapshot and privacy controls tested; no tracking claims until the
  complete SDK/data-use audit and App Privacy disclosures are finished.
