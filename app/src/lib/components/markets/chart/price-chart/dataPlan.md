# Price Chart & Realtime Data Plan

> Architecture decision record for how HighPotential sources, stores, and streams
> market price data (OHLC) and, by extension, user-specific position/stake data.
> Written so implementation can proceed later with the same depth and rigor as the
> design discussion. Read this top-to-bottom before touching the data layer.

---

## 0. Guiding principles (the constraints every decision is measured against)

1. **Local-first / db-less by default.** The chain is the source of truth. A database
   is only introduced for data that is genuinely (a) market-wide / multi-user and
   (b) historical / time-series / aggregate — i.e. not cheaply reconstructable from a
   single contract read.
2. **Deployment-target portability.** The app is a SvelteKit application that must run
   unchanged across **Vercel/Netlify (serverless)** and **IPFS via `@sveltejs/adapter-static`**.
   IPFS = fully static, **no server at runtime**. Therefore any realtime mechanism must
   be **client-side** (browser → endpoint), never reliant on a SvelteKit server process.
3. **No per-trade tax on the hot path.** Nothing decorative (charts, bookkeeping) may add
   gas cost to swaps or risk reverting a user trade.
4. **Security without UX cost.** Minimize exposed secrets; degrade gracefully; never block
   a trade on a charting/data concern.

### Why not embed a WebSocket server in SvelteKit
SvelteKit has **no built-in WebSocket support** in its request handlers. An in-process WS
would force `@sveltejs/adapter-node` (killing serverless + static/IPFS deploys), couple the
realtime layer to the SSR event loop, and drop all sockets on every web redeploy. So realtime
is done **client-side via Viem**, with an optional standalone relay only as a future scaling step.

---

## 1. Data classes (decide architecture per class, never globally)

