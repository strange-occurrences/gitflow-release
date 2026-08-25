# Build Artifact — Porting Spec for the Real Project

**Status:** Experimental implementation verified on `strange-occurrences/gitflow-release` (`dev` branch).  
**Commits:** `10d1811` (workflow + schema), `f62eafe` (trigger script).  
**Last verified:** 2026-08-25 — 3 GitHub runs: 2× success (valid config), 1× failure (invalid config, correctly rejected).  
**Audience:** An agent that will re-implement this pattern in the production repo (different org / repo name).

---

## 1. What this does

A `workflow_dispatch` workflow that accepts a **single string input `config_b64`** — a base64-encoded JSON document. The workflow decodes, validates (syntax + JSON Schema), and pretty-prints the JSON. A local helper script does the same validation **before** dispatching, so bad configs fail fast on the caller side.

No Python or custom code is used for validation — only shell CLI tools that are trivially installable (`jq`, `ajv-cli`/`ajv-formats` via `npx`) and available on `ubuntu-latest`.

---

## 2. Target workflow contract

### 2.1 Trigger

```yaml
# .github/workflows/build-artifact.yml
on:
  workflow_dispatch:
    inputs:
      config_b64:
        description: "Base64-encoded JSON config (see .github/schemas/build-config.schema.json)"
        required: true
        type: string
```

Why `string` and not `environment`/`choice`/`boolean`: the workflow API only supports string-like `workflow_dispatch` inputs; complex payloads must be encoded. Base64 avoids YAML quoting/escaping problems with raw JSON on the `gh` command line.

### 2.2 Jobs

Exactly one job on `ubuntu-latest` (add more jobs after this pattern lands — keep the decode/validate/print gate first and `needs` it).

```yaml
jobs:
  build-artifact:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Decode config
        # base64 --decode → /tmp/config.json; jq empty for syntax
      - name: Validate config against JSON Schema
        # npx ajv validate -s .github/schemas/build-config.schema.json -d /tmp/config.json --strict=false --spec=draft7
      - name: Print decoded config
        # jq . /tmp/config.json + echo a few key fields
```

### 2.3 Step 1 — Decode + syntax check

```bash
set -euo pipefail
if [ -z "$CONFIG_B64" ]; then
  echo "::error::config_b64 input is empty"
  exit 1
fi
if ! echo "$CONFIG_B64" | base64 --decode > /tmp/config.json 2>/tmp/b64.err; then
  echo "::error::config_b64 is not valid base64"
  cat /tmp/b64.err
  exit 1
fi
if ! jq empty /tmp/config.json 2>/tmp/jq.err; then
  echo "::error::decoded config_b64 is not valid JSON"
  cat /tmp/jq.err
  exit 1
fi
echo "Decoded JSON is syntactically valid."
```

Environment wiring: `env: CONFIG_B64: ${{ inputs.config_b64 }}` on the step. This keeps the secret-like payload out of the `run:` interpolation and makes `set -x` safe.

### 2.4 Step 2 — JSON Schema validation

```bash
npm install --no-save --silent ajv-cli@5 ajv-formats@3 1>/dev/null
npx ajv validate \
  -s .github/schemas/build-config.schema.json \
  -d /tmp/config.json \
  --strict=false \
  --spec=draft7
```

- `--strict=false` — allows the `$schema` URI without ajv strict-mode complaints.
- `--spec=draft7` — must match the schema's `$schema`.
- Exit code is non-zero on validation failure → the job fails and is visible as a red check.

Alternative: pin `ajv-cli`/`ajv-formats` in a `package.json` devDependency and use `npm ci`. The inline `npm install --no-save` form was chosen to avoid adding a `package.json` to the repo for a single workflow.

### 2.5 Step 3 — Print

```bash
echo "=== Decoded config (pretty-printed) ==="
jq . /tmp/config.json
echo "=== End config ==="
echo "version=$(jq -r '.version' /tmp/config.json)"
echo "environment=$(jq -r '.environment' /tmp/config.json)"
echo "aws.region=$(jq -r '.aws.region' /tmp/config.json)"
```

