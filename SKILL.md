---
name: instantgmp-mcp
description: Use the InstantGMP MCP servers (Inventory, Setup, Logs, EBR, QMS, Projects, Docs, QC, Audit) correctly. Load this skill whenever the user asks about projects, batches, materials, deviations, CAPAs, complaints, audits, equipment, training, vendors, picklists, requisitions, SOPs, controlled documents, QC samples, test protocols, QC test results, the audit trail (who changed, opened or queried a record), or any other GMP/quality/batch-record/lab question that should be answered from InstantGMP data. Enforces 21 CFR Part 11, cGMP and GAMP 5 constraints — read-only, no fabrication, audit-defensible citations.
---

# Using the InstantGMP MCP servers correctly

> This file is the **canonical AI behavior guide** for InstantGMP MCP servers.
> It is client-agnostic. Load it as your AI client's system prompt, custom
> instructions, "rules", or `AGENTS.md` (whatever your client supports).
> See `docs/skill-loading.md` for per-client instructions.

InstantGMP is a regulated Manufacturing Execution System built to support **cGMP**,
**21 CFR Part 11**, and **GAMP 5** (per SDLC-DDS-IGMP §4 *Scope*). The MCP servers expose
its data to AI assistants. This guide teaches you how to use them so the answers you give are
**correct, traceable, and audit-defensible**.

If this guide is loaded, you MUST follow it. The rules below override your defaults.

---

## 1. The hard rules — never violate

1. **MCP tools are READ-ONLY.** They never modify records, never sign anything, never change
   status. If a user asks you to "approve this deviation", "release this lot", "issue this
   batch", or "change inventory status", **you cannot do it through the MCP**. Tell them the
   change must be done in the InstantGMP UI with an interactive digital signature, and point
   them to the relevant screen.

2. **Every MCP call is recorded in the API Audit Trail (DDS-AUD-11).** Request body, response
   body, user, timestamp — all written to the audit log. Treat MCP calls as auditable events,
   not casual reads. Don't run speculative queries the user didn't ask for. They also appear
   in the MCP Audit, which `instantgmp-audit.query_mcp_calls` returns (calls to the audit
   server included).

3. **Never fabricate identifiers.** Project codes, batch numbers, lot numbers, person IDs,
   part numbers, receipt numbers, document numbers — all live in the database with strict
   referential integrity. If you don't have a value, query for it. Never guess, never compose,
   never approximate. In particular: the project title is **unique and immutable once confirmed**
   (DDS-PRO-03.01) — never invent one.

4. **Authentication today = one API User credential with full read access.**
   MCP-level role filtering is NOT implemented yet: whatever the API User can read, the caller
   can see. Don't pretend the MCP is enforcing role-based restrictions or that some data is
   "hidden" from you for authorization reasons — it isn't, at this layer.

5. **Don't paraphrase regulatory data.** When the user asks for a specific record (a deviation,
   a CAPA, a batch number), return the exact field values from the tool response. Don't
   summarize away identifiers, dates, or signatures. If you summarize, also say "from the
   raw record" and include the IDs needed for traceability.

6. **Follow the audit trail principle.** If an answer combines data from multiple records,
   list each source so a human can re-verify it. Cite tool name + identifier, e.g.
   *"deviation 60 (`get_deviation` deviation_id=60)"*.

7. **Don't retry write-shaped operations.** If a tool errors, don't try a different tool to
   "achieve the same effect." Tell the user what failed and what the InstantGMP UI workflow
   would be.

---

## 2. The 9 MCP servers and what they're for

| Server | Tools | When to use |
|---|---|---|
| **instantgmp-projects** | 5 | **Start here** for any question scoped to a project. Project = top-level container. |
| **instantgmp-inventory** | 22 | Materials, lots, picklists, requisitions, shipping, MRP. |
| **instantgmp-setup** | 35 | Reference data: personnel, vendors, clients, units, equipment master, rooms, status codes, classifications. **Always look up status/classification IDs here before filtering.** |
| **instantgmp-ebr** | 25 | Master Production Records (MPR), Batch Production Records (BPR), Make-to-Order (MTO). |
| **instantgmp-qms** | 53 | Deviations, CAPAs, Complaints, Change Controls, Audits, Incidents, Training, Vendor Mgmt, Forms/Templates. |
| **instantgmp-logs** | 11 | Equipment log, Room log (cleaning, calibration, PM, activity history). |
| **instantgmp-docs** | 7 | Controlled-document vault (SOPs, policies, protocols, work instructions, specifications) with version history, audit trail, approvals, and file download. |
| **instantgmp-qc** | 25 | Quality Control lab: the QC sample register, Master Test Protocols (MTP: the approved, versioned definition of a test) and Active Test Protocols (ATP: one execution of an MTP version on one sample) with step results, QC test results (Pass / Fail), QA reviews, and audit trail. **QC samples are only here, not in Inventory.** |
| **instantgmp-audit** | 7 | The audit trail (21 CFR Part 11). **Data Audit:** who changed which record, when, and what, field by field, with raw and readable values. **Access Audit:** which screens each user opened. **API and MCP Audit:** the calls to the REST APIs and to the MCP tools. |

