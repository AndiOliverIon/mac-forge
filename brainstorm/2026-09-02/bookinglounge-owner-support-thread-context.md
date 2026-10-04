# BookingLounge owner-support threads — context for Mac Forge scripting

Date recorded: 2026-10-02  
BookingLounge release: 1.7.5 (build 26)  
BookingLounge repository: `/Users/oliver/projects/bookinglounge`

## Why this note exists

BookingLounge now has the owner side of an in-app conversation with BookingLounge Support. The iOS app, API, SQL schema, and owner push notification path are shipped. There is intentionally no support/operator UI. Oliver is the only support operator for now, so the next work belongs in `mac-forge` as small operator scripts.

The first support operator script now lives at `scripts/vps1/bookinglounge-support.sh`, with the aliases `bl-support` and `bls`. It provides the safe command-line workflow in Mac Forge to find owner conversations, read their messages and diagnostics, send a support reply through the BookingLounge API, and explicitly change an active thread's state. Do not build a second app or a web support portal unless Oliver changes the scope.

## What is already implemented

The feature was introduced by these BookingLounge commits and is included in the 1.7.5 release on `main`:

- `03e45d8` — owner support conversations across iOS, API, SQL, and APNs
- `ad2f573` — maximum three unanswered owner messages
- `0fa7d0c` — review fixes and navigation/UI hardening
- `9157e60` — app version and build captured and shown with owner messages
- `ebc6d05` — final owner dashboard card polish

The production backend and the `2026-09-30-OwnerSupportThreads` migration are deployed. The API health check now refuses readiness if the owner-support tables or migration are missing.

### Owner experience

- The final card on the owner dashboard opens the support conversation.
- The owner can send messages of 1–4000 UTF-16 characters.
- An owner can send up to three consecutive messages while waiting for Support. This deliberately allows a thought to be split across a few messages without enabling spam.
- The fourth unanswered message is rejected by the server with HTTP `409`, code `supportReplyPending`.
- Any support reply resets that allowance, so the owner can send up to three more messages.
- The app can refresh manually and automatically refreshes after receiving a `supportReply` push notification.
- Each owner-authored message records `ContextScreen`, `AppVersion`, and `AppBuild`. The version/build is displayed in the conversation so Support can see which app version produced the report.
- Static copy is localized in English and Romanian.

There is no equivalent card or conversation in client mode. This is an owner-only feature.

## Data model and state rules

Migration: `Backend/database/sqlserver/migrations/2026-09-30-OwnerSupportThreads.sql`

### `dbo.SupportThread`

- `Id` — thread UUID
- `OwnerProfileId` — owning business owner
- `Status` — `pending`, `engaged`, or `closed`
- `ClosedAt` — required only for `closed`
- `CreatedAt`, `UpdatedAt`
- A filtered unique index allows only one active thread (`ClosedAt IS NULL`) per owner.

With BookingLounge's current one-owner/one-shop model, this is effectively one active support conversation per shop owner.

### `dbo.SupportMessage`

- `Id`, `ThreadId`, `OwnerProfileId`
- `SequenceNumber` — identity value used as the authoritative conversation order
- `Sender` — `owner` or `support`
- `Body` — nonblank, maximum 4000 characters
- `ContextScreen`, `AppVersion`, `AppBuild` — normally populated only for owner messages
- `CreatedAt`, `ReadAt`

Important semantics:

- An owner message sets the thread to `pending`.
- A support reply sets it to `engaged`.
- The three-message limit counts owner messages after the latest support message.
- When the owner fetches the active thread, all unread support messages receive `ReadAt = SYSUTCDATETIME()`.
- The backend exposes a support-side read endpoint. The initial Mac Forge script does not mark messages read automatically; it treats the unanswered count as the primary queue signal.
- The schema supports `closed`, but the application currently has no close operation or close endpoint. Active-thread fetches ignore closed threads.

## Existing backend interfaces

### Owner side

The iOS app uses the authenticated BookingLounge RPC operations:

- `fetchOwnerSupportThread`
- `sendOwnerSupportMessage`

Relevant implementation files:

- `Backend/BookingLounge.Api/Services/BookingLoungeRpcHandlers.cs`
- `Backend/BookingLounge.Api/Services/BookingLoungeSqlStore.Support.cs`
- `BookingLounge/BookingLounge/Core/DataContract/Support/BLSupportDataContract.swift`
- `BookingLounge/BookingLounge/Features/Owner/OwnerSupportView.swift`

### Support automation endpoints

The backend exposes authenticated support automation operations for listing active threads, showing one active thread, marking owner messages read, and replying:

```text
GET  /v1/support/threads
GET  /v1/support/threads/{threadId}
POST /v1/support/threads/{threadId}/read
POST /v1/support/threads/{threadId}/messages
```

The initial Mac Forge script uses database reads because it also needs owner/shop navigation and closed history. It uses the protected reply endpoint for writes that must invoke application behavior.

