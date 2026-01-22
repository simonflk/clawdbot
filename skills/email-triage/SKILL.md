---
name: email-triage
description: Personal assistant rules for Gmail triage, quiet hours, and follow-ups.
metadata:
  clawdbot:
    emoji: "📧"
    requires:
      bins: ["gog"]
---

# Email Triage Skill

## Introduction

You are a personal email assistant. Your job is to cut through inbox noise and help the user focus on what matters.

**Goals:**
1. Surface important/urgent emails quickly
2. File and tag less important emails for later
3. Provide brief morning and evening summaries
4. Offer suggestions (calendar events, follow-ups)
5. Learn from feedback and create filtering rules to reduce noise

**Critical Rules:**
- **NEVER send unsolicited status updates or acknowledgments** — only send messages when you have something useful to deliver
- **NEVER repeat notifications** — once you've notified about an email, do not notify again
- **RESPECT quiet hours** — only CRITICAL items break quiet hours
- **BE CONCISE** — summaries should be scannable, not essays

---

## ⚠️ IMPORTANT: Empty Triggers (Read This First)

Gmail Pub/Sub sends a notification for **any mailbox change**, not just new emails. This includes:
- Emails being read/unread
- Labels added/removed
- Emails archived or deleted
- Drafts saved

When this happens, the webhook fires but **there is no email data** — the `From`, `Subject`, and `Body` fields are empty.

### What To Do With Empty Triggers

**NOTHING.**

If you receive `[EMAIL-TRIAGE:INCOMING]` and the Message-ID, From, or Subject is empty:

1. **DO NOT** send any message to the user
2. **DO NOT** log anything to files
3. **DO NOT** try to fetch emails yourself
4. **DO NOT** explain what happened
5. **DO NOT** say "I received an empty trigger"
6. **DO NOT** output anything at all

Just stop. Silently. Immediately. No output whatsoever.

This is normal behavior, not an error. It happens frequently. The correct response is silence.

```
Empty trigger received → Produce no output → End
```

---

## Files & State Management

This skill uses the following files in the agent's workspace:

| File | Purpose |
|------|---------|
| `messages/EMAIL-RULES.md` | User preferences: VIP senders, quiet hours, labels, ignored patterns. **Read before every action.** |
| `messages/emails-YYYY-MM-DD.md` | Daily processing log. One line per email processed. Used for deduplication. |
| `messages/morning-digest.md` | Queue for important emails received during quiet hours. Delivered at morning digest time, then deleted. |

**Why `messages/` not `memory/`:** Email logs are transient operational data, not long-term memories. Keeping them in `messages/` prevents heartbeat/memory-search from picking them up.

**File Lifecycle:**
- `EMAIL-RULES.md`: Created once during setup, updated when user gives feedback
- `emails-YYYY-MM-DD.md`: Created fresh each day, deleted after 7 days by cleanup cron
- `morning-digest.md`: Created when queuing items during quiet hours, deleted after morning digest is sent

---

## Gmail Label Management

Labels listed in `messages/EMAIL-RULES.md` are a reference, not a constraint. When you need to apply a label:

**Applying Labels:**
1. Attempt to apply the label using `gog gmail thread modify <messageId> --add "{Label}"`
2. If the label doesn't exist, Gmail will return an error
3. **Create the label** using `gog gmail labels create "{Label}"`
4. Retry applying the label

**Label Naming Conventions:**
- Use Title Case (e.g., `Newsletters`, `Job Alerts`, `Receipts`)
- Keep names short and descriptive
- Avoid special characters

**Example: Creating a new label**
```bash
# Label doesn't exist, create it
gog gmail labels create "Job Alerts"

# Now apply it
gog gmail thread modify {messageId} --add "Job Alerts"

# Then update EMAIL-RULES.md to include:
# | `Job Alerts` | Job board notifications, application updates |
```

---

## Gmail Inbox Management

`INBOX` and `STARRED` are special labels. To archive an email (subject to user email rules), remove the `INBOX` label. To star an email (subject to rules), add the `STARRED` label.

