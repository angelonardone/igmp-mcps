---
description: Switch the InstantGMP MCP plugin to a different saved server profile (URL + credentials)
argument-hint: (optional profile name; omit to list and pick interactively)
---

The user has invoked `/igmp-switch`. They want to point the InstantGMP
MCP plugin at a different server (different URL and/or different API
credentials) by switching to a previously saved profile.

Profiles are managed by the bundled PowerShell helper at
`${CLAUDE_PLUGIN_ROOT}/scripts/setup.ps1`. Each profile stores a URL,
API user, and DPAPI-encrypted password under
`%USERPROFILE%\.instantgmp\profiles\<name>.json`. Switching a profile
overwrites the User-scope env vars `IGMP_URL`, `IGMP_API_USER`,
`IGMP_API_PASSWORD`, and `IGMP_ACTIVE_PROFILE`.

Steps:

1. **List the available profiles for the user.** Run, in a User
   PowerShell window:

   ```powershell
   powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\setup.ps1" -List
   ```

   Show them the output. The currently active profile is marked with `*`.

2. **If the user passed a profile name as an argument**, jump to step 4
   with that name. Otherwise, ask them which profile to switch to. If
   no profiles exist yet, tell them to save one first with
   `/igmp-setup` (or `setup.ps1 -Save <name>`).

3. **If they want to add a NEW server**, don't switch — instead invoke
   the `/igmp-setup` flow (or run
   `setup.ps1 -Save <new-name>`) so the new credentials get prompted,
   probed, and saved as a named profile, then activated.

4. **Activate the chosen profile:**

   ```powershell
   powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\setup.ps1" -Use <profile-name>
   ```

   The script probes the server and writes the env vars.

5. **Tell the user to fully restart Cowork.** The HTTP MCP servers only
   read environment variables at process start, so the switch takes
   effect on the next Cowork launch.

6. **Verify after restart** by running a small InstantGMP query
   (e.g. *"list the first three projects"*) and confirming the records
   come back from the expected server.

Reminders:

- Never echo the profile's password back to the user. The script never
  prints it; you should not print it either.
- Profiles are encrypted with DPAPI, which is bound to the current
  Windows user on the current machine — they cannot be copied to
  another user or another PC.
- The DDS still requires using a dedicated `APIUser`-type personnel
  record (not a real production user) for each environment.

To delete a stale profile, use:

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}\scripts\setup.ps1" -Delete <profile-name>
```
