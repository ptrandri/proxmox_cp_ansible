# Ansible App Deployment

This repository is structured for deploying multiple Docker Compose based apps through Ansible Semaphore.

The shared flow is:

1. Semaphore passes VM SSH details through a survey (or through inventory).
2. `playbooks/deploy.yml` builds the target host and reads `app_name`.
3. `roles/docker_host` prepares Docker and Docker Compose on the VM.
4. The selected app role deploys its own templates, secrets, volumes, and compose stack.

## Structure

- `playbooks/deploy.yml`: the single entrypoint for every app.
- `roles/docker_host`: shared Docker host setup.
- `roles/app_common`: shared domain/timezone/clean-install resolution, deploy, health gate, diagnostics.
- `roles/apps/n8n_queue`: n8n queue-mode deployment.
- `roles/apps/openclaw`: openclaw deployment.
- `roles/apps/router9`: 9router deployment.
- `vars/semaphore_env.yml`: maps Semaphore Environment variables to Ansible variables.
- `vars/apps/*.yml.example`: per-app variable examples for local runs.

## Install Requirements

```bash
ansible-galaxy collection install -r requirements.yml
pip install -r requirements.txt
```

`requirements.txt` is needed because the n8n role can generate a bcrypt hash from the Semaphore password field.

## Where To Put Variables

There is one canonical name per setting. No aliases.

| Source | Precedence | Use for |
| --- | --- | --- |
| The task `environment` JSON sent by the backend (also survey fields, `-e`) | highest | Values that change per deployment. |
| Semaphore Environment > Environment Variables | middle | Stable config shared by every deployment. |
| Role defaults in `roles/*/defaults/main.yml` | lowest | Values that rarely change at all. |

Extra variables outrank environment variables, so anything the backend sends per run always wins. An empty or
unset environment variable falls through to the default. The mapping lives in `vars/semaphore_env.yml`.

Do not use Semaphore Environment > **Extra Variables** for anything the backend may need to override: that box
is itself extra variables, so it sits at the same precedence as the payload.

### Send from n8n per deployment

These go in the task `environment` JSON when n8n calls the Semaphore API. They do not need to be declared as
survey fields.

Every app shares the same connection and domain contract, differing only in the `<prefix>` and in its own
app-specific fields.

| Variable | Type | Required | Notes |
| --- | --- | --- | --- |
| `vm_ip` | string | yes | Target VM address. |
| `vm_user` | string | yes | Normal user with sudo, e.g. `ubuntu`. `root` also works. |
| `vm_pass` | string | yes | SSH password, also used as the sudo password. |
| `workload_type` | string | yes | `qemu` or `lxc`. |
| `app_name` | string | yes | `n8n_queue`, `openclaw`, or `9router`. No default - a missing value fails. |
| `<prefix>_clean_install` | bool | yes | `true` removes the stack and its volumes first. |
| `<prefix>_custom_domain` | bool | yes | `true` uses `<prefix>_domain`, `false` uses `<prefix>_generated_domain`. |
| `<prefix>_domain` | string | when `<prefix>_custom_domain` is `true` | e.g. `n8n.ptrandri.id`. |
| `<prefix>_generated_domain` | string | when `<prefix>_custom_domain` is `false` | e.g. `n8n-71bd257c0d.bataminfra.id`. |
| `<prefix>_timezone` | string | no | Defaults to `Asia/Jakarta`. |

The prefix per app, and the app-specific fields on top of the shared contract:

| `app_name` | Prefix | Port | App-specific fields |
| --- | --- | --- | --- |
| `n8n_queue` | `n8n` | 5178 | `n8n_basic_auth_user` (email, required for owner provisioning), `n8n_basic_auth_password` |
| `openclaw` | `openclaw` | 18789 | `openclaw_gateway_token` (optional, generated when omitted) |
| `9router` | `router9` | 20128 | `router9_initial_password` (required), `router9_jwt_secret` and `router9_api_key_secret` (optional, generated when omitted) |