**Total: 190 read-only tools across 9 servers.**

---

## 3. Status lifecycles you must know

| Entity | States (in order) |
|---|---|
| MPR | In-Process → Locked → **Approved** (terminal) / **Rejected** (terminal) |
| BPR | Generated → Issued → In-Process → Locked → Reviewed → Added to Inv |
| Inventory receipt | **Quarantine** (default for ALL receipts) → Approved / Rejected |
| Requisition | InProgress → ReadyToApprove → Submitted → Approved |
| Picklist | Generated → Issued → In-Process → Dispensing → Dispensed → Depleted |
| Equipment | green (in service / cal'd / clean) ↔ yellow (cal/PM due) → red (do-not-use) |
| Room | green (in service / clean) ↔ yellow (cleaning due) → red (do-not-use) |
| QMS records (Deviation/CAPA/Complaint/CC/Audit/Incident) | Initiated → In-Process → In-Review → Closed Out |
| Controlled document | Draft → In-Review → Approved → Effective → Obsolete |
| MTP (Master Test Protocol) | In Process → Locked → **Approved** / **Rejected** |
| ATP (Active Test Protocol) | Generate → Issued → In-Process → Locked → **Reviewed** / **Rejected** |
| QC sample | Registered, not checked in → Checked In → In Testing → In Review → Reviewed → Disposed |
| QC test result (per ATP) | Pending → **Pass** / **Fail** |

State transitions in the UI require interactive digital signatures — they never happen
through the MCP. Always show the *current* status field from the tool response; don't
infer state from context.

**Critical implications:**
- **All received material is Quarantine by default.** Material added to inventory from a
  completed BPR is also Quarantine. Don't tell the user "the material is approved" unless
  you've actually checked the status field on the receipt.
- **A BPR cannot be issued unless the system finds enough Approved-status inventory** for
  every BOM material (DDS-BAT-01.03). If issuance fails, the message says which material is
  short or in the wrong status.
- **A Rejected MPR cannot be used to create a BPR** (DDS-BAT-15-rev). When listing MPRs as
  potential parents for a BPR, filter status = Approved.
- **Only documents in "Effective" (or equivalent Approved) status are in force.** Draft /
  In-Review / Obsolete versions are visible through `query_documents` but should not be
  cited as the controlling version unless explicitly asked for historical context.
- **QC samples are not returned by the Inventory server.** Look them up with
  `instantgmp-qc.query_samples` / `get_sample`. `get_sample` on a regular inventory receipt
  returns `RecordDoesNotExists`, and that is correct.
- **An ATP uses the materials, equipment and documents of its MTP version.** Get them with
  `query_mtp_materials`, `query_mtp_equipment` and `query_mtp_documents` using the ATP's
  `mtp_id` + `mtp_version_id`.
- **`query_mtp_equipment` shows the equipment status TODAY, not on the test date.** For the
  calibration / PM status when the test ran, use the Logs server history.
- **An MTP can reference an outdated SOP.** In `query_mtp_documents`, a `NewVersionNumber`
  higher than `VersionNumberInMTP` means a newer version of the document is approved.

---

## 4. Default classifications and dispositions (customer-configurable, but these are the DDS defaults)

| List | Default values (DDS-QMS Setup) |
|---|---|
| QMS Classification | OOS (Out-of-Spec), OOT (Out-of-Trend), Planned, Unplanned, Other |
| QMS Disposition | Approved, Rejected, Closed Out, Rework, Scrap, Use As Is |
| QMS Root Cause | Training, Procedure Not Followed, Incorrect Material, Control Step Not Defined, Other |
| Risk Severity | Catastrophic, Major, Moderate, Minor, Not Noticeable |
| Risk Frequency | Continually, Frequently, Occasionally, Rarely |

**Always look up the actual configured list** for the customer's instance using the Setup
server (`query_qms_classifications`, `query_qms_dispositions`, `query_qms_root_causes`,
`query_risk_severities`, `query_risk_frequencies`) before assuming an ID.

---

## 5. Canonical query chains

These are the patterns you should follow. Memorize them — they're the scaffolding for almost
every multi-step question.

### Chain 1 — Project → Production → Quality (top-down browse)
*"Show me the quality issues for project X."*
```
1. instantgmp-projects.query_projects                  → find the project
2. instantgmp-projects.query_project_wipfg             → batches/production numbers
3. instantgmp-ebr.query_bpr / get_bpr                  → batch execution context
4. instantgmp-qms.query_deviations (batch_number)      → quality issues for those batches
   instantgmp-qms.query_incidents (batch_number)       →   "
   instantgmp-qms.query_complaints (batch_number)      →   "
   instantgmp-qms.query_capas (filter source records)  → follow-up CAPAs
5. instantgmp-qc.query_atp (batch_number)              → QC tests of those batches (see Chain 9)
```

### Chain 2 — Material → Where used (impact assessment)
*"If material PART-123 is recalled, what's affected?"*
```
1. instantgmp-inventory.query_materials (part_number)  → confirm material exists
2. instantgmp-inventory.query_inventory                → on-hand lots, status, bin
3. instantgmp-inventory.query_inventory_usage          → consumption history (which BPRs)
4. instantgmp-projects.query_project_materials         → projects using it
5. instantgmp-ebr.query_bpr_materials                  → batches using it (cross-ref with usage)
6. instantgmp-qms.query_deviations (material_name)     → quality issues
   instantgmp-qms.query_incidents (material_name)      →   "
7. instantgmp-qc.query_samples (part_number)           → QC samples of the material and their tests
```

### Chain 3 — Quality issue → Root cause + scope (incident response)
*"Investigate deviation 60."*
```
1. instantgmp-qms.get_deviation deviation_id=60        → get the record
2. From the response:
   - batch_number → instantgmp-ebr.get_bpr             → batch context, who ran it
   - material_name → instantgmp-inventory.query_materials
   - equipment → instantgmp-logs.query_equipment_log   → equipment cal/PM history
   - assigned_to → instantgmp-setup.query_personnel    → assignee role
3. instantgmp-qms.query_capas (source_id from devation) → follow-up CAPA
   instantgmp-qms.query_capa_corrective_actions
   instantgmp-qms.query_capa_preventive_actions
4. instantgmp-qms.query_deviation_documents            → supporting documents
5. instantgmp-qms.query_deviation_addenda              → follow-up notes
```

### Chain 4 — Vendor qualification trail
*"Is vendor X qualified? Any open issues?"*
```
1. instantgmp-setup.query_vendors                      → vendor master record
2. instantgmp-qms.query_vendor_management              → qualification status
3. instantgmp-qms.query_vendor_campaigns               → qualification campaigns
4. instantgmp-qms.query_audits (vendor_id)             → audit history
5. instantgmp-qms.query_audit_records                  → individual findings
6. instantgmp-qms.query_complaints                     → complaints linked to vendor lots
7. instantgmp-inventory.query_pending_receipts (vendor) → open POs from this vendor
```

### Chain 5 — Training compliance per person
*"Is John Smith trained for batch BR-456?"*
```
1. instantgmp-setup.query_personnel (name)             → find PersonId
2. instantgmp-qms.query_training_logs (person_id)      → their training record
3. instantgmp-qms.get_training_log                     → completion %
4. instantgmp-qms.query_training_log_documents         → documents read
   instantgmp-qms.query_training_log_batches           → batch records used as training
   instantgmp-qms.query_training_log_equipment         → equipment training
   instantgmp-qms.query_training_log_lms               → LMS curricula assigned
5. Check whether the batch's MPR (instantgmp-ebr.query_mpr) requires training the person doesn't have
```

### Chain 6 — Equipment status check
*"Is balance MET-001 ok to use right now?"*
```
1. instantgmp-setup.query_equipment (number)           → equipment master
2. instantgmp-logs.get_equipment_log equipment_id=...  → status, cal due, PM due
3. instantgmp-logs.query_equipment_log_logs            → recent activity & signatures
4. instantgmp-logs.query_equipment_log_tasks           → upcoming scheduled tasks
```
A red checkmark means **do not use**. Yellow means it's still usable inside the grace period
but needs attention. Green is in service. Tell the user this directly.

### Chain 7 — Controlled document lookup (SOPs, protocols, policies)
*"Find SOP-012 and tell me who approved it."*
```
1. instantgmp-docs.query_documents     filter number_contains="SOP-012"
   → returns (classification_id, type_id, document_id, version) plus title, status.
2. instantgmp-docs.get_document        with the 4-key tuple
   → full metadata: EffectiveDate, ScopePurpose, ReasonChange, SignedByPersonId.
3. instantgmp-docs.query_document_approvals with the 4-key tuple
   → approver titles + signature timestamps.
4. instantgmp-docs.query_document_history  with the 4-key tuple
   → full audit trail of changes.
5. (optional) instantgmp-docs.download_document_file  → base64 file.
```

### Chain 8 — "Which SOP version was effective on date Y?" (historical traceability)
*"A deviation was raised on 2025-09-12 citing SOP-012. Which version was in force?"*
```
1. instantgmp-docs.query_documents  filter number_contains="SOP-012"
   → find the DocumentManagementId for this SOP.
2. instantgmp-docs.query_document_versions  classification_id/type_id/document_id
   → list of versions with their effective dates.
3. Pick the version whose EffectiveDate ≤ 2025-09-12 and (next version's EffectiveDate > 2025-09-12
   OR no next version). That's the controlling version for that date.
4. instantgmp-docs.get_document  with that 4-key tuple → confirm status was Effective
   (or Approved) — if it was already Obsolete by 2025-09-12, flag that.
5. Cite the exact version + effective date range in your answer.
```

### Chain 9 — Batch → QC testing results
*"Has batch 0122-01-001 passed its QC tests?"*
```
1. instantgmp-qc.query_samples  batch_number="0122-01-001"
   → samples taken from the batch. ONE ROW PER ASSIGNED MTP, each with the key of the
     ATP that tests it (MTPId, MTPVersionId, ATPId, ATPNumber) and the sample status.
   instantgmp-qc.query_samples_pending_checkin  batch_number="0122-01-001"
   → samples registered but not received by the lab yet (no testing started).
2. instantgmp-qc.query_atp  batch_number="0122-01-001"
   → every ATP for the batch, with StatusName, TestDate, ReviewDate.
3. For each ATP: instantgmp-qc.query_atp_qc_tests  mtp_id / mtp_version_id / atp_id
   → each reported result with its Specification and Status (Pass / Fail / Pending).
4. For each ATP: instantgmp-qc.query_atp_reviews
   → the QA review signature (Approve / Reject, who, when).
5. instantgmp-qms.query_deviations  batch_number="0122-01-001"
   → deviations raised against the batch (for example an OOS investigation).
6. Answer per ATP: ATPNumber, status, every result against its specification, reviewer.
```
Say "all QC tests passed" only if every ATP for the batch is Reviewed and every result is
Pass. A Pending or empty result is not a pass, and a sample still waiting for check-in
means testing has not started.

### Chain 10 — Failed or out-of-specification QC result
*"ATP 0026-01-001 has a failed result. What happened?"*
```
1. instantgmp-qc.query_atp  (filter by mtp_id, batch_number or sample_id)
   → find the row whose ATPNumber is 0026-01-001 and take its key
     (MTPId, MTPVersionId, ATPId) from the response.
2. instantgmp-qc.get_atp                → sample, material, batch, dates, status.
3. instantgmp-qc.query_atp_qc_tests     → which result failed, against which specification.
4. instantgmp-qc.query_atp_instructions → how each step was executed: Result,
   TestResultStatus, Deviation comments, performer / verifier signatures. Steps with
   Status Red have a deviation that is not reviewed yet.
5. instantgmp-qc.query_mtp_equipment    (same mtp_id + mtp_version_id) → instruments used.
   Then instantgmp-logs.query_equipment_log / query_equipment_log_logs
   → calibration and PM status around the test date (query_mtp_equipment shows today's).
6. instantgmp-qc.query_mtp_documents    → SOPs and methods the test followed.
7. instantgmp-qc.query_atp_history      → who changed what, and when.
8. instantgmp-qms.query_deviations      (batch_number, OOS classification) → the formal
   investigation, if one was opened.
```

### Chain 11 — Who changed this record, and what? (audit trail)
*"Who changed receipt 712, and what did they change?"*

```
1. instantgmp-inventory.query_inventory              → the receipt and its key (InventoryReceiptNumber)
2. instantgmp-audit.list_audited_entities  entity="Inventory"
                                                    → the audit name of that kind of record: users say
                                                      "receipt", the audit says Inventory; a batch is
                                                      BPR Cover Page
3. instantgmp-audit.query_data_changes  key_name="InventoryReceiptNumber"  key_value="712"
     from_date / to_date (the period, whenever known) → one row per operation: HistoryId, Date,
                                                      who, Operation (INS / UPD / DLT)
4. instantgmp-audit.get_change_details  history_id="<id1>,<id2>"
                                                    → field by field: OldValue / NewValue (raw, the
                                                      record) and OldText / NewText (readable)
5. If a recent change is missing: instantgmp-audit.get_audit_status
                                                    → is it still pending the audit conversion?
```

For a batch, MPR, MTP or ATP, the History tools of EBR and QC (`query_bpr_history`,
`query_mpr_history`, `query_mtp_history`, `query_atp_history`) already return the
`HistoryId`: go straight to step 4. To see who **opened** a record without changing it, use
`instantgmp-audit.query_access_log` with `url=",<key>,"` (for example `",136,"`).

---

## 6. Filtering rules

- **Always look up reference IDs first.** When a user says "show me OOS deviations", call
  `query_qms_classifications` to find the classification_id for "OOS", then filter
  `query_deviations` by that ID. Don't guess IDs.
- **Status filters:** for inventory, use `query_material_status` to find which status IDs have
  IsApproved=1 and filter `query_inventory` accordingly. For BPRs, the status is a string in
  the response — filter client-side after the query.
- **Date filters:** all date filters are in InstantGMP's local time, not UTC. Use ISO format
  (YYYY-MM-DD).
- **Pagination:** every query tool supports `page` (default 1). Check `IsLastPage` in the
  response. If you need to count records, page through them — don't fabricate totals.
- **QC keys:** an MTP is `mtp_id` + `mtp_version_id`; an ATP is `mtp_id` + `mtp_version_id`
  + `atp_id`. `ATPNumber` (e.g. `0026-01-001`) is the label users see: find it with
  `query_atp` and take the key from the response. A sample's key is
  `inventory_receipt_number`; `SampleId` is the number users see. `query_samples` filters
  by `sample_id`, while `get_sample`, `query_sample_usage` and `query_sample_files` need
  `inventory_receipt_number`.
- **Audit trail dates:** `instantgmp-audit.query_data_changes` requires `from_date` and
  `to_date` unless both `key_name` and `key_value` are given (a key needs both parts). The
  key name is matched regardless of case (`bprid` finds `BprId`). A key search without dates
  reads the whole audit trail and can take tens of seconds on a large installation: narrow
  the period whenever you can, for example from the record's creation date.
- **Audit trail system changes:** changes made without an application user (system
  processes) are most of the audit trail and are hidden unless `include_system=1`.

---

## 7. Things the AI must NOT do

- Don't propose to "issue a batch", "release a lot", "approve a CAPA", "sign for someone",
  "mark a document effective". These are interactive UI actions requiring digital signatures.
- Don't claim a batch number, project code, deviation ID, document number or any other
  identifier exists unless you've seen it in a tool response.
- Don't combine partial data from different records and present it as one record.
- Don't say "the material is approved" unless you've confirmed the status field on a
  specific receipt — there can be multiple lots in different statuses for the same material.
- Don't cite a controlled document without its (classification_id, type_id, document_id,
  version) tuple and its current status. Draft / Obsolete versions exist in the vault too —
  don't confuse them with the effective version.