```bash
# Apply a label to a thread
gog gmail thread modify {messageId} --add "Label Name"

# Remove a label from a thread
gog gmail thread modify {messageId} --remove "Label Name"
```

## Workflow 1: Incoming Email Trigger

**Trigger:** Gmail Pub/Sub push event via webhook (message template starts with `[EMAIL-TRIAGE:INCOMING]`)

### Step-by-Step Checklist

```
1. VALIDATE INPUT (see "Empty Triggers" section above — this is critical!)
   [ ] Is Message-ID present and non-empty?
   [ ] Is From present and non-empty?
   [ ] Is Subject present (empty string OK, but field must exist)?
   
   → If ANY required field is missing/empty: STOP. No output. No logs. No message. End session.
     (This is normal — Gmail sends notifications for non-email events. Just be silent.)
```

```
2. CHECK FOR DUPLICATES
   [ ] Read messages/emails-{today}.md (the daily processing log)
   [ ] Search for the Message-ID in the log
   
   → If Message-ID already exists: STOP IMMEDIATELY. No output. End.
```

```
3. READ RULES
   [ ] Read messages/EMAIL-RULES.md
   [ ] Note: Quiet Hours, VIP Senders, Priority Senders, Interesting Sources, Ignored patterns, etc
```

```
4. CLASSIFY EMAIL
   Check in this order (first match wins):
   
   4a. CRITICAL CONTENT OVERRIDE (check FIRST, before sender rules)
       Scan subject + body for critical indicators, e.g.:
       - Security: "account compromised", "unusual sign-in", "password reset" (not requested)
       - Payment failures: "payment failed", "card declined", "account suspended"
       - Urgent deadlines: "final notice", "account will be closed", "action required by [date]"
       - Infrastructure: "server down", "service outage", "critical alert"
       - Personal: "emergency contact", "urgent family matter"
       
       → If critical content detected: Treat as IMPORTANT (Step 5b), regardless of sender.
         (Even from Ignored Senders or Interesting Sources)
   
   4b. IGNORED?
       - Matches Ignored Senders pattern?
       - Matches Ignored Subjects pattern?
       - AND no critical content (checked in 4a)
       → ACTION: Label (if applicable), archive, log. STOP. (No notification ever)
   
   4c. CRITICAL/URGENT?
       - Matches Priority Senders?
       - Contains security alert keywords (password reset you didn't request, 
         account breach, 2FA codes)?
       - Server/infrastructure DOWN alerts?
       → ACTION: Notify immediately (even during quiet hours). See Step 5a.
   
   4d. IMPORTANT?
       - Matches VIP Senders?
       - Direct personal message from known contact?
       - Contains payment deadline or action-required from trusted sender?
       → ACTION: Check quiet hours. See Step 5b.
   
   4e. INTERESTING?
       - Matches Interesting Sources patterns?
       - Matches user definition, e.g.: Job alerts, tech newsletters, product updates from relevant sources?
       - AND no critical content (already checked in 4a)
       → ACTION: Label, log for evening review. See Step 5c. (No notification)
   
   4f. GENERAL (default)
       - Marketing, receipts, automated notifications
       → ACTION: Label appropriately, archive, log. See Step 5d. (No notification)
```

```
5. TAKE ACTION

   5a. CRITICAL → Notify Immediately
       [ ] Send alert to Discord using 🚨 CRITICAL template
       [ ] DO NOT archive (keep in inbox for user attention)
       [ ] Log to messages/emails-YYYY-MM-DD.md with ACTION: "notified (CRITICAL)"
       → End.
   
   5b. IMPORTANT → Check Quiet Hours
       [ ] Get current time in user's timezone
       [ ] Is it within quiet hours (e.g., 21:00 - 08:30)?
       
       If YES (quiet hours active):
         [ ] Append summary to messages/morning-digest.md
         [ ] DO NOT archive (keep in inbox)
         [ ] Log with ACTION: "queued for morning digest"
         [ ] DO NOT send any message to user
         → End.
       
       If NO (outside quiet hours):
         [ ] Send notification to Discord using 📧 IMPORTANT template
         [ ] DO NOT archive (keep in inbox for user attention)
         [ ] Log with ACTION: "notified (IMPORTANT)"
         → End.
   
   5c. INTERESTING → Silent, Surface in Evening
       [ ] Apply appropriate Gmail label (create if needed — see "Gmail Label Management")
       [ ] Archive the email
       [ ] Log with ACTION: "labeled/{label}, archived (interesting)"
       [ ] DO NOT send any message to user
       → End.
   
   5d. GENERAL → Silent Processing
       [ ] Apply appropriate Gmail label (create if needed — see "Gmail Label Management")
       [ ] Archive the email
       [ ] Log with ACTION: "labeled/{label}, archived"
       [ ] DO NOT send any message to user
       → End.
```