**9router uses the `router9_` prefix, not `9router_`**, because an Ansible variable cannot start with a digit.
`app_name` still accepts `9router`. The marketplace `input_schema` keys must use `router9_`.

Customer domain:

```json
{
  "workload_type": "qemu",
  "n8n_clean_install": true,
  "n8n_custom_domain": true,
  "vm_ip": "192.168.50.10",
  "vm_user": "ubuntu",
  "vm_pass": "xxxxxxxx",
  "n8n_basic_auth_user": "owner@ptrandri.id",
  "n8n_basic_auth_password": "xxxxxxx!",
  "n8n_domain": "n8n.ptrandri.id"
}
```

Generated domain:

```json
{
  "workload_type": "qemu",
  "n8n_clean_install": true,
  "n8n_custom_domain": false,
  "vm_ip": "192.168.50.10",
  "vm_user": "ubuntu",
  "vm_pass": "xxxxxxxx",
  "n8n_basic_auth_user": "owner@bataminfra.id",
  "n8n_basic_auth_password": "xxxxxxx",
  "n8n_generated_domain": "n8n-71bd257c0d.bataminfra.id"
}
```

Only the selected domain is read. The unused one can be omitted or sent empty.

The owner account is provisioned when `n8n_basic_auth_user` and `n8n_basic_auth_password` are both non-empty.
Omit them and the user completes email/password setup in the n8n UI.

`n8n_basic_auth_user` must be an email address. n8n stores the instance owner as an email, so a plain name such
as `admin` is expected to be rejected and would leave an instance nobody can log into. The playbook fails early
with that message. Set `n8n_owner_email_strict: false` if you want to deploy a non-email owner anyway.

### Key into the Semaphore Environment

Everything below is optional and only needed to override a default. Every payload variable also has an
environment form if you want a static default for it.

| Environment variable | Ansible variable | Default |
| --- | --- | --- |
| `VM_USER` | `vm_user` | `root` |
| `VM_PORT` | `vm_port` | 22 |
| `VM_BECOME_PASSWORD` | `vm_become_password` | falls back to `vm_pass` |
| `VM_SSH_PRIVATE_KEY_B64` / `VM_SSH_PRIVATE_KEY_FILE` | key auth | empty |
| `WORKLOAD_TYPE` | `workload_type` | `qemu` |
| `N8N_TIMEZONE` / `OPENCLAW_TIMEZONE` / `ROUTER9_TIMEZONE` | `<prefix>_timezone` | `Asia/Jakarta` |
| `N8N_PUBLIC_PORT` / `OPENCLAW_PUBLIC_PORT` / `ROUTER9_PUBLIC_PORT` | `<prefix>_public_port` | 5178 / 18789 / 20128 |
| `N8N_IMAGE` / `OPENCLAW_IMAGE` / `ROUTER9_IMAGE` | `<prefix>_image` | pinned n8n, `openclaw:latest`, `9router:latest` |
| `N8N_WORKER_CONCURRENCY` | `n8n_worker_concurrency` | `15` |
| `N8N_OWNER_EMAIL_STRICT` | `n8n_owner_email_strict` | `true` |

A practical Environment is just the stable half:

```json
{
  "VM_USER": "ubuntu",
  "WORKLOAD_TYPE": "qemu",
  "N8N_TIMEZONE": "Asia/Jakarta",
  "OPENCLAW_TIMEZONE": "Asia/Jakarta",
  "ROUTER9_TIMEZONE": "Asia/Jakarta"
}
```

`APP_NAME` is deliberately absent and has no default anywhere. One template serves every app, so a payload
without `app_name` fails with "app_name is required" instead of quietly installing n8n.

### Domain resolution

`n8n_custom_domain` selects the source. A bare hostname becomes `https://<host>`; pass a full `http://...` URL
to force plain HTTP. The selected domain is required, so a run cannot silently deploy to a wrong address.

## Workload Type