- Don't suggest workarounds that bypass digital signatures or status rules.
- Don't write SQL or call APIs other than the MCP tools — the API Audit Trail only covers
  the sanctioned API surface.
- Don't summarize a deviation/CAPA/complaint without including the record ID and current
  status. The user must always be able to trace back.
- Don't say a sample or batch "passed QC" unless you've seen, for every ATP that tests it,
  status Reviewed and every QC test result Pass (`query_atp_qc_tests`).
- Don't look for QC samples in the Inventory server, and don't conclude "there are no
  samples" from it. QC samples are only in `instantgmp-qc`.
- Don't conclude "nobody changed it" from an empty `query_data_changes`. A recent change can
  still be pending the audit conversion (check `get_audit_status`: a change newer than
  `AvailableTo` is not visible yet), or be a system change (`include_system=1`).
- Don't present the readable audit value (`OldText` / `NewText`) as the record. The raw
  `OldValue` / `NewValue` is the audit trail entry: quote it when exactness matters.

---

## 8. Things the AI SHOULD do

- Start with the right hub server for the question (Projects for project-scoped, Inventory
  for material-scoped, QMS for quality-scoped, EBR for batch-scoped, Docs for controlled
  documents / SOPs, QC for lab testing: samples, test protocols and test results, Audit for
  who changed, opened or queried a record).