This is the observable proof the payload arrived intact. Downstream steps/jobs should read `/tmp/config.json` (or `jq -r` individual fields) rather than re-decoding `inputs.config_b64`.

---

## 3. JSON Schema

File: `.github/schemas/build-config.schema.json` — draft-07.

### 3.1 Shape

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Build artifact config",
  "type": "object",
  "required": ["version", "environment", "aws", "terraform", "resources"],
  "additionalProperties": false,
  "properties": {
    "version":    { "type": "integer", "enum": [1] },
    "environment":{ "type": "string", "minLength": 1 },
    "aws": {
      "type": "object",
      "required": ["account_id", "account_label", "region", "local_profile"],
      "additionalProperties": false,
      "properties": {
        "account_id":    { "type": "string", "pattern": "^[0-9]{12}$" },
        "account_label": { "type": "string", "minLength": 1 },
        "region":        { "type": "string", "minLength": 1 },
        "local_profile": { "type": "string", "minLength": 1 }
      }
    },
    "terraform": {
      "type": "object",
      "required": ["state_account_id", "workspace", "var_file", "backend_config"],
      "additionalProperties": false,
      "properties": {
        "state_account_id": { "type": "string", "pattern": "^[0-9]{12}$" },
        "workspace":      { "type": "string", "minLength": 1 },
        "var_file":       { "type": "string", "minLength": 1 },
        "backend_config": { "type": "string", "minLength": 1 }
      }
    },
    "resources": {
      "type": "object",
      "required": ["name_prefix", "artifact_bucket"],
      "additionalProperties": false,
      "properties": {
        "name_prefix":     { "type": "string", "minLength": 1 },
        "artifact_bucket": { "type": "string", "minLength": 1 }
      }
    }
  }
}
```

- `additionalProperties: false` at every object level catches typos and drift.
- `version: { enum: [1] }` is the schema-version gate — bump it when you introduce breaking changes.
- `account_id` / `state_account_id` use `^[0-9]{12}$` (AWS account ID format). Adjust the pattern if the production IDs have a different shape.

### 3.2 Example payloads

**Valid (dummy/anonymized — use for tests; replace with real values in production):**

```json
{
  "version": 1,
  "environment": "poc",
  "aws": {
    "account_id": "111122223333",
    "account_label": "sandbox",
    "region": "us-east-1",
    "local_profile": "sandbox-admin"
  },
  "terraform": {
    "state_account_id": "444455556666",
    "workspace": "sandbox",
    "var_file": "environments/poc/terraform.tfvars",
    "backend_config": "environments/poc/backend.hcl"
  },
  "resources": {
    "name_prefix": "demo-infra-v2-poc",
    "artifact_bucket": "demo-infra-v2-poc-111122223333-artifacts"
  }
}
```

Save as e.g. `config.json`, then:

```bash
B64="$(base64 -w0 < config.json)"   # GNU; BSD fallback: base64 < config.json | tr -d '\n'
echo "$B64" | base64 --decode | jq . # sanity check
```

**Invalid — missing required fields (should fail ajv):**

```json
{ "version": 1, "environment": "poc" }
```

Expected error:

```
must have required property 'aws'
```

**Invalid — bad account_id pattern (should fail ajv):**

```json
{ "version": 1, "environment": "poc", "aws": { "account_id": "abc", ... } }
```

Expected error:

```
must match pattern "^[0-9]{12}$"  (instancePath: /aws/account_id)
```

---

## 4. Trigger script

File: `scripts/trigger-build-artifact.sh` (executable, `chmod +x`).

### 4.1 Purpose

Mirrors the workflow's validation locally so the caller fails fast without consuming a GitHub Actions run. On success it base64-encodes the file and dispatches via `gh workflow run`.

### 4.2 CLI

```
scripts/trigger-build-artifact.sh [options] <path-to-json>

