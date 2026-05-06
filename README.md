# InstantGMP — Cowork integration

This repo distributes two things to your company's users:

1. **`instantgmp-mcp.skill`** — the InstantGMP usage skill, packaged as
   a Cowork-installable `.skill` archive. Teaches Claude how to use the
   InstantGMP MCP servers correctly under 21 CFR Part 11, cGMP, and
   GAMP 5 (read-only, no fabrication, audit-defensible citations).
2. **`scripts/setup.ps1`** — a Windows PowerShell helper that asks each
   user for their InstantGMP server URL, API user, and API password,
   probes the server, and writes a ready-to-paste MCP config to
   `%USERPROFILE%\.instantgmp\mcp-config.json`. The user pastes that
   JSON into Cowork → Settings → Developer (or whichever section your
   Cowork build exposes for MCP servers). Profiles let support staff
   switch between servers with one command.

The repo also contains `plugins/instantgmp/`, a Claude Code CLI
plugin/marketplace layout, kept for users on Claude Code (the terminal
tool). **Cowork desktop on Windows does not currently support
installing custom plugin marketplaces from arbitrary GitHub URLs**, so
Cowork users follow the skill+JSON path instead.

## Repository layout

```
igmp-mcps/
├── instantgmp-mcp.skill                  # zipped skill — drag into Cowork
├── scripts/
│   └── setup.ps1                         # Cowork-desktop setup helper
├── InstallationManual.docx               # printable user manual
├── plugins/instantgmp/                   # Claude Code CLI plugin (secondary)
│   ├── .claude-plugin/plugin.json
│   ├── .mcp.json
│   ├── commands/
│   │   ├── igmp-setup.md
│   │   └── igmp-switch.md
│   ├── scripts/setup.ps1                 # same script, mirrored here
│   └── skills/instantgmp-mcp/SKILL.md    # source of the skill
├── .claude-plugin/marketplace.json       # Claude Code marketplace manifest
└── README.md
```

## End-user install (Cowork desktop on Windows)

The user does this once per machine. After that, every Cowork session
loads the skill and reaches the InstantGMP server.

### Step 1 — Install the skill

Download `instantgmp-mcp.skill` from this repo and drag it into the
Cowork chat window. Cowork shows a **Save skill** button — click it.
The skill is now available to Claude.

### Step 2 — Run the setup helper

Download `scripts/setup.ps1` from this repo (or clone the whole repo).
Open a regular **Windows PowerShell** window (no admin needed) and run:

```powershell
powershell -ExecutionPolicy Bypass -File <path-to>\setup.ps1
```

The helper asks for:

- **InstantGMP base URL** (e.g. `https://yourcompany.igmpapp.com`)
- **API user** (`X-Api-User`)
- **API password** (`X-Api-Password`, hidden as you type)

It probes the server, writes a JSON config with literal values to
`%USERPROFILE%\.instantgmp\mcp-config.json`, and opens it in Notepad.

### Step 3 — Paste the config into Cowork

1. In Cowork, open **Settings → Developer** (or **Advanced**, depending
   on your build) and find the **MCP servers** section.
2. Add a new MCP-server configuration.
3. Paste the contents of `mcp-config.json` (the file Notepad opened)
   into the configuration box and save.

### Step 4 — Restart Cowork

Fully quit Cowork — close the window **and** the system-tray icon —
then reopen it. The MCP servers only read configuration at startup.

### Step 5 — Verify

Ask Claude inside Cowork:

```text
List the first three projects in InstantGMP.
```

Claude should call `instantgmp-projects.query_projects` and cite real
records. If it can't reach the server, double-check the URL (no
trailing slash) and that your APIUser credential is active.

## Switching between InstantGMP servers (named profiles)

Support staff who connect to multiple InstantGMP servers (prod, QA,
customer A, customer B, …) can save each one as a named profile and
switch between them with one command — no re-typing credentials.

