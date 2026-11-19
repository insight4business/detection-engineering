# Use case management

How a detection is defined, registered, tuned, tested, shipped as code and measured against MITRE ATT&CK. The rules themselves are in [../use-cases-by-technology](../use-cases-by-technology).

## Where am I in the lifecycle?

| Stage | Folder or file | Use it to |
|---|---|---|
| Define | use-case-template.md / [.yml](./use-case-template.yml) | Describe a new detection: objective, data, logic, thresholds, false positives, response |
| Register | use-case-register.csv | Track every use case (53 rows) with status, owner, review date and the path to its query |
| Test | [testing/](./testing) | Test guide, Atomic Red Team mapping, unit tests and test record template |
| Ship | [detection-as-code/](./detection-as-code) | Tool-neutral rule YAML, tests, lint script and Azure DevOps / GitHub Actions pipelines |
| Tune | [tuning/](./tuning) | Process and log for tuning changes (request, approve, test, roll back) |
| Measure | mitre-coverage/ | Coverage matrix: 32 techniques mapped to KQL and SPL use cases |

## Lint
```
python3 -m pip install pyyaml
python3 02-detection-engineering/use-case-management/detection-as-code/pipelines/lint_rules.py 02-detection-engineering
```
The lint scans every `.kql` and `.spl` under `use-cases-by-technology/`, checks the header keys, and confirms the register lists exactly those rules with the right path.