Options:
  --ref <branch>       Git ref to run on (default: dev)
  --workflow <name>    Workflow name or file (default: "Build Artifact")
  --schema <path>      Schema path (default: .github/schemas/build-config.schema.json)
  --dry-run            Validate + print base64 + decoded JSON, do not dispatch
  --watch              After dispatch, watch the run until completion (gh run watch)
  -h, --help           Help

Requires: jq, base64, gh (and for schema: npx with ajv-cli)
```

### 4.3 Key implementation details

- Portability: base64 without newlines uses a GNU/BSD branch:

  ```bash
  if base64 -w0 </dev/null >/dev/null 2>&1; then
    B64="$(base64 -w0 < "$CONFIG_PATH")"
  else
    B64="$(base64 < "$CONFIG_PATH" | tr -d '\n')"
  fi
  ```

- Dispatch:

  ```bash
  gh workflow run "$WORKFLOW" --ref "$REF" -f config_b64="$B64"
  ```

- `--dry-run` prints the pretty JSON + base64 length and the equivalent `gh workflow run` command without dispatching.
- `--watch` resolves the latest run ID via `gh run list --workflow="$WORKFLOW" --limit 1 --json databaseId` then `gh run watch "$RUN_ID"`.

### 4.4 Examples

Dry-run (no GitHub call):

```bash
cat > /tmp/poc.json <<'JSON'
{
  "version": 1,
  "environment": "poc",
  "aws": {
    "account_id": "111122223333",
    "account_label": "sandbox",
    "region": "us-east-1",
    "local_profile": "sandbox-admin"
  },
  "terraform": {
    "state_account_id": "444455556666",
    "workspace": "sandbox",
    "var_file": "environments/poc/terraform.tfvars",
    "backend_config": "environments/poc/backend.hcl"
  },
  "resources": {
    "name_prefix": "demo-infra-v2-poc",
    "artifact_bucket": "demo-infra-v2-poc-111122223333-artifacts"
  }
}
JSON

scripts/trigger-build-artifact.sh --dry-run /tmp/poc.json
# → Validates (jq + ajv), prints JSON, prints base64 length, does not dispatch.

scripts/trigger-build-artifact.sh /tmp/poc.json
# → Validates, then: gh workflow run "Build Artifact" --ref dev -f config_b64=...

scripts/trigger-build-artifact.sh --watch /tmp/poc.json
# → Validates, dispatches, then watches until completion.

scripts/trigger-build-artifact.sh --ref main --watch /tmp/poc.json
# → Dispatch to a different branch.
```

---

## 5. Production adaptation checklist

Copy this to a tracking issue and check off:

- [ ] **Repo/branch names** — replace `dev` default ref with the production default (e.g. `main`). The workflow's `on.workflow_dispatch.inputs` has no branch filter; the `--ref` in the trigger script controls it.
- [ ] **Workflow name** — if the production workflow is called differently, update `--workflow` default in the trigger script and the `gh workflow run` lookup.
- [ ] **Real identifiers** — replace dummy `111122223333` / `444455556666` / `demo-infra-v2-poc` in examples and test fixtures with the actual `account_id`, `state_account_id`, `name_prefix`, `artifact_bucket` for the target environment. Keep dummy placeholders **out** of production — the experimental repo deliberately uses anonymized values.
- [ ] **Schema path** — confirm `.github/schemas/build-config.schema.json` is the right location in the production tree (or move it; update both workflow Step 2 and the trigger script's `--schema` default).
- [ ] **Ajv pinning** — decide between inline `npm install --no-save ajv-cli@5 ajv-formats@3` (zero `package.json` churn) vs. a committed `package.json` + `npm ci` (reproducible pin). For production, prefer a pinned `package.json`.
- [ ] **Permissions** — the workflow needs `contents: read` only for this gate; add `id-token`, `actions: write`, etc. when downstream jobs need them.
- [ ] **Timeouts / concurrency** — add `concurrency` and per-step `timeout-minutes` matching production conventions.
- [ ] **Secrets / env** — wire `aws.account_id` / `terraform.state_account_id` into `aws-actions/configure-aws-credentials` or OIDC role assumption after the validation gate (validation must stay before any credential use).
- [ ] **Manual `gh` alternative** — document the escape hatch for operators without the helper script:

  ```bash
  B64="$(base64 -w0 < path/to/config.json)"
  gh workflow run "Build Artifact" --ref <branch> -f config_b64="$B64"
  GITHUB_TOKEN="$(pass psst/github/github_token)" gh workflow run "Build Artifact" --ref <branch> -f config_b64="$B64"
  # or: base64 < config.json | tr -d '\n' on macOS/BSD
  ```

- [ ] **Negative test** — dispatch with a deliberately invalid payload (missing `aws`, bad `account_id`) and confirm the run fails at the `Validate config against JSON Schema` step.

---

## 6. Verification that passed on the experimental repo

Commands run before this spec was written (copy them to validate the port):

```bash
# 1. Workflow is valid
actionlint -oneline .github/workflows/build-artifact.yml