Profiles live at `%USERPROFILE%\.instantgmp\profiles\<name>.json`. The
password is encrypted with Windows DPAPI under the current Windows
user — only the same user, on the same machine, can decrypt it.

```powershell
# Save the current prompts as a named profile and activate it
.\setup.ps1 -Save qa

# Switch to a saved profile (rewrites mcp-config.json)
.\setup.ps1 -Use qa

# List all saved profiles (URL + user only — never the password)
.\setup.ps1 -List

# Delete a stale profile
.\setup.ps1 -Delete qa
```

After switching, repeat **Step 3** (paste the new config into Cowork)
and **Step 4** (restart Cowork).

## End-user install (Claude Code CLI users only)

If your team uses Claude Code (the terminal tool, not Cowork desktop),
the same content is also packaged as a Claude Code plugin marketplace:

```text
/plugin marketplace add https://github.com/anardoneinstantgmp/igmp-mcps.git
/plugin install instantgmp@instantgmp
/igmp-setup
```

This path uses env-var placeholders (`${IGMP_URL}`, `${IGMP_API_USER}`,
`${IGMP_API_PASSWORD}`) in `plugins/instantgmp/.mcp.json`. The setup
script in that path is the same one shipped at `scripts/setup.ps1`.

## Why two install paths?

Cowork desktop and Claude Code CLI handle plugins differently:

- **Cowork desktop** ships skills via `.skill` zip files (in-chat
  install) and MCP servers via a settings-UI JSON config. There is no
  documented way to add a custom plugin marketplace from a GitHub URL
  in Cowork desktop today.
- **Claude Code CLI** supports `/plugin marketplace add <git-url>` and
  installs plugins (skill + MCPs + slash commands) as one bundle.

Same skill, same MCP servers, same setup helper — packaged twice so
both audiences get a smooth path.

## How per-user credentials work

The setup helper writes `mcp-config.json` with **literal** URL, user,
and password values. Each user's file lives under their own Windows
profile (`%USERPROFILE%\.instantgmp\`) and is never shared. The repo
itself contains zero secrets.

Profiles are stored as JSON with the password encrypted via Windows
DPAPI, which is bound to the current Windows user on the current
machine. Profiles do **not** survive being copied to another user or
another PC — each user must save their own.

## Updating the package

When you push a new commit to this repo, users update by:

- **Skill**: re-download `instantgmp-mcp.skill` and drop it into Cowork
  again (Cowork replaces the previous version of the skill with the
  same `name` in its frontmatter).
- **Setup script**: re-download `scripts/setup.ps1`. Profiles are
  unaffected.
- **MCP config**: only re-run the setup helper if the URL pattern or
  header names change; otherwise existing user configs continue to
  work.

## Removing it

To clear everything from a user's machine:

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.instantgmp"
```

In Cowork:

1. Open **Settings → Skills** and remove `instantgmp-mcp`.
2. Open **Settings → Developer → MCP servers** and remove the seven
   InstantGMP entries.
3. Restart Cowork.

## Security notes

- The MCP config on disk contains the literal API password. The file
  is in the user's home directory and is readable by that user (and
  processes running as that user) but not by other users on the
  machine.
- The DDS (`SKILL.md` §9) requires using a dedicated `APIUser`-type
  personnel record per AI client, per environment — never a real
  production human's login.
- All MCP calls are written to InstantGMP's API Audit Trail
  (DDS-AUD-11) under the `APIUser` identity.

## Support

The skill source lives at
`plugins/instantgmp/skills/instantgmp-mcp/SKILL.md` (and is what gets
zipped into `instantgmp-mcp.skill`). Edit there, then rebuild the zip:

```powershell
Compress-Archive -Path plugins\instantgmp\skills\instantgmp-mcp -DestinationPath instantgmp-mcp.skill -Force
```

Bump versions in `plugins/instantgmp/.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` after non-trivial changes.
