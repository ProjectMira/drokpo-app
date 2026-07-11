# Plan: Like/match notifications, message CTA from Likes, Discover button + profile-detail UX

Date: 2026-07-11. Spans **both repos**:
- App: `/Users/tashitsering/Desktop/Projects/drokpo-app` (SwiftUI, iOS)
- Backend: `/Users/tashitsering/Desktop/Projects/drokpo-backend` (FastAPI on Cloud Run + Firestore + Python Cloud Functions in `functions/main.py`)

Backend deploys automatically on push to `main` via `.github/workflows/deploy-backend.yml` (Cloud Run + `firebase deploy --only hosting,firestore,storage,functions`). App ships via TestFlight CI in drokpo-app.

---

## Feature 1 — Notification when someone likes you (and verify match notifications)

### Root-cause analysis (why the user got no notification)

The screenshot shows "Test Girl" under **Liked you** — i.e. a *received like*, **not a match** (a match only exists after both sides like). Current push pipeline (`drokpo-backend/functions/main.py`):

- `on_match_created` — fires on `matches/{matchId}` doc creation → "You made a new friend!" push. ✅ exists
- `on_message_created` — fires per message → "New message" push. ✅ exists
- **There is no trigger for a received like.** That's the gap: nothing fires when someone merely likes you.

