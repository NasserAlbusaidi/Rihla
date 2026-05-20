# Runbook

Operational responses for the first 30 days of public rollout. One paragraph
per tripwire. Updated when something fires and the response evolves.

Project: `rihla-safar` · Solo on-call.

## First Response — read this first when paged

1. Confirm the alert is real. Open the launch dashboard, look at the rolling
   1h window for the metric that fired. Page failures are common; user pain is
   not. If the metric is back inside threshold and stable for 15 min, ack and
   move on.
2. Check `git log origin/main..HEAD` and the most recent deploy. If something
   shipped in the last 24h, that is the prime suspect.
3. Decide rollout posture: hold (no promotion), halt (no new installs at this
   stage), or rollback (drop the active track). See "Rollback Procedures"
   below. Default on the first real alert is **halt**, not rollback.

## Tripwires

### T1 — Crash-free sessions drop below 99% (rolling 1h)

Symptom: Sentry "crash-free sessions" metric for the active Play track falls
under 99% for at least 1 hour. **First check:** open Sentry, sort by event
count, look at the top 3 issues from the last 1h. If one issue dominates
(>50% of events), it is almost always the cause. **Likely causes, ranked:**
(1) regression from the most recent build; (2) a previously-rare path now
common because rollout %% increased; (3) a Firebase SDK or platform behaviour
change (rare but happens with Android OS updates). **Mitigations:** if it is
the most recent build, halt the rollout in Play Console (pause Production
rollout %% or revert to previous build). If the issue is on a specific OS
version or device family, document it in `docs/REAL-DEVICE-QA.md` follow-ups
and consider whether to filter the affected `minSdk` segment for now.
**Rollback trigger:** crash-free under 99% for 2h+ AND root cause not
identified — rollback the active track to the previous build.

### T2 — Cloud Functions error rate above 5% (rolling 15m)

Symptom: Firebase Console → Functions → `joinGroupByInviteCode`,
`cleanupAnonUidArtifacts`, account-deletion cascade, or FCM token cleanup
shows >5% errors over 15 minutes. Note that `cleanupAnonUidArtifacts`
runs fire-and-forget after email-link recovery — failures land in Sentry
breadcrumbs rather than blocking the user, so watch the Sentry channel
for cleanup-callable errors specifically. **First check:** open
the Function's logs in the Firebase Console for the same window. Filter by
`severity=ERROR`. If errors share a code (`PERMISSION_DENIED`,
`FAILED_PRECONDITION`, `RESOURCE_EXHAUSTED`), that is the cluster.
**Likely causes, ranked:** (1) Firestore rules drift — local rules were
modified but production rules not redeployed; (2) Firestore composite index
missing for a query path; (3) App Check token rejection (older devices,
clock skew); (4) cold-start timeouts under bursty traffic. **Mitigations:**
for (1) and (2), `bash tool/check_firebase_prod_state.sh rihla-safar` will
diff rules and indexes against the repo — redeploy if drift is detected. For
(3), examine the error breakdown by App Check enforcement reason; if a
specific platform dominates, surface a clearer client-side error message
before next promotion. For (4), confirm Function memory + min-instances
config; consider `minInstances: 1` on the join callable if cold-starts are
the cluster. **Rollback trigger:** rate stays above 5% for 30+ min and the
cluster cannot be explained — halt rollout, do not promote further.

### T3 — Invite-join 4xx/5xx rate above 10% (rolling 15m)

Symptom: dashboard panel shows `joinGroupByInviteCode` non-2xx responses
exceed 10% of total invocations for 15 minutes. **First check:** filter the
Function logs by HTTP status code in the same window. **Likely causes,
ranked:** (1) a shared invite code went viral and 5 attempts/hour/UID rate
limit is firing — this is expected, watch for a follow-up cohort of users
who recover; (2) an invite code was deleted but is still being shared,
producing `not-found`; (3) App Check rejection cluster (see T2); (4)
malformed `memberIds` cluster, which means a writer somewhere is corrupting
group membership documents — investigate immediately. **Mitigations:** if
(1), no action needed unless support volume spikes (consider raising the
rate limit in `functions/src/callables/joinGroupByInviteCode.ts` if a
legitimate viral moment is happening). For (2)–(4), reproduce locally
against the emulator and patch. **Rollback trigger:** sustained >10% for
1h+ with no identified cause and active user complaints — halt rollout.