# 2. Schema is valid JSON
jq empty .github/schemas/build-config.schema.json

# 3. Local ajv checks (without GitHub)
DUMMY='{"version":1,"environment":"poc","aws":{"account_id":"111122223333","account_label":"sandbox","region":"us-east-1","local_profile":"sandbox-admin"},"terraform":{"state_account_id":"444455556666","workspace":"sandbox","var_file":"environments/poc/terraform.tfvars","backend_config":"environments/poc/backend.hcl"},"resources":{"name_prefix":"demo-infra-v2-poc","artifact_bucket":"demo-infra-v2-poc-111122223333-artifacts"}}'
echo "$DUMMY" | jq .
B64="$(echo -n "$DUMMY" | base64 -w0)"
echo "$B64" | base64 --decode > /tmp/config.json
jq empty /tmp/config.json
npx --yes ajv-cli@5 validate -s .github/schemas/build-config.schema.json -d /tmp/config.json --strict=false --spec=draft7
# negative:
echo '{"version":1,"environment":"poc"}' > /tmp/bad.json
npx --yes ajv-cli@5 validate -s .github/schemas/build-config.schema.json -d /tmp/bad.json --strict=false --spec=draft7  # → exit 1

# 4. Trigger script — dry-run + live
scripts/trigger-build-artifact.sh --dry-run /tmp/demo-config.json
GITHUB_TOKEN="$(pass psst/github/github_token)" scripts/trigger-build-artifact.sh /tmp/demo-config.json
gh run list --workflow="Build Artifact" --limit 3 --json databaseId,conclusion,status --jq '.[]'

# 5. Negative workflow run (should fail at ajv step)
BAD_B64="$(echo -n '{"version":1,"environment":"poc"}' | base64 -w0)"
GITHUB_TOKEN="$(pass psst/github/github_token)" gh workflow run "Build Artifact" --ref dev -f config_b64="$BAD_B64"
# then: gh run view --log <id> | grep -i "invalid\|error"
```

Observed runs on `strange-occurrences/gitflow-release@dev`:

| Run ID      | Payload | Result    | Notable log line |
|-------------|---------|-----------|------------------|
| 32831719410 | valid dummy (direct `gh workflow run`) | `success` | `Decoded JSON is syntactically valid.` → `/tmp/config.json valid` → pretty-printed JSON |
| 32831787050 | invalid (missing fields) | `failure` | `must have required property 'aws'` |
| 32834833731 | valid dummy (via `scripts/trigger-build-artifact.sh`) | `success` | same as 32831719410, local pre-validation also `valid` |

---

## 7. Files to copy

```
.github/workflows/build-artifact.yml
.github/schemas/build-config.schema.json
scripts/trigger-build-artifact.sh
```

No other repo changes are required. The pattern is self-contained; extend the `build-artifact` job (or add downstream jobs `needs: build-artifact`) once the gate is stable.

---

## 8. Auth reminder (do not print the token)

All `gh` calls in this repo use:

```bash
GITHUB_TOKEN="$(pass psst/github/github_token)" gh ...
```

Never `echo` the token value. The same pattern applies in production (different `pass` entry or a GitHub Actions `secrets.GITHUB_TOKEN` / PAT as appropriate).
