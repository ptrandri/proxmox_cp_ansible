# Ansible App Deployment

This repository is structured for deploying multiple Docker Compose based apps through Ansible Semaphore.

The shared flow is:

1. Semaphore passes VM SSH details through a survey (or through inventory).
2. `playbooks/deploy.yml` builds the target host and reads `app_name`.
3. `roles/docker_host` prepares Docker and Docker Compose on the VM.
4. The selected app role deploys its own templates, secrets, volumes, and compose stack.

## Structure

- `playbooks/deploy.yml`: the single entrypoint for all apps, static inventory or dynamic `vm_ip`.
- `playbooks/deploy_dynamic.yml`: wrapper that requires `vm_ip`, then imports `deploy.yml`.
- `playbooks/deploy_n8n.yml`: backward-compatible n8n-only wrapper, imports `deploy.yml`.
- `roles/docker_host`: shared Docker host setup.
- `roles/apps/n8n_queue`: n8n queue-mode deployment.
- `vars/semaphore_env.yml`: maps Semaphore Environment variables to Ansible variables.
- `vars/apps/n8n_queue.yml.example`: n8n-specific variable example.
- `inventories/production/hosts.yml.example`: VM inventory example.

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

| Variable | Type | Required | Notes |
| --- | --- | --- | --- |
| `vm_ip` | string | yes | Target VM address. |
| `vm_user` | string | yes | Normal user with sudo, e.g. `ubuntu`. `root` also works. |
| `vm_pass` | string | yes | SSH password, also used as the sudo password. |
| `workload_type` | string | yes | `qemu` or `lxc`. |
| `n8n_clean_install` | bool | yes | `true` removes the stack and its volumes first. |
| `n8n_custom_domain` | bool | yes | `true` uses `n8n_domain`, `false` uses `n8n_generated_domain`. |
| `n8n_domain` | string | when `n8n_custom_domain` is `true` | e.g. `n8n.ptrandri.id`. |
| `n8n_generated_domain` | string | when `n8n_custom_domain` is `false` | e.g. `n8n-71bd257c0d.bataminfra.id`. |
| `n8n_basic_auth_user` | string | for owner provisioning | Must be an email address. |
| `n8n_basic_auth_password` | string | for owner provisioning | Owner password. |

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

Everything below is optional and only needed to override a default.

| Environment variable | Ansible variable | Default |
| --- | --- | --- |
| `VM_USER` | `vm_user` | `root` |
| `VM_PORT` | `vm_port` | 22 |
| `VM_BECOME_PASSWORD` | `vm_become_password` | falls back to `vm_pass` |
| `VM_SSH_PRIVATE_KEY_B64` | `vm_ssh_private_key_b64` | empty |
| `VM_SSH_PRIVATE_KEY_FILE` | `vm_ssh_private_key_file` | empty |
| `WORKLOAD_TYPE` | `workload_type` | `qemu` |
| `APP_NAME` | `app_name` | `n8n_queue` |
| `N8N_TIMEZONE` | `n8n_timezone` | `Asia/Jakarta` |
| `N8N_PUBLIC_PORT` | `n8n_public_port` | `5178` |
| `N8N_IMAGE` | `n8n_image` | `docker.n8n.io/n8nio/n8n:2.27.4` |
| `N8N_WORKER_CONCURRENCY` | `n8n_worker_concurrency` | `15` |
| `N8N_OWNER_EMAIL_STRICT` | `n8n_owner_email_strict` | `true` |
| `N8N_CLEAN_INSTALL` | `n8n_clean_install` | `false` |
| `N8N_CUSTOM_DOMAIN` | `n8n_custom_domain` | `false` |
| `N8N_DOMAIN` | `n8n_domain` | empty |
| `N8N_GENERATED_DOMAIN` | `n8n_generated_domain` | empty |
| `VM_IP` | `vm_ip` | empty |
| `VM_PASS` | `vm_pass` | empty |
| `N8N_BASIC_AUTH_USER` | `n8n_basic_auth_user` | empty |
| `N8N_BASIC_AUTH_PASSWORD` | `n8n_basic_auth_password` | empty |

A practical Environment is just the stable half:

```json
{
  "VM_USER": "ubuntu",
  "WORKLOAD_TYPE": "qemu",
  "APP_NAME": "n8n_queue",
  "N8N_TIMEZONE": "Asia/Jakarta"
}
```

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
- Inventory: a localhost inventory (the VM comes from the survey), or a static VM inventory.
- Environment: the Environment holding the stable variables from "Where To Put Variables".
- Survey: only the fields the backend does not send itself.

Localhost inventory for survey-driven runs:

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
```

`playbooks/deploy.yml` targets `hosts: all` for static inventories. If `vm_ip` is provided, it switches to
dynamic mode, creates the target host with `add_host`, and deploys to that VM instead of localhost.

Do not create self-referencing extra vars like `vm_ip: "{{ vm_ip }}"` unless your Semaphore webhook template
explicitly renders placeholders before Ansible runs.

## Static Inventory

```bash
cp inventories/production/hosts.yml.example inventories/production/hosts.yml
```

Password example with a normal sudo user:

```yaml
all:
  children:
    app_servers:
      hosts:
        app-prod:
          ansible_host: "1.2.3.4"
          ansible_user: "ubuntu"
          ansible_password: "YOUR_SSH_PASSWORD"
          ansible_become: true
          ansible_become_method: sudo
          ansible_become_user: root
          ansible_become_password: "YOUR_SUDO_PASSWORD"
```

SSH key example:

```yaml
all:
  children:
    app_servers:
      hosts:
        app-prod:
          ansible_host: "1.2.3.4"
          ansible_user: "ubuntu"
          ansible_ssh_private_key_file: "~/.ssh/id_rsa"
          ansible_become: true
```

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

## Deploy n8n Queue Mode Locally

```bash
cp vars/apps/n8n_queue.yml.example vars/apps/n8n_queue.yml
ansible-playbook playbooks/deploy.yml -e @vars/apps/n8n_queue.yml
```

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

## Adding Another App

1. Create a new role under `roles/apps/<app_name>`.
2. Put app defaults in `roles/apps/<app_name>/defaults/main.yml`.
3. Put deployment tasks in `roles/apps/<app_name>/tasks/main.yml`.
4. Put compose/env templates in `roles/apps/<app_name>/templates`.
5. Add the app to `supported_apps` in `playbooks/deploy.yml`.
6. Add an example vars file under `vars/apps/<app_name>.yml.example`.

The new app automatically reuses `roles/docker_host`.