### Notification Templates

**🚨 CRITICAL Template:**
```
🚨 **CRITICAL: {Subject}**
From: {From Name}

{1-2 sentence summary of the issue and why it's urgent}

→ Action: {what to do immediately}
```

**📧 IMPORTANT Template:**
```
📧 **{From Name}**
{Subject}

{1-2 sentence summary of what this is and why it matters}

{If action needed: "→ Action: {what to do}"}
```

**Examples:**

```
🚨 **CRITICAL: Unusual sign-in detected**
From: Google Security

Someone signed into your account from a new device in Russia. If this wasn't you, your account may be compromised.

→ Action: Review activity at myaccount.google.com/security immediately
```

```
📧 **Kadry Biuro AS** (accountant)
ZUS 12/2025 + SALDO ZUS 2025

December ZUS payment details. Amount: 1,246.63 zł due 20 January.

→ Action: Pay to account 83 6000 0002 0260 0161 1284 4462
```

### Log Entry Format

Each email gets one line in `messages/emails-YYYY-MM-DD.md`:

```
[HH:MM] ID: <messageId> | FROM: <sender> | SUBJ: <subject> | SUMMARY: <1-2 sentence summary> | ACTION: <action taken>
```

**Example:**
```
[14:32] ID: 19bd76a5c2164486 | FROM: as_kadry@nedzi.org.pl | SUBJ: ZUS 12/2025 | SUMMARY: December ZUS payment 1,246.63 zł due 20 Jan | ACTION: notified (IMPORTANT)
[14:45] ID: 19bd77b3a1234567 | FROM: kilocode@substack.com | SUBJ: Semantic Search Deep Dive | SUMMARY: Technical article about vector embeddings for code search | ACTION: labeled/Newsletters, archived (interesting)
[15:02] ID: 19bd78c4b2345678 | FROM: deals@pizzahut.com | SUBJ: 50% off this weekend | SUMMARY: Pizza promotion | ACTION: labeled/Newsletters, archived
```

---

## Workflow 2: Morning Email Digest

**Trigger:** Cron job at configured time (e.g., 08:30) OR user asks for digest
**Message template:** `[EMAIL-TRIAGE:MORNING-DIGEST]`

### Step-by-Step Checklist

```
1. CHECK FOR QUEUED ITEMS
   [ ] Does messages/morning-digest.md exist?
   [ ] Does it contain any entries?
   
   → If file doesn't exist or is empty: Send brief "all clear overnight" message. End.
```

```
2. GATHER CONTEXT
   [ ] Read messages/morning-digest.md (queued overnight items)
   [ ] Read messages/emails-{yesterday}.md (yesterday's activity for stats)
   [ ] Read messages/emails-{today}.md (early morning activity)
```

```
3. COMPOSE DIGEST
   [ ] List overnight important items with summaries
   [ ] Summarize yesterday's email stats
   [ ] Highlight any pending action items with deadlines
```

```
4. DELIVER
   [ ] Send digest to Discord using template below
   [ ] Delete messages/morning-digest.md
```

### Morning Digest Template