Operational check on 2026-10-04: the development endpoint authenticates successfully and is ready for script testing. Production database browsing works, but the production service currently returns `404` for the support route and its environment file has no `BookingLounge__SupportAutomation__Token` key. Production replies therefore remain unavailable until the BookingLounge support-operator endpoint commits are deployed and a production token is configured; the script fails closed in that situation.

Support replies already have a purpose-built automation endpoint:

```text
POST /v1/support/threads/{threadId}/messages
Authorization: Bearer <support-automation-token>
Content-Type: application/json

{"body":"Reply text"}
```

Production URL:

```text
https://api.bookinglounge.tnisoft.ro/v1/support/threads/{threadId}/messages
```

Development URL, after forwarding the private development API port:

```text
http://localhost:5081/v1/support/threads/{threadId}/messages
```

The endpoint validates the bearer token, rejects blank or overlong messages, appends a `support` message transactionally, changes the thread to `engaged`, and sends an APNs notification to the owner's registered devices. Its successful response contains `threadID`, `messageID`, and `createdAt`.

The token is configured only in the ignored server environment files:

- production: `/srv/tnisoft/bookinglounge-api/shared/bookinglounge-api-prod.env`
- development: `/srv/tnisoft/bookinglounge-api/shared/bookinglounge-api-dev.env`
- variable: `BookingLounge__SupportAutomation__Token`

Never copy this token into a tracked file, echo it, include it in command history, or expose it in logs. A Mac Forge implementation must load it from an ignored secret source or retrieve it securely from `vps1` at runtime without printing it.

### Push behavior

Sending through the endpoint invokes `BookingPushNotifier.NotifyOwnerSupportReplyAsync`. The notification payload contains:

- notification kind `supportReply`
- audience `owner`
- support thread ID
- shop ID and shop identifier

The iOS notification router opens/refreshes the owner conversation. This is why a Mac Forge reply script must call the API endpoint rather than inserting a support message directly in SQL.

There is currently no notification from an owner message to Oliver/Support. Discovery is therefore by listing or polling the database until a separate operator notification is intentionally added.

## How Mac Forge should reach the BookingLounge database

Use the existing Mac Forge VPS1 database layer; do not add an ad-hoc connection string or read secrets from the BookingLounge repository.

Relevant Mac Forge files:

- `scripts/vps1/vps1.sh` — shared connection, tunnel, SQL, SSH, and safety helpers
- `scripts/vps1/vps1-sql-tunnel.sh` — forwards local port `14333` to private VPS1 SQL at `127.0.0.1:1433`
- `config-local/local-store.json` — ignored secret store containing the generic `VPS1` connection and the distinct `BookingLounge Production (VPS1)` and `BookingLounge Development (VPS1)` profiles
- `dotfiles/aliases-vps1` — existing `v1-sql-tunnel-*` operator aliases

A new Bash script should select the environment-specific profile, source `scripts/vps1/vps1.sh`, require `sqlcmd`, call `vps1_load_connection`, and execute queries through `vps1_sqlcmd`:

```bash
VPS1_CONNECTION_NAME="BookingLounge Production (VPS1)"
source "$repo_root/scripts/vps1/vps1.sh"
vps1_require_cmd sqlcmd
vps1_load_connection
vps1_sqlcmd -b -d bookinglounge ...
```

Use `BookingLounge Development (VPS1)` with `bookinglounge-dev` for development. Both profiles use the established private VPS1 tunnel endpoint but keep the credentials and target database explicit. `vps1_load_connection` reads the selected profile without printing its credentials and automatically raises the SQL tunnel when the configured local endpoint is unavailable.

Database names:

- production: `bookinglounge`
- development: `bookinglounge-dev`

The SQL Server is private and must remain private. Do not make port 1433 public. Do not hardcode the server, username, or password; do not print the values loaded from `config-local/local-store.json`.

For production data safety:

- Listing threads and displaying a conversation should use read-only `SELECT` queries.
- Sending a normal support reply should use the protected API endpoint, not direct SQL.
- A routine API reply is an application operation and does not require a database snapshot.
- Any direct SQL mutation, close/reopen feature, repair, cleanup, migration, or backfill must be called out before execution. Create or verify a fresh production snapshot first when there is meaningful risk. VPS1 snapshots live in `/srv/tnisoft/mssql/snapshots`.

## Implemented Mac Forge operator workflow

Run `bl-support` or `bls` for the interactive workflow. It behaves as a small drill-down browser: select development or production, select an owner/shop that currently has an open thread, then work with that conversation. Every deeper screen provides explicit navigation back to owners or environments.

The owner list never shows closed threads. Because the data model permits only one open thread per owner, selecting an owner opens that conversation directly without an unnecessary thread-selection level. The default conversation view shows at most the three owner messages sent since the latest support reply. Messages are rendered as wrapped, numbered cards with distinct owner/support labels and terminal colors; `NO_COLOR` disables color without removing the visual structure. Database text is stripped of C0 and C1 terminal control characters before rendering while intentional tabs, line breaks, Unicode, and emoji remain intact. Conversation actions use a full-screen FZF layout with the messages in a dedicated scrollable preview, so small terminals do not push content into inaccessible scrollback. Page Up/Page Down or Ctrl-U/Ctrl-D scroll the message pane. Commands occupy one numbered line beneath the preview (`1 Reply`, `2 Close`, and so on) and are invoked directly with their number keys. `Show entire thread history` reveals every message in the current thread using the same scrollable layout and numbered command bar.

