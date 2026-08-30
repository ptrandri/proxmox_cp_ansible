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
- `vars/apps/n8n_queue.yml.example`: n8n-specific variable example.
- `inventories/production/hosts.yml.example`: VM inventory example.

## Install Requirements

```bash
ansible-galaxy collection install -r requirements.yml
pip install -r requirements.txt
```

`requirements.txt` is needed because the n8n role can generate a bcrypt hash from the Semaphore password field.

## Semaphore Survey Fields

These are the fields the Semaphore task template sends. They match the backend form one-to-one.

| Field | Variable | Required | Notes |
| --- | --- | --- | --- |
| VM IP | `vm_ip` | yes | Target VM address. |
| VM User | `vm_user` | yes | Normal user with sudo, e.g. `ubuntu`. `root` also works. |
| VM Password | `vm_pass` | yes | SSH password. Also used as the sudo password. |
| Application | `app_name` | yes | e.g. `n8n_queue`. |
| Enable Basic Auth | `app_basic_auth` | yes | `true` provisions the n8n owner account. |
| Domain Name | `app_domain` | no | Empty falls back to `http://<vm_ip>`. |
| Timezone | `app_timezone` | yes | e.g. `Asia/Jakarta`. |
| Admin Username | `app_username` | when basic auth | Owner email. |
| Admin Password | `app_password` | when basic auth | Owner password. |
| Clean Install | `app_clean_install` | yes | `true` wipes the stack and its volumes first. |

Mark `vm_pass` and `app_password` as sensitive in Semaphore.

Older names are still accepted so existing templates keep working: `vm_password`, `app_admin_username`/`n8n_username`, `app_admin_password`/`n8n_password`, and `n8n_clean_install`.

Optional extra fields:

| Variable | Purpose |
| --- | --- |
| `vm_port` | SSH port if not 22. |
| `vm_become_password` | Sudo password when it differs from `vm_pass`. |
| `vm_become` | Force privilege escalation on or off. |
| `vm_ssh_private_key_b64` / `vm_ssh_private_key` / `vm_ssh_private_key_file` | Key auth instead of `vm_pass`. |
| `vm_name` | Name of the generated host, default `dynamic-app-target`. |

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
- Environment: one that has Ansible, Docker collection requirements, and Python dependencies installed.
- Survey: the fields above.

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

## Deploy n8n Queue Mode

```bash
cp vars/apps/n8n_queue.yml.example vars/apps/n8n_queue.yml
ansible-playbook playbooks/deploy.yml -e @vars/apps/n8n_queue.yml
```

Minimum vars:

```yaml
app_name: "n8n_queue"
app_timezone: "Asia/Jakarta"
app_basic_auth: false
app_clean_install: false
```

With owner provisioning:

```yaml
app_basic_auth: true
app_username: "owner@example.com"
app_password: "strong-n8n-owner-password"
```

If `app_basic_auth` is `true`, the n8n owner account is provisioned from `app_username` and `app_password`.
If it is `false`, the owner variables are not sent to n8n and the user sets up email/password manually in the
n8n UI.

`app_domain` is optional. If set to `n8n.example.com`, the role uses `https://n8n.example.com`. Pass
`http://n8n.example.com` if HTTP is required. If left empty, the role uses `http://<vm_ip>` on the public port.

Default public port is `5178`, mapped to container port `5678`.

The default n8n image is pinned to `docker.n8n.io/n8nio/n8n:2.27.4` so owner provisioning from environment
variables works. You can override it with `n8n_image`, but keep it on n8n v2.17.0 or newer if you want
`app_username` and `app_password` to create/manage the owner account automatically.

Optional overrides:

```yaml
n8n_public_port: 5178
n8n_image: "docker.n8n.io/n8nio/n8n:2.27.4"
n8n_postgres_user: "n8n"
n8n_postgres_password: "strong-postgres-password"
n8n_redis_password: "strong-redis-password"
n8n_encryption_key: "long-random-encryption-key"
```

The role generates `n8n_postgres_user`, `n8n_postgres_password`, `n8n_redis_password`, and
`n8n_encryption_key` automatically if you do not pass them. Existing values are reused from `/opt/n8n/.env`
on redeploy.

Set `app_clean_install: true` only when you want a fresh deployment. It removes the existing n8n Compose
stack and deletes the n8n, Postgres, and Redis named volumes before redeploying.

If the controller cannot install `passlib[bcrypt]`, pass `n8n_password_hash` instead of `app_password`.

## Adding Another App

1. Create a new role under `roles/apps/<app_name>`.
2. Put app defaults in `roles/apps/<app_name>/defaults/main.yml`.
3. Put deployment tasks in `roles/apps/<app_name>/tasks/main.yml`.
4. Put compose/env templates in `roles/apps/<app_name>/templates`.
5. Add the app to `supported_apps` in `playbooks/deploy.yml`.
6. Add an example vars file under `vars/apps/<app_name>.yml.example`.

The new app automatically reuses `roles/docker_host`.