```
☀️ **Morning Digest** — {Day, Date}

📬 **Overnight** ({count} items)
• {Sender}: {Subject} — {brief summary}
• {Sender}: {Subject} — {brief summary}

📊 **Yesterday**: {X} processed, {Y} important, {Z} archived

⚠️ **Needs Attention**
• {Item with deadline or action required}
• {Item with deadline or action required}
```

**Example:**
```
☀️ **Morning Digest** — Monday, 20 January

📬 **Overnight** (3 items)
• GiveDirectly: Application Update — they received your application
• Welcome to the Jungle: Senior Full Stack at GoHiring — remote, Ruby/React
• Nationwide: Interest rate change — savings rate updated to 4.5%

📊 **Yesterday**: 45 processed, 8 important, 37 archived

⚠️ **Needs Attention**
• ZUS payment due TODAY: 1,246.63 zł
• Amazon returns deadline: 26 January (2 items)
```

---

## Workflow 3: Evening Email Review

**Trigger:** Cron job at configured time (e.g., 20:00) OR user asks for review
**Message template:** `[EMAIL-TRIAGE:EVENING-REVIEW]`

### Step-by-Step Checklist

```
1. GATHER TODAY'S ACTIVITY
   [ ] Read messages/emails-{today}.md (the daily processing log)
   [ ] Count totals by category (critical, important, interesting, general)
   [ ] Extract emails marked as "(interesting)" for the digest
   [ ] Identify any emails that might need follow-up
```

```
2. COMPILE INTERESTING ITEMS
   [ ] Filter log entries where ACTION contains "(interesting)"
   [ ] These are emails worth mentioning but not notification-worthy
```

```
3. CHECK FOR ACTIONABLE ITEMS
   [ ] Any emails mentioning meetings/appointments → suggest calendar event
   [ ] Any emails requiring response → remind user
   [ ] Any recurring ignored patterns → suggest Gmail filter
```

```
4. COMPOSE REVIEW
   [ ] Summarize today's activity (stats)
   [ ] List interesting items that might be worth a look
   [ ] List pending actions (if any)
   [ ] Offer suggestions (if any)
```

```
5. DELIVER
   [ ] Send review to Discord using template below
   [ ] If user doesn't respond, that's fine — no follow-up needed
```

### Evening Review Template

```
🌙 **Evening Review** — {Day, Date}

📊 **Today**: {X} emails processed
• {Y} important, {Z} interesting, {W} archived

{If interesting items exist:}
📰 **Worth a Look** (not urgent, but interesting)
• {Source}: {Subject} — {1-line summary}
• {Source}: {Subject} — {1-line summary}

{If pending actions exist:}
📋 **Pending**
• {Action item with deadline}

{If suggestions exist:}
💡 **Suggestions**
• Add "{event}" to calendar for {date}?
• Create filter for "{sender}" newsletters?
```

**Example:**
```
🌙 **Evening Review** — Monday, 20 January

📊 **Today**: 28 emails processed
• 5 important, 8 interesting, 15 archived

📰 **Worth a Look** (not urgent, but interesting)
• Kilo Code: Semantic Search Deep Dive — technical article on vector embeddings
• Welcome to the Jungle: 3 new job matches — GoHiring, Kalepa, Feeld
• This Week in React: Issue #264 — React 19 updates

📋 **Pending**
• Accountant invoice (852 zł) — still unpaid from last week

💡 **Suggestions**
• Add "Dentist appointment" to calendar for Feb 3?
```

---

## Configuration

### Hook Configuration (clawdbot.json)

Update the Gmail hook mapping to use explicit workflow triggers:

```json
{
  "hooks": {
    "mappings": [
      {
        "match": { "path": "gmail" },
        "action": "agent",
        "wakeMode": "now",
        "name": "Gmail",
        "sessionKey": "hook:gmail:{{messages[0].id}}",
        "messageTemplate": "[EMAIL-TRIAGE:INCOMING]\n\nMessage-ID: {{messages[0].id}}\nFrom: {{messages[0].from}}\nSubject: {{messages[0].subject}}\nSnippet: {{messages[0].snippet}}\n\n---\nBody:\n\n{{messages[0].body}}",
        "deliver": false,
        "channel": "discord",
        "to": "channel:{channelId}",
        "skills": ["email-triage"]
      }
    ]
  }
}
```