Interactive replies use a multiline composer. Return starts another line; `/send` finishes the draft and opens the existing reply preview and confirmation, `/undo` removes the previous line, and `/cancel` discards the draft and returns to the conversation. Prefix a command with another slash when it must be sent literally, such as `//send`. Declining the final confirmation, exceeding the reply-size limit, encountering concurrent owner activity, or receiving a transient API/transport failure keeps the draft available through the next `Reply` action. The message sequence from the displayed conversation remains the reply baseline while the operator composes; unseen activity aborts the send and refreshes the conversation. Scripted multiline replies continue to use `--file` or `--stdin`.

Choosing `2 Close` opens a compact closure screen that identifies the current state and explains the result. `Pending` and `Engaged` remain message-driven: an owner message sets `Pending`, while a support reply sets `Engaged`. Closing is the only manual state transition. It is applied only after environment-specific confirmation and only when the current status and latest message sequence still match what the operator reviewed; concurrent activity aborts closure and refreshes the conversation.

The same tool also supports explicit commands:

```bash
bls list --env development --status pending
bls owners --env production
bls threads --env production --owner <owner-guid|email|shop-identifier>
bls show --env production <thread-guid>
bls reply --env development <thread-guid> [--file path|--stdin]
bls state --env development <thread-guid> closed
```

The explicit `reply` and `state` write commands first print the compact current conversation and use that displayed status/message sequence as their concurrency baseline. A change before confirmation aborts the write rather than acting over unseen owner activity.

Implemented capabilities:

1. **List active conversations**
   - Default to actionable/pending threads, newest activity first.
   - Show thread ID, status, updated time, owner name/email, shop name/identifier, last sender, and number of consecutive owner messages awaiting a reply.
   - Allow choosing production or development explicitly; make the selected environment obvious before any write.

2. **Show one conversation**
   - Print messages in `SequenceNumber` order.
   - Label `owner` and `support` clearly.
   - Show timestamps, context screen, and owner app version/build when present.
   - For support replies, show whether/when the owner read them from `ReadAt`.

3. **Reply to one active conversation**
   - Accept a thread UUID and message text, preferably with an interactive prompt or file/stdin option that avoids fragile shell quoting.
   - Show the destination owner/shop and ask for confirmation before the production request.
   - Call the existing support automation endpoint with the correct environment token.
   - Never log the bearer token.
   - On success, show the returned message ID/time and then refresh the conversation from SQL.

4. **Close one active thread**
   - Supports only `closed`; `pending` and `engaged` are set by owner and support messages.
   - Shows the exact environment, owner, shop, thread, and transition before changing anything.
   - Development requires `y`; production requires typing `production`.
   - Refuses stale closure when the status or latest message sequence changed after display.
   - This is currently a row-scoped SQL transaction because the API has no state endpoint. It is deliberate short-term technical debt; replace it with an authenticated backend state endpoint when the workflow stabilizes.

5. **Optional watch/poll mode**
   - Poll read-only for newly pending owner messages because no inbound operator notification exists.
   - Add this only when Oliver explicitly asks; do not create a daemon or scheduler by assumption.

Closing is never silent: the script presents the target and applies the same environment-specific write confirmation as replies. Closing makes the thread historical; the owner's next message creates a new active thread. The cleaner long-term implementation remains a dedicated authenticated backend state endpoint, followed by changing the Mac Forge command to call it.

## Useful joins for operator queries

Thread identity and owner/shop context come from:

```sql
FROM dbo.SupportThread AS st
JOIN dbo.ownerprofiles AS o ON o.id = st.OwnerProfileId
JOIN dbo.shops AS s ON s.ownerprofileid = st.OwnerProfileId
LEFT JOIN dbo.SupportMessage AS sm ON sm.ThreadId = st.Id
```

Use `sm.SequenceNumber` for message order, not only `CreatedAt`. The count awaiting support is the number of `owner` messages whose sequence is greater than the maximum `support` sequence in that thread. An active queue should filter `st.ClosedAt IS NULL`; the most actionable state is `st.Status = N'pending'`.

Only show owner PII needed for the operator action. Never dump unrelated profile or booking data.

## Current gaps and deliberate non-goals

- No support-side UI exists or is planned for this phase.
- Support list/detail/read APIs exist for active threads, while safe SQL reads remain the short-term operator source for owner/shop navigation and closed history.
- No inbound alert to Support exists when an owner writes.
- No close/reopen backend endpoint exists. The initial script can close an active thread through a guarded row-scoped SQL transaction; reopening remains unsupported.
- No multi-operator assignment, notes, escalation, attachments, or ticket categories exist.
- The client role cannot create these support conversations.

Keep the script narrow around the workflow above. Do not add further server-side mutations in Mac Forge; move the existing state transition behind a BookingLounge backend endpoint when its semantics are settled.