Two secondary caveats to verify while testing (don't code around them yet, just check):
1. `on_match_created` only fires on **document creation**. If a `matches/{a_b}` doc already exists from earlier testing (status `active`), a re-like reports "matched" to the client but creates no doc → no push. During QA, delete stale match docs between runs.
2. Push delivery requires: APNs key uploaded in Firebase console, user granted notification permission (`PushService.enable()` runs from `SessionStore` when session becomes active), and `users/{uid}.fcmTokens` non-empty in Firestore. If QA still sees nothing, check Cloud Functions logs and that field first.

### 1a. Backend: new Cloud Function `on_swipe_created`

File: `drokpo-backend/functions/main.py`

Swipes are written by the FastAPI backend at `users/{fromUid}/swipes/{toUid}` with denormalized `action`, `fromUid`, `toUid` (see `backend/app/services/matching.py::_swipe_transaction`). Add:

```python
@firestore_fn.on_document_created(document="users/{uid}/swipes/{targetUid}")
def on_swipe_created(event: firestore_fn.Event) -> None:
    data = event.data.to_dict() or {}
    if data.get("action") not in ("like", "superlike"):
        return
    from_uid = data.get("fromUid") or event.params["uid"]
    to_uid = data.get("toUid") or event.params["targetUid"]

    db = firestore.client()

    # If this like completed a match, the match doc was written in the same
    # transaction; on_match_created already notifies both sides. Skip the
    # like push so the recipient doesn't get two notifications.
    match_id = "_".join(sorted([from_uid, to_uid]))
    if db.collection("matches").document(match_id).get().exists:
        return

    # Respect blocks in either direction (mirrors matching._either_blocked).
    refs = [
        db.collection("blocks").document(from_uid).collection("blockedUsers").document(to_uid),
        db.collection("blocks").document(to_uid).collection("blockedUsers").document(from_uid),
    ]
    if any(snap.exists for snap in db.get_all(refs)):
        return

    tokens = _tokens_for(db, [to_uid])
    _send(
        tokens,
        "Someone likes you!",
        "Open Drokpo to see who liked you.",
        {"type": "like"},
    )
```

Notes for the implementer:
- Do **not** put the liker's name in the notification — the whole point of the Likes tab is revealing who it is in-app; also avoids leaking names onto lock screens.
- No duplicate-push risk on re-swipe: `_swipe_transaction` uses `transaction.set()` on a fixed doc id (`users/{from}/swipes/{to}`), so a repeat like is an *update*, and `on_document_created` doesn't fire.
- Because swipe + match doc are committed atomically in one transaction, when the swipe trigger runs, the match doc (if any) is already readable — the skip check is race-free.
- Keep the payload `{"type": "like"}` — no `matchId` (there is none).

### 1b. Optional hardening (do it, it's small): prune dead FCM tokens

`_send` currently ignores results. Change it to accept the db + uid list and remove tokens whose send response failed with `UNREGISTERED`/`INVALID_ARGUMENT`:

```python
def _send(db, uid_tokens: dict[str, list[str]], title, body, data=None) -> None:
    tokens = [t for ts in uid_tokens.values() for t in ts]
    if not tokens:
        return
    resp = messaging.send_each_for_multicast(messaging.MulticastMessage(...))
    dead = {tokens[i] for i, r in enumerate(resp.responses)
            if r.exception is not None
            and getattr(getattr(r.exception, "code", None), "name", "") in ("NOT_FOUND", "INVALID_ARGUMENT")
            or "UNREGISTERED" in str(r.exception or "")}
    for uid, ts in uid_tokens.items():
        stale = [t for t in ts if t in dead]
        if stale:
            db.collection("users").document(uid).update({"fcmTokens": firestore.ArrayRemove(stale)})
```

If the error-classification plumbing gets fiddly, a simpler acceptable version: on any per-token exception, `ArrayRemove` that token. Update the two existing callers (`on_match_created`, `on_message_created`) to the new signature (have `_tokens_for` return `{uid: [tokens]}`). If this refactor threatens to balloon, ship 1a without it and leave a TODO — 1a is the user-facing fix.

### 1c. App: route the "like" push to the Likes tab

Currently every push tap lands on Chats (`MainTabView.selectChatsIfDeepLinked()`), which is wrong for a like push.

- `Drokpo/Core/DeepLinkRouter.swift` — no structural change needed; it already carries `pendingType` (`"like"` will flow through, `matchId` nil).
- `Drokpo/Features/MainTabView.swift` — replace `selectChatsIfDeepLinked` with type-aware routing:

```swift
private func routeDeepLink() {
    guard router.pendingType != nil || router.pendingMatchId != nil else { return }
    if router.pendingType == "like" {
        selection = .likes
        router.clear()          // Likes has no thread to open; consume here.
    } else {
        selection = .chats      // "match" / "message": ChatsView consumes the router.
    }
}
```

Call it from the existing `.onAppear` and add `.onChange(of: router.pendingType) { routeDeepLink() }` alongside the existing `.onChange(of: router.pendingMatchId)`. (Today only `pendingMatchId` is observed; a like push has nil matchId, so the type change must also trigger routing.)
- `Drokpo/Core/PushService.swift` — the guard `type != nil || matchId != nil` already lets `{"type": "like"}` through. No change.
- `LikesView` loads via `.task` on appear; it does **not** reload when re-selected. Add `.onChange` hook: when the view appears due to deep link the `.task` already ran once — so also refresh when the tab is selected. Simplest: in `LikesView`, add `.onReceive`-style reload — concretely, keep it simple: add `.task(id: <a refresh trigger>)` or just accept pull-to-refresh. **Minimum bar:** switching to the Likes tab from a like-push should show the new like; implement by reloading in `onAppear` (change `.task { await load() }` to also fire on subsequent appears — `.task` only runs once per identity, so add `.onAppear { Task { await load() } }` guarded by a `hasLoaded` flag debounce, or use `.task(id: direction)` plus an explicit reload when `router` consumed a like push).

### 1d. Firestore rules / indexes

No changes needed — Cloud Functions use the Admin SDK (bypass rules); no new queries need indexes.

---

## Feature 2 — "Send message" / "Like back" CTA when viewing a profile from Likes

### Backend: expose match state on swipe lists

`GET /api/swipes` and `/api/swipes/received` return entries with `otherUser` attached but nothing about whether you're already matched. The client needs this to decide between "Like back" and "Send message".

File: `drokpo-backend/backend/app/services/matching.py` — in `_attach_profiles` (or a sibling `_attach_match_state` called from `list_swipes`/`list_received`), batch-read match docs:

```python
def _attach_match_state(db, uid: str, swipes: list[dict]) -> list[dict]:
    refs = [db.collection("matches").document(_match_id(uid, s["uid"])) for s in swipes]
    snaps = db.get_all(refs) if refs else []
    status_by_id = {snap.id: (snap.to_dict() or {}).get("status") for snap in snaps if snap.exists}
    for s in swipes:
        mid = _match_id(uid, s["uid"])
        status = status_by_id.get(mid)
        s["matchId"] = mid if status == "active" else None
        s["matchStatus"] = status
    return swipes
```

Call it with the *caller's* uid in both `list_swipes(uid, ...)` and `list_received(uid, ...)` after `_attach_profiles`. (Note `db.get_all` returns snapshots in arbitrary order — key by `snap.id`, as above.)

Tests: extend `backend/tests/test_swipes.py` — received/given lists include `matchId` when an active match exists, `matchId: null` when unmatched or no match.

### App: enrich `ProfileDetailView` with a context-dependent action bar

**`Drokpo/Core/Models.swift`** — add to `SwipeEntry`:

```swift
var matchId: String?
var matchStatus: String?
var isMatched: Bool { matchId != nil }
```

**`Drokpo/Features/Shared/ProfileDetailView.swift`** — add an action context so the same view serves Likes, Chats, and Discover (Feature 4 reuses this):

```swift
enum ProfileDetailContext {
    case plain                                     // current behavior (Chats header, etc.)
    case likedYou(matchId: String?, onLikeBack: () async -> SwipeResult?)
    case discover(onLike: () -> Void, onPass: () -> Void)   // used by Feature 4
}
```

- Layout: keep the existing photo pager + info column, and **add missing fields** while in here: `occupation` (briefcase icon) and `education` (graduationcap icon) are in `FeedCard` but never rendered; also show `distanceKm` when present ("~12 km away"). Render `interests` as wrapping chips (simple `FlowLayout` or `LazyVGrid`) instead of one comma-joined line — this is the "see the profile in details and likes and all" ask.
- Bottom safe-area bar (`.safeAreaInset(edge: .bottom)`):
  - `likedYou` with `matchId == nil`: one prominent pink button **"Like back ♥"**. On tap → call `onLikeBack()`; if the result `isMatch`, flip the bar in place to **"Send message"** and show the existing match alert/overlay behavior.
  - `likedYou` with `matchId != nil` (already matched): prominent button **"Send message"**.
  - "Send message" action: `DeepLinkRouter.shared.handle(type: "message", matchId: matchId)`. The existing plumbing (`MainTabView.onChange` → Chats tab → `ChatsView.consumeDeepLink()` → `path = [matchId]` → `ChatThreadView`) opens the thread with zero new navigation code, and `ChatThreadView` already tolerates the match arriving late from the `ChatStore` listener. **This is the recommended mechanism — do not push `ChatThreadView` inside the Likes stack** (it works since `ChatStore` is injected on the whole `TabView`, but leaves the user in a chat under the Likes tab; tab-switching matches iOS mental models and the push-tap behavior).
  - `plain`: no bar (unchanged).

**`Drokpo/Features/Likes/LikesView.swift`**:
- Pass context: `ProfileDetailView(card: card, context: .likedYou(matchId: entry.matchId, onLikeBack: { await likeBack(card) }))`. Refactor `likeBack` to return the `SwipeResult?` so the detail view can react; keep the existing list-row heart button behavior (it already removes the row and shows the match alert).
- For the **"You liked"** tab, entries that are matched can show a small "Matched" pill in the row (nice-to-have; skip if time-boxed).
- Improve the match alert: add a **"Say hi"** button that calls `DeepLinkRouter.shared.handle(type: "message", matchId: result.matchId)` (keep "Later" as cancel). Requires `likeBack` to keep the returned `matchId` alongside the name — store `matched: (name: String, matchId: String?)?` instead of just `matchedName`.

---

## Feature 3 — Proportional like/dislike buttons on Discover

Current state (`Drokpo/Features/Feed/FeedView.swift::actionButton`): two 60×60 circles, `HStack(spacing: 40)`, X is red, heart is **green**. Issues: fixed size ignores device width; green heart is inconsistent with the pink heart used everywhere else (Likes tab, tab bar); visual weight of the glyphs differs.

Changes in `FeedView`:
- Size buttons **proportionally to screen width**: `let d = min(72, UIScreen.main.bounds.width * 0.17)` (or read width via `containerRelativeFrame`/`GeometryReader` if preferred — don't wrap the whole deck in a new GeometryReader; a static `UIScreen` read is fine here). Both buttons identical diameter `d`, icon `.system(size: d * 0.42, weight: .bold)`.
- Even placement: `HStack { Spacer(); passButton; Spacer(); likeButton; Spacer() }` or fixed spacing `d * 0.6` — pick one, but both buttons must be the same size and symmetric about center.
- Color: pass = `.red` xmark, like = `.pink` heart (match the app's like color). Keep the circular `.background(Circle().fill(.background).shadow(radius: 4))` style.
- Add a subtle pressed scale (`.buttonStyle` with `scaleEffect(configuration.isPressed ? 0.9 : 1)`) — cheap polish, optional.

---

## Feature 4 — Tap a Discover card to expand into full profile detail

### Interaction design

`CardView` already uses left/right invisible tap zones to page photos, so a whole-card tap gesture would conflict. Design:
- Keep the photo-paging tap zones on the **upper photo area only**.
- Make the **bottom info block** (name/age/region/bio overlay) tappable → expand. Also add an explicit chevron affordance (`chevron.up` or `info.circle` next to the name) so it's discoverable.

### Implementation

**`Drokpo/Features/Feed/CardView.swift`**:
- Add `var onExpand: (() -> Void)? = nil` parameter.
- Constrain the existing photo-tap `HStack` zones to end above the info block (e.g. put the two clear rectangles in a `VStack` with a spacer matching the info block height, or simpler: give the info `VStack` `.contentShape(Rectangle())` and `.onTapGesture { onExpand?() }` — SwiftUI hit-testing gives the topmost view the tap, and the info block is layered above the zones, so this works without resizing the zones. Verify with a quick manual test).
- Add the chevron affordance in the name row.

**`Drokpo/Features/Feed/FeedView.swift`**:
- `@State private var expandedCard: FeedCard?` on `FeedView`.
- Thread `onExpand` through `SwipeableCard` → `CardView` (only meaningful for the top card; pass `nil`/no-op for background cards, same as the drag gesture's `isTop` gating).
- Present: `.sheet(item: $expandedCard) { card in NavigationStack { ProfileDetailView(card: card, context: .discover(...)) } }` — a sheet with `.presentationDetents([.large])` and a visible drag indicator. (Sheet over fullScreenCover so swipe-down-to-dismiss comes free and the deck context is preserved.)
- `.discover` context action bar: the same proportional pass/like buttons from Feature 3 (extract `actionButton` into a small shared component, e.g. `Drokpo/Features/Shared/SwipeActionButtons.swift`, so Discover deck and detail sheet share it). Actions: `onLike` / `onPass` set `expandedCard = nil` then call `model.swipe(card, action:)`. If the swipe produces a match, the existing `MatchOverlay` in `FeedView` appears (model.matchedCard is already observed there) — verify the overlay shows after the sheet dismisses (dismiss first, then swipe, as ordered above).
- The detail view for discover shows **everything** the card has: all photos (pager), occupation, education, languages, interests chips, socials, bio, distance — same enriched `ProfileDetailView` from Feature 2.

---

## Suggested commit/PR breakdown (in order)

**drokpo-backend** (one PR, deploys on merge to main):
1. `functions/main.py`: `on_swipe_created` like notification (+ token pruning if it stays small).
2. `services/matching.py`: `matchId`/`matchStatus` on swipe list responses + tests in `tests/test_swipes.py`. Run `cd backend && pytest`.

**drokpo-app** (one PR):
3. `Models.swift` `SwipeEntry` fields; `MainTabView`/`DeepLinkRouter` like-push routing; `LikesView` reload-on-appear.
4. `ProfileDetailView` context + enriched fields + action bar; `LikesView` context wiring + "Say hi" alert.
5. `FeedView` proportional buttons (+ shared `SwipeActionButtons`).
6. Card-tap expansion (`CardView.onExpand`, `FeedView` sheet with `.discover` context).

Build check after each app step: `xcodebuild -project Drokpo.xcodeproj -scheme Drokpo -destination 'generic/platform=iOS Simulator' build` (or the repo's `ci/` script if one exists).

## QA script (two TestFlight/simulator accounts, A and B)

1. Fresh state: delete any `matches/{A_B}` doc and both users' `users/*/swipes/*` docs for the pair (Firebase console) — stale docs from earlier testing suppress creation-triggered pushes.
2. B likes A → **A gets "Someone likes you!" push**; tapping it opens the app on the **Likes tab** and the like is visible without pull-to-refresh.
3. A opens Test-profile from Liked you → detail shows occupation/education/interests chips → taps **Like back** → match: overlay/alert with **Say hi** → lands in the chat thread. **Both A and B get the match push.**
4. B sends a message → A gets message push → tap opens the thread (existing behavior, regression check).
5. Discover: buttons equal-sized, pink heart / red X, symmetric; tap card info → sheet with full profile; Like from sheet → sheet dismisses, match overlay if mutual; Pass from sheet → next card.
6. Block edge: B blocks A, A's like must produce **no** push to B (function's block check).
7. If any push fails to arrive: check Functions logs in Firebase console, confirm `users/{uid}.fcmTokens` non-empty, notification permission granted, APNs key present (Admin key DFDRX9AW9K roster — see TestFlight memory).

## Explicit non-goals

- No unlike/undo, no superlike UI, no paywall gating of Liked-you, no Android.
- No change to Firestore rules or indexes (none needed).
- No renaming of existing push types; `"like"` is the only new type.