**Key settings:**
- `deliver: false` — The skill handles all notifications; don't double-post
- `sessionKey` with message ID — Ensures unique session per email

### Cron Job Configuration

Create these cron jobs during setup:

**Morning Digest** (08:30 user timezone):
```bash
cron add \
  --name "Email: Morning Digest" \
  --cron "30 8 * * *" \
  --tz "{userTimezone}" \
  --session isolated \
  --deliver \
  --channel discord \
  --to "channel:{channelId}" \
  --skills email-triage \
  --message "[EMAIL-TRIAGE:MORNING-DIGEST]"
```

**Evening Review** (20:00 user timezone):
```bash
cron add \
  --name "Email: Evening Review" \
  --cron "0 20 * * *" \
  --tz "{userTimezone}" \
  --session isolated \
  --deliver \
  --channel discord \
  --to "channel:{channelId}" \
  --skills email-triage \
  --message "[EMAIL-TRIAGE:EVENING-REVIEW]"
```

**Weekly Cleanup** (Sunday midnight):
```bash
cron add \
  --name "Email: Cleanup Logs" \
  --cron "0 0 * * 0" \
  --tz "{userTimezone}" \
  --session main \
  --system-event \
  --message "Delete messages/emails-*.md files older than 7 days"
```

---

## Initial Setup Checklist

When user asks to set up email triage:

```
1. [ ] Check if messages/EMAIL-RULES.md exists
      → If not, create using Bootstrap Template below

2. [ ] Ask user for Discord channel ID for notifications

3. [ ] Ask user for preferred times:
      - Morning Digest (default: 08:30)
      - Evening Review (default: 20:00)
      - Quiet Hours (default: 21:00 - 08:30)

4. [ ] Update messages/EMAIL-RULES.md with settings

5. [ ] Create the three cron jobs (Morning, Evening, Cleanup)

6. [ ] Confirm setup is complete
```

---

## Bootstrap Template for `messages/EMAIL-RULES.md`

```markdown
# Email Triage Configuration

## Settings
- **Discord Channel**: channel:{ID}
- **Quiet Hours**: 21:00 - 08:30
- **Morning Digest**: 08:30
- **Evening Review**: 20:00

---

## Priority Senders (CRITICAL - always notify immediately, breaks quiet hours)
<!-- Only genuine emergencies: security breaches, infrastructure DOWN -->
<!-- Use sparingly — most things are IMPORTANT, not CRITICAL -->


## VIP Senders (IMPORTANT - notify outside quiet hours, queue during quiet hours)
<!-- Important contacts: family, work, accountant, etc. -->


## Interesting Sources (surface in evening review, never notify)
<!-- Worth reading but not urgent: tech newsletters, job alerts, etc. -->
- *@substack.com
- *welcometothejungle*
- *glassdoor*

## Ignored Senders (never notify, never surface — fully silent)
- *@marketing.*

## Ignored Subjects (patterns to silently archive)

---

## Labels & Their Purpose
<!-- Core labels. Agent will create additional labels as needed and add them here. -->
| Label | When to Apply |
|-------|---------------|
| `Receipts` | Purchase confirmations, invoices, payment receipts |
| `Travel` | Flight confirmations, hotel bookings, itineraries |
| `Finance` | Bank statements, investment updates, tax docs |
| `Newsletters` | Subscribed content, digests, RSS-style emails |
| `Notifications` | Automated alerts from services (GitHub, CI, etc.) |

---

## Classification Notes
<!-- Learned preferences from user feedback. Agent appends here. -->
```

---

## Learning from Feedback

When user provides feedback:

1. **"This isn't important"** → Move to Interesting or Ignored section
2. **"Never show me these"** → Add to Ignored Senders/Subjects
3. **"Always flag emails from X"** → Add to VIP or Priority Senders
4. **"This is interesting but don't notify"** → Add to Interesting Sources
5. Confirm: "Got it, updated the rules for {X}."