### T4 — Firebase Auth daily quota usage above 50%

Symptom: Firebase Console → Authentication → Usage shows anonymous auth
sign-ins approaching the per-day quota. **First check:** are the sign-ins
from real installs (matches Play Console install counts roughly) or
unexplained? Anonymous auth has no abuse protection by itself; if the
numbers don't match installs, you have abuse. **Likely causes, ranked:**
(1) genuine organic growth — celebrate, then request a quota raise from
Firebase support before hitting 80%; (2) a bot is hammering the app (rare
on mobile, possible if the app launches on simulators in a click-farm);
(3) a client bug is calling `ensureAnonymousSession()` in a loop. **Mitigations:**
for (1), request quota raise. For (2), enable App Check on Identity Toolkit
if not already enforced (Console option); add IP-level rate limiting via
Cloud Armor on the auth domain if available. For (3), grep for repeated
`ensureAnonymousSession()` calls in logs; if a client version is leaking,
release a hotfix and consider a min-version gate on the join callable.
**Rollback trigger:** quota will be exhausted in <2h and cause cannot be
controlled — halt rollout and consider temporary block on the offending
source.

### T5 — Cost alert ($5 / $20 / $50)

Symptom: Google Cloud Billing alert for project `rihla-safar` triggers.
**First check:** Cloud Billing → Reports → group by service. Usual top
spenders for a Firebase Flutter app: Cloud Functions invocations, Firestore
reads, Cloud Storage egress (n/a here, Storage SDK retired), Firebase
Hosting bandwidth, Identity Toolkit. **Likely causes, ranked:** (1) genuine
traffic exceeding expectations — confirm against active users and decide if
expected; (2) a Function is in a retry loop (look at Functions invocation
count vs error rate); (3) a client-side query is unbatched and burning
Firestore reads (look for read-heavy collections); (4) abuse — see T4.
**Mitigations:** for (2), the function's error-handling needs review — most
Firebase Functions retries are configurable in the function config. For
(3), profile the worst offenders with Firebase Performance Monitoring; add
`limit()` clauses or paginate. **Rollback trigger:** spend rate projects to
$200+/day with no offsetting user value — halt rollout, investigate the
cost driver, do not promote until controlled.

## Rollback Procedures

### Halt a rollout

Google Play Console → Release → target track (Open Test or Production) → set
rollout %% to 0 (Production) or pause new tester access (Open Test). Existing
installs continue to run; no new installs receive the build. This is the
default response to an unexplained tripwire.

### Roll back to previous build

Google Play Console → Production → Releases → select the previous release →
"Promote release". Existing installs do not automatically downgrade; new
installs receive the previous version. For a fast user-facing fix, this
buys you 24h while you push a hotfix.

### Rollback backend (Firestore rules / indexes / Functions)

Firestore rules versions are kept in the Console; redeploy a known-good
version. For Functions, redeploy the previous Git SHA:

```bash
git checkout <previous-sha> -- functions/
RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes RIHLA_FIREBASE_DEPLOY_APPROVED_SHA="$(git rev-parse HEAD)" bash tool/deploy_firebase_backend.sh rihla-safar
git checkout HEAD -- functions/
```

For indexes, Firestore keeps them additive — there is no fast rollback path.
Adding an index is safe; removing one is not. Treat index changes as one-way
doors.

### Emergency app shutdown

Worst case: pull the app from the Play Store (Production → "Unpublish").
This is destructive to installs — they will keep running but the listing
disappears. Reserve for legal/security emergencies only.

## Post-incident

After any rollback or halt: write a one-paragraph incident note appended to
this file under a `## Incidents` section (created when first one happens),
linking the Sentry issue, dashboard screenshot timestamp, and the fix
commit. Stale runbooks are worse than none — update the relevant tripwire
section if the response evolved.
