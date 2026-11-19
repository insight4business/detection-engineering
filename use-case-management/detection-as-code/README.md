# Detection as code

Keep detections in version control, review them like code, and validate them automatically before they reach the SIEM. This folder is a generic starting point with placeholders. It does not describe any existing production pipeline.

## Layout
```
detection-as-code/
  rules/       one YAML definition per detection (tool-neutral schema, see example)
  tests/       test cases per rule (positive and negative events, expected result)
  pipelines/   validation pipelines and the lint script
    lint_rules.py          YAML syntax and header lint (Python 3, PyYAML)
    azure-pipelines.yml    example for Azure DevOps
    github-actions.yml     example for GitHub Actions
```
The query files themselves live in [../../use-cases-by-technology](../../use-cases-by-technology) (one folder per technology, with `kql/` and `spl/` inside). A rule definition points to its query file.

## What the pipeline validates
1. All YAML files parse.
2. Every `.kql` and `.spl` file carries the required header keys: id, name, mitre_tactic, mitre_technique, severity, data_source, false_positives, status, last_review.
3. Technique ids match the ATT&CK format, severity and status use allowed values, ids are unique.
4. The use case register lists exactly the rule files that exist.
5. (GitHub example) The repository sanitization gate passes.

Run locally:
```
python3 -m pip install pyyaml
python3 02-detection-engineering/use-case-management/detection-as-code/pipelines/lint_rules.py 02-detection-engineering
```

## Suggested workflow
1. Branch, edit the rule or add one from [../use-case-template.yml](../use-case-template.yml).
2. Update the register and mitre-coverage.csv.
3. Add or update tests under `tests/` and follow [testing/README.md](../testing/README.md).
4. Open a pull request; the pipeline lints; a second person reviews logic, thresholds and sanitization.
5. After merge, a deployment stage (not included, add your own) publishes to a test workspace first, then production behind an approval gate.
6. Record tuning changes in the tuning log (tuning-process.md).

## Adapting
Replace `<REPO_FOLDER>`, `<SERVICE_CONNECTION>` and `<ENVIRONMENT>` in the pipeline files. Add a deployment step that maps rule YAML to your SIEM format using the platform tools you already use.