`workload_type` accepts `qemu` (also `kvm`, `vm`) and `lxc` (also `container`).

Docker host setup is the same for both. The value is used for validation and for error reporting: if Docker
fails to start on an `lxc` workload, the playbook says that the Proxmox container needs `nesting=1` and
`keyctl=1`, which cannot be set from inside the container.

## Normal User With Sudo

`vm_user` is expected to be a normal user (for example `ubuntu`) that can escalate to root:

- Privilege escalation is enabled automatically whenever `vm_user` is not `root`, using `sudo` to `root`.
- The sudo password defaults to `vm_pass`. Set `vm_become_password` only when the sudo password differs.
  Passwordless sudo (`NOPASSWD`) also works.
- `roles/docker_host` adds `vm_user` to the `docker` group, so the user can run `docker` and
  `docker compose` on the VM afterwards without sudo.
- Before any deployment task runs, the playbook checks that the user really reaches uid 0 and fails
  with a clear message if sudo is missing or the password is wrong.

If `vm_user` is `root`, escalation is skipped automatically, because many minimal images do not ship `sudo`.

The error `/bin/sh: sudo: not found` means the target user is root on a minimal image, or Semaphore
ran the localhost inventory instead of the dynamic VM. Make sure `vm_ip` is passed.

## Semaphore Template Setup

Create an Ansible Playbook template in Semaphore with:

- Repository: this repository.
- Playbook path: `playbooks/deploy.yml`.
- Inventory: a localhost inventory. The target VM always comes from `vm_ip`.
- Environment: the Environment holding the stable variables from "Where To Put Variables".
- Survey: only the fields the backend does not send itself.

Localhost inventory for survey-driven runs:

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
```

`playbooks/deploy.yml` builds the target host from `vm_ip` with `add_host` and deploys to it. `vm_ip`,
`vm_user`, and a credential are required; the playbook fails immediately if any is missing.

Do not create self-referencing extra vars like `vm_ip: "{{ vm_ip }}"` unless your Semaphore webhook template
explicitly renders placeholders before Ansible runs.

## SSH Key From A Semaphore Field

For a single-line field, use base64:

```yaml
vm_ssh_private_key_b64: "ONE_LINE_BASE64_PRIVATE_KEY"
```

Generate it on Linux/macOS:

```bash
base64 -w 0 ~/.ssh/id_ed25519
```

If `-w` is not supported:

```bash
base64 ~/.ssh/id_ed25519 | tr -d '\n'
```

On Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.ssh\id_ed25519"))
```

If Semaphore gives you a multi-line textarea, use `vm_ssh_private_key` instead. If Semaphore stores the key
as a file on the runner, pass `vm_ssh_private_key_file`.

The matching public key must already exist on the VM in the target user's `~/.ssh/authorized_keys`, for
example `/home/ubuntu/.ssh/authorized_keys` when `vm_user` is `ubuntu`. A public key by itself cannot be used
by Ansible to log in; Ansible needs the private key or a password.

## Deploy Locally

```bash
cp vars/apps/n8n_queue.yml.example vars/apps/n8n_queue.yml
ansible-playbook playbooks/deploy.yml -e @vars/apps/n8n_queue.yml

cp vars/apps/openclaw.yml.example vars/apps/openclaw.yml
ansible-playbook playbooks/deploy.yml -e @vars/apps/openclaw.yml

cp vars/apps/router9.yml.example vars/apps/router9.yml
ansible-playbook playbooks/deploy.yml -e @vars/apps/router9.yml
```

### n8n

Default public port is `5178`, mapped to container port `5678`.

The default n8n image is pinned to `docker.n8n.io/n8nio/n8n:2.27.4` so owner provisioning from environment
variables works. Override it with `n8n_image`, but keep it on n8n v2.17.0 or newer if you want
`n8n_basic_auth_user` and `n8n_basic_auth_password` to create/manage the owner account automatically.

The role generates `n8n_postgres_user`, `n8n_postgres_password`, `n8n_redis_password`, and `n8n_encryption_key`
automatically if you do not pass them. Existing values are reused from `/opt/n8n/.env` on redeploy.