| Data class | Source of truth | Realtime mechanism | DB? |
|---|---|---|---|
| **Market OHLC / prices** (this doc's focus) | On-chain swap events | TigerData history + client-side Viem WS forming bar | Yes — TigerData (Timescale) |
| **Market-wide metrics**: ePBR (expected PBR), EST, PPM/PBR time-series | On-chain events | Ponder → TigerData | Yes — TigerData |
| **User positions** (AdvancedTrade) — `PositionManager` | On-chain contract storage | Client-side Viem WS on contract events | No |
| **User stakes** — `StakeManager` / `VaultManager` | On-chain contract storage | Client-side Viem WS on contract events | No |
| **User PnL aggregates** (cumulative realized PnL, counts, volume) | On-chain storage (fixed O(1) slots) | Viem WS on contract events | No |
| **User PnL time-series / deep history** | On-chain **event log** | `getLogs` reconstruction (index into Ponder/Timescale only if it must be deep/paginated/fast) | Only if forced |

**Rule:** user-specific, session-scoped state → read chain directly (db-less). Market-wide,
historical, aggregate → Ponder → TigerData.

---

## 2. Market OHLC architecture (PRIMARY SCOPE OF THIS DOC)

Industry-standard pattern: **indexer for canonical history + live socket for the forming bar.**

### Pipeline
1. **Ponder** subscribes to each market's swap events, constructs OHLC, writes the
   **base granularity** (raw swaps or 1m candles) into a Timescale **hypertable**.
2. **TigerData (TimescaleDB)** stores history cheaply; higher intervals (5m/1h/1d) are
   **continuous aggregates** (materialized views) rolled up from the base table — do NOT
   store each interval separately.
3. **UI on market select**: fetch historical OHLC for the active interval / visible range
   over HTTP from TigerData. Lazy-load / paginate older bars on scroll-back.
4. **UI live tick**: a **single client-side Viem `webSocket()`** subscription to the target
   market's swap events. Bucket incoming ticks into the **forming (current) bar** for the
   active interval. One subscription serves all intervals — switching timeframe only
   re-buckets the same stream + re-fetches history (no new socket).
5. **Bar close**: the client **finalizes its own bar from the events it already has** and
   treats it as authoritative for display **immediately** (zero round trip). TigerData is a
   **periodic/triggered reconciliation backstop**, NOT a per-close blocking call.

### Reconciliation model (critical — do not get this wrong)
- Do **not** re-fetch TigerData on every candle close. Pipeline lag (block → Ponder →
  base row → continuous-aggregate refresh) means the canonical bar is not ready the instant
  the interval closes; depending on it causes stalls/flicker.
- Reconcile **on: interval/range change, WS reconnect, and a low-frequency timer.**
- Reconciliation repairs **drift** (events missed during disconnects) and **reorgs**
  (a client-built bar may include a swap that later reorgs out). TigerData indexed with a
  confirmation/finality depth is the corrector.

### Mental model to lock in
> **TigerData = canonical/finalized history. Client-aggregated events = the live forming bar,
> authoritative on sight. Reconciliation = a periodic repair pass for drift + reorgs, not a
> per-close dependency.**

---

## 3. Robustness checklist (the edge cases that separate demo from production)

1. **Reconnect backfill.** On WS reconnect, `getLogs` from `lastSeenBlock → head` to recover
   swaps missed during the gap, THEN resume live aggregation. Without this the forming bar is
   silently wrong after any blip.
2. **History ↔ live seam.** Track the exact boundary (timestamp + block) where TigerData
   history ends and client aggregation begins. Fetch history up to T, start live from T.
   Guard against **double-counting the boundary candle** (classic off-by-one / overlap).
3. **Reorg handling.** Choose a confirmation depth for "final" in TigerData; keep client
   provisional bars correctable. Base reorgs are rare/shallow but non-zero.
4. **Doppler phase-awareness (carries through the WHOLE pipeline).**
   - Pre-migration (bootstrapping): price source is the **Doppler bonding-curve / hook**
     contract's buy/sell events.
   - Post-migration: source is the **Uniswap V4 singleton `PoolManager` `Swap` event**
     (filtered by this market's `poolId`, carries `sqrtPriceX96` + `tick`).
   - **Ponder must index both phases**; the **WS subscription must switch source at migration**,
     or a freshly-graduated market's chart goes flat exactly when it gets interesting.
5. **Price derivation consistency.** `sqrtPriceX96` → display price needs token ordering +
   decimals. Derive identically in Ponder and the client so DB bars and live bars agree to the
   same precision (mismatch shows as a jump at the seam).
6. **Many-markets surfaces ≠ active chart.** Do NOT open per-pool WS subscriptions for the
   fixtures marquee / market lists / watchlists (300+ markets → blows past provider limits/cost).
   For breadth surfaces, **poll one aggregated TigerData endpoint** (one read returns N latest
   prices). WS-to-chain is for the **single active chart** only.

---

## 4. Client implementation notes (SvelteKit / Svelte 5)

- **Pure client-side.** No `+server.ts`, no `lib/server/`, no `hooks.server.ts`, no custom
  adapter. Just browser code. This is what keeps it portable to IPFS static.
- **SSR / prerender guard.** Only open the socket in the browser — use `onMount` / `$effect`
  (don't run during SSR) or gate on SvelteKit's `browser` flag. During an IPFS build the
  prerender pass runs once server-side (no `WebSocket` global) — must not connect there.
- **State home.** Follow the existing reactive pattern in `src/lib/state/*.svelte.ts`
  (mirrors `wallet.svelte.ts` `setBalance()` / `network.svelte.ts` chain selection). Map
  `network.id` → viem chain at the boundary. Live ticks push into reactive `$state`; the
  chart (lightweight-charts) consumes via `update()` (forming bar) vs `setData()` (history load).
- **Viem transport.** `webSocket()` transport multiplexes multiple subscriptions over ONE
  socket. Confirm the RPC provider supports `eth_subscribe` for logs (most do — Alchemy/
  QuickNode/Base); if not, viem silently falls back to polling.
- **RPC key exposure.** Client-direct ships the `wss://...<API_KEY>` to the browser. Mitigate
  with provider-side domain/referrer allowlists or a rate-limited client-only key. Note
  referrer locking is fuzzy on public IPFS gateways (many domains) — a method-allowlisted,
  rate-limited key may be more realistic.

---

## 5. Rejected / deferred alternatives (with reasons — don't relitigate without new info)

- **On-chain `OHLC.sol` (store candles on-chain, update per swap via inter-contract call).**
  REJECTED. Storage has no capacity ceiling (2²⁵⁶ keyspace) so "space" isn't the limit — gas +
  state bloat is. ~7.9M minute slots/market/15yr × 300+ markets ≈ billions of slots. Adds a
  permanent per-swap `SSTORE` tax (~20k+ gas cold vs ~1.5–2k for a `LOG`) that the **paymaster
  sponsors forever**, bloats Base state (future state-rent risk), couples charting to the
  safety-critical swap path (must never revert a trade), and is **redundant**: the V4 `Swap`
  event already emits the same data for ~10× less and without state bloat. Writes are also
  event-driven (only on trades), so it's a sparse grid that still needs client-side flat-candle
  reconstruction. Contrast with `Matchweeks.sol`, which works on-chain precisely because it is
  **bounded + low-frequency** (38/season, oracle-refreshed) — OHLC is the opposite profile.
  - Only defensible on-chain variant: a **fixed-size ring buffer** of the last N candles
    (caps storage), but still pays the per-swap tax and is obtainable from events via `getLogs`
    anyway — so still not worth it.
- **Ponder → Supabase realtime (instead of the WS-to-chain hybrid).** DEFERRED. It is
  **slower** for the live tick (inserts the full indexer pipeline in front of the price update;
  chain events reach the client before Ponder even sees them), and it **pressures storage**:
  Supabase Realtime reads its own Postgres WAL, so you'd either run **two DBs** (TigerData +
  Supabase, redundant/2 sources of truth) or **drop Timescale** (lose continuous aggregates).
  Its only real advantage is managed fan-out, which doesn't pay off until high concurrency on
  hot markets.
- **Custom WebSocket server on Railway (client-facing fan-out).** DEFERRED, not required.
  Becomes worth it only when many concurrent users watch the same hot markets and per-client
  RPC subscriptions hit provider limits/cost. If/when needed, prefer a **single push relay**
  (Postgres `LISTEN/NOTIFY` → SSE/WS, fed by the Ponder/TigerData you already run) over adopting
  Supabase — it keeps storage on Timescale and adds no new vendor. NOTE: this is distinct from
  the existing `relay/` service (a Fastify static-IP HTTP egress proxy for StatsPerform/Opta
  ingestion — not client-facing, not WS).

---

## 6. Hosting facts (constants vs differentiators)

- **Ponder MUST be hosted on a persistent process** (Railway / Fly / Render / VM) in EVERY
  architecture — it is long-running and stateful, not serverless-friendly. This is a **constant**,
  true even in the "db-less for user data" world, because it populates TigerData for OHLC history.
- The **push layer** is the differentiator: WS-to-chain needs **no extra infra** (the RPC
  provider is the fan-out); Supabase Realtime is **managed by Supabase**; a self-hosted
  `LISTEN/NOTIFY` relay is the only option that needs Railway.
- All push options work from an IPFS static client (all are client-side WS/HTTP), so IPFS
  compatibility is not the differentiator — but WS-to-chain is the only one that keeps
  "chain is source of truth" and adds zero vendors.

---

## 7. Prerequisite for the user-data side (related, not this doc's primary scope)

Realtime user data (positions/stakes) reuses the same client-side Viem WS mechanism:
1. On sign-in: one `eth_call` to `HPSmartWallet.accountSet()` → discover `positionManager` +
   `vaultManager` addresses; cache in session state.
2. Hydrate current state with a one-time view read (`eth_call` / `multicall`).
3. Subscribe (one multiplexed WS) to both contracts' **events** for live deltas; push into
   reactive state. On reconnect, `getLogs`-backfill from last seen block.
4. **Hard requirement:** `PositionManager` / `StakeManager` must **emit an event on every
   state transition** (pending → open → closed, stake updates). A contract that only mutates
   storage with no event is invisible to a WS subscription. Mirror the `HPSmartWallet`
   discipline (`AccountSetUpdated`, etc.).
5. Keep storage to **live state + scalar PnL aggregates** (O(1) slots). Reconstruct the PnL
   **time-series from the event log** (`getLogs`); do not store a growing history array on-chain.

> Reminder: an Ethereum WS subscription can only target **events (logs)** and **new block
> heads** — there is NO subscription for "this storage slot/struct changed." Events are the
> trigger; view functions are the read. This is why event emission is non-negotiable.