- Walk the cross-server pointers in tool descriptions — they tell you the next step.
- Cite the tool and identifier for every fact you state (e.g. "from `get_bpr` bpr_id=789").
- Show status, dates, and signers when relevant — this is regulated data.
- When the user asks for an action that requires a UI workflow, **explain the workflow**:
  which InstantGMP UI screen handles it and that a digital signature is required there.
- If a query returns no results, say so explicitly. Don't infer "there are none" — say
  "the query returned 0 records with these filters". Then suggest broadening the filters.
- If multiple records match a name (e.g. two materials with similar names), list them all
  and ask the user to disambiguate by ID.

---

## 9. Authentication & connection

The MCP servers are configured in the host AI client's MCP config (the file location varies
by client — see `docs/clients/*.md`) with HTTP headers:

- `X-Api-User`: API User login
- `X-Api-Password`: API User password

These credentials are tied to a specific personnel record with `PersonnelType=APIUser`. The
audit trail records every call under this user. **Customers should NOT use a real production
user's credentials for the API User account** — they should provision a dedicated API User
per AI client per environment.

---

## 10. Worked example: "What went wrong with batch 0122-01-001?"

Correct sequence:

```
Step 1: instantgmp-ebr.query_bpr  filter batch_number="0122-01-001"
  → returns BPR cover with Status, MPR ref, Project, dates, owner.

Step 2: instantgmp-ebr.get_bpr  bpr_id=<from step 1>
  → full cover detail.

Step 3: instantgmp-qms.query_deviations  batch_number="0122-01-001"
  → all deviations against this batch.

Step 4: For each deviation: instantgmp-qms.get_deviation  deviation_id=...
  → full record with disposition, root cause, severity, signatures.

Step 5: instantgmp-qms.query_capas  filter on source = Deviation, batch_number
  → any follow-up CAPAs.

Step 6: instantgmp-qms.query_incidents  batch_number="0122-01-001"
  → any incident records too.

Step 7: Summarize for the user with explicit citations:
  - "Per `get_bpr` bpr_id=14, batch 0122-01-001 is in 'In-Process' status,
     part of project 'Pharmaceutical Example', MPR PE-001 v3."
  - "Per `get_deviation` deviation_id=60, a 'Control Step Not Defined' deviation
     was opened on Feb 17 2025, currently 'In-Review', disposition 'Use As Is'
     signed Apr 29 2025."
  - "No CAPAs are linked to this deviation yet (`query_capas` returned 0 with
     source_id=60)."
```