Set `n8n_clean_install: true` only when you want a fresh deployment. It removes the existing n8n Compose stack
and deletes the n8n, Postgres, and Redis named volumes before redeploying.

If the controller cannot install `passlib[bcrypt]`, pass `n8n_password_hash` instead of
`n8n_basic_auth_password`.

### openclaw

Published on `18789`. The config directory is a named volume (`openclaw-config`) rather than a host bind mount,
so the image's own user owns it and there is no uid mismatch on first start.

`openclaw_gateway_token` is generated and persisted on first deploy. Pass it explicitly to pin a known token.

The upstream compose file declares `network_mode: host` together with `ports:` and `networks:`, which Docker
Compose rejects as mutually exclusive. This role publishes port `18789` on a bridge network instead, which is
also what a reverse proxy in front of the instance needs. Set `network_mode: host` only if openclaw has to
discover devices on the VM's LAN, and then drop the port mapping.

`openclaw_domain` / `openclaw_generated_domain` are still required, because the platform hands the customer
that hostname, but nothing in this repo consumes it yet: openclaw is reached on its published port until a
reverse-proxy role exists. The same is true for 9router.

openclaw exposes no documented readiness endpoint, so the health gate waits for the published port to accept
connections rather than polling an invented HTTP path.

### 9router

Published on `20128`, health-gated on `/api/health`.

`router9_initial_password` is required and sets the first-login admin password. `JWT_SECRET` and
`API_KEY_SECRET` are generated and persisted on first deploy.

The container healthcheck uses `curl`, matching the upstream compose file. If the image does not ship `curl`,
the container reports unhealthy even while serving; the Ansible-side gate polls from the host and is not
affected.

## Adding Another App

`roles/app_common` owns everything that is the same for every app, so a new role only describes what is
actually different about that app.

1. Create `roles/apps/<app>/defaults/main.yml` setting at least:
   - `app_prefix` - the variable prefix the customer form and payload use. Must start with a letter.
   - `app_project_dir` - where the stack lives on the VM.
   - `app_stack_volumes` - named volumes to delete on a clean install, prefixed with the Compose project name.
   - `app_log_services` - Compose services whose logs are collected when a deploy fails.
   - `app_health_mode` plus `app_health_url` (http) or `app_health_port` (port), or `none` to skip the gate.
2. Create `roles/apps/<app>/tasks/main.yml`. Include `app_common` first to resolve the shared input, then
   `app_common` with `tasks_from: load_secrets`, render the templates, `tasks_from: save_secrets`, and finish
   with `tasks_from: deploy`.
3. Put the compose and env templates in `roles/apps/<app>/templates`. They read the shared facts
   `app_service_url`, `app_host`, `app_protocol`, `app_secure_cookie`, and `app_timezone_effective`.
4. Add the app to `supported_apps` in `playbooks/deploy.yml`.
5. Add the `<prefix>_*` block to `vars/semaphore_env.yml` and an example under `vars/apps/<app>.yml.example`.

Do not add a variable to `roles/app_common/defaults/main.yml` that an app role also sets. `app_common` is
included from inside the app role, so its defaults load later and would override the app's own value at the
same precedence level. Shared settings are read with an inline `default()` in the tasks instead.

Every app automatically reuses `roles/docker_host` and the domain, timezone, clean-install, health-gate and
failure-diagnostics behaviour.

## Generated Secrets

`app_common` persists generated secrets in `<app_project_dir>/.generated-secrets.yml` (mode 0600) and reuses
them on redeploy, so a rerun does not rotate a token that existing data depends on. A clean install removes the
stack volumes but keeps that file, so the instance keeps its identity unless you delete it explicitly.

n8n predates this and keeps its generated secrets in `/opt/n8n/.env`; it was left that way deliberately,
because switching an existing instance to the shared file would regenerate its encryption key and orphan every
stored credential.
