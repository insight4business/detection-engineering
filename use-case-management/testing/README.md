# Testing detections

A detection is not finished until it has fired on realistic activity and stayed quiet on normal activity. This guide describes how to test each use case before promoting it from `Draft` to `Testing` and then `Production`.

## 1. Principles
- Test in a lab tenant, lab workspace or isolated endpoints. Never run offensive tests in production without written authorization and a rollback plan.
- Every use case needs at least one positive test (must alert) and one negative test (must not alert).
- Keep evidence: query result, alert screenshot or export (sanitized), and the time from action to alert.
- Re-test after every rule change, schema change or connector change.

## 2. Test levels
| Level | What it proves | How |
|---|---|---|
| Logic test | The query returns the expected rows for sample data | Synthetic events with `datatable` in KQL (see [unit-tests](./unit-tests)) or `makeresults` in SPL |
| Ingestion test | The required table, fields and audit policy exist | Run the base query without filters on recent data and check that required fields are populated |
| End-to-end test | Real activity produces an alert within the target latency | Simulate the technique, wait for the schedule, confirm incident or alert |
| Noise test | Alert volume is acceptable | Run the rule over 14 to 30 days of history and count results per day |

## 3. Host and identity techniques: Atomic Red Team
For endpoint and Windows techniques use the open-source Atomic Red Team test library, one technique at a time, on an isolated lab host with the endpoint agent and log forwarding in place.

1. Install the Invoke-AtomicRedTeam module on the lab host.
2. List the tests for the technique: `Invoke-AtomicTest T1059.001 -ShowDetails`.
3. Check prerequisites: `Invoke-AtomicTest T1059.001 -CheckPrereqs`.
4. Run the test: `Invoke-AtomicTest T1059.001`.
5. Clean up: `Invoke-AtomicTest T1059.001 -Cleanup`.
6. Confirm the telemetry arrived (process creation, security events) and the alert fired.

technique-test-map.csv shows which use cases map to a technique that normally has Atomic tests. Verify availability for your version of the library.

## 4. Cloud and identity techniques: lab simulation
Many cloud detections (role assignment, policy changes, storage exposure, diagnostic settings) are control plane actions. Simulate them manually or by script in a lab subscription or tenant:
- Create and remove a lab user, role assignment, app registration or secret.
- Change a lab NSG rule, policy assignment, storage setting or diagnostic setting.
- Sign in from a lab VPN in another country, or through an anonymizer, for impossible travel and TOR cases.
- Use dedicated lab accounts, tag them, and remove them after the test.

## 5. Generating test events
- KQL: shadow the table with a `datatable` of fixed rows, as in the unit tests, and run the aggregation part of the rule.
- SPL: use `| makeresults count=20 | streamstats count | eval ...` to build synthetic rows, then append the rule logic.
- Use documentation addresses (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24) and `contoso.com` identities only.
- Windows events can be produced by the real action (failed logon, service install, log clear) on a lab host.

## 6. Acceptance criteria
A use case can move to `Testing` when:
- The positive test returns the expected result and the negative test returns nothing.
- Required fields are present in real data.

It can move to `Production` when:
- The end-to-end test alert arrives within the agreed latency (for example, within two schedule intervals).
- The noise test is within the agreed budget (for example, fewer than five alerts per day, or an agreed number for the SOC).
- The response playbook link is filled in and the SOC has been briefed.
- Owner, severity, MITRE mapping and review date are set, and the register and coverage matrix are updated.

## 7. Recording results
Use test-record-template.csv for each test run. Keep one row per run and link the evidence.

## 8. Regression and periodic checks
- Run the logic tests in the pipeline whenever a rule file changes.
- Re-run end-to-end tests at least every six months, and after platform changes.
- Add a health detection that alerts when a required table stops receiving data.