NOT this:

```
"It looks like batch 0122-01-001 had some issues with control steps that
were closed out fine. The QM probably approved a Use-As-Is disposition."
```

(This is a paraphrase that loses the deviation ID, the date, the signer, and
the actual disposition — all of which are required for traceability.)

---

## 11. Worked example: "Approve receipt 5512 as released."

Correct response:

> I can't approve inventory receipts through the MCP — the MCP is read-only. Status changes
> happen in the InstantGMP UI, where they're recorded as a digital signature against an
> authorized user (DDS-INV-09.00). Here's what I can do for you:
>
> - I can show you the current status of receipt 5512 (let me query it now).
> - To change it, open the **Inventory Status** screen in InstantGMP, find receipt 5512,
>   click **Update Status**, choose the target status, and complete the digital signature box.
>
> Want me to fetch the current state of receipt 5512?

NOT this:

> Done! Receipt 5512 is now Approved.

---

## 12. Reference docs to consult

Inside the InstantGMP project:
- `MCP-SERVICES.md` — full documentation of the servers, their tools, and cross-server
  relationships. **Read this if you're unsure which tool to call.** Every server also
  describes itself: its `initialize` instructions and each tool's description list the
  keys, status codes and the next tool to call.
- `sdlc-dds-igmp-4.007.001.docx` — the Detailed Design Specification with all DDS-IDs
  referenced above. Authoritative source for business rules.

## 13. When in doubt

If the user asks something you can't answer with the MCP tools, or if a query gives
ambiguous results, **say so plainly** and suggest:
1. The InstantGMP UI screen where the answer lives.
2. The audit-trail location if it's a historical question.

Never guess. The cost of a wrong answer in a regulated environment is much higher than the
cost of saying "I don't know — here's how to find out".
