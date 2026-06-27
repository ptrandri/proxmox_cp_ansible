# Ansible App Deployment

This repository is structured for deploying multiple Docker Compose based apps through Ansible Semaphore.

The shared flow is:

1. Semaphore passes VM SSH details through inventory.
2. `roles/docker_host` prepares Docker and Docker Compose on the VM.
3. `playbooks/deploy.yml` reads `app_name`.
4. The selected app role deploys its own templates, secrets, volumes, and compose stack.

## Structure

- `playbooks/deploy.yml`: generic Semaphore entrypoint for all apps.
- `playbooks/deploy_dynamic.yml`: generic entrypoint when `vm_ip` comes from a Semaphore survey/webhook.
- `playbooks/deploy_n8n.yml`: backward-compatible n8n-only wrapper.
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

## Inventory

Create a local inventory:

```bash
cp inventories/production/hosts.yml.example inventories/production/hosts.yml
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
```

Password example:

```yaml
all:
  children:
    app_servers:
      hosts:
        app-prod:
          ansible_host: "1.2.3.4"
          ansible_user: "root"
          ansible_password: "YOUR_SSH_PASSWORD"
          ansible_become_password: "YOUR_SUDO_PASSWORD"
```

## Generic Semaphore Fields

Use these common fields for every app:

| Label | Variable | Type | Required |
| --- | --- | --- | --- |
| Application | `app_name` | select | yes |
| Domain Name | `domain` | text | yes |
| Admin Username | `app_admin_username` | text/email | app-dependent |
| Admin Password | `app_admin_password` | generated password / sensitive | app-dependent |
| Timezone | `timezone` | select | yes |

For n8n, set `app_name` to `n8n_queue`.

The n8n role also accepts the older aliases `n8n_username` and `n8n_password`, but `app_admin_username` and `app_admin_password` are preferred for multi-app automation.

## Semaphore Template Setup

Create an Ansible Playbook template in Semaphore with:

- Repository: this repository.
- Playbook path: `playbooks/deploy.yml`.
- Inventory: a Semaphore inventory containing the target VM.
- Environment: one that has Ansible, Docker collection requirements, and Python dependencies installed.
- Survey/Extra Variables: the generic fields above plus app-specific secrets.

`playbooks/deploy.yml` targets `hosts: all` by default for static inventories. If `vm_ip` is provided, it switches to dynamic mode, creates the target host with `add_host`, and deploys to that VM instead of localhost.

## Dynamic VM IP From Semaphore

If `vm_ip` is dynamic, use `playbooks/deploy.yml` or `playbooks/deploy_dynamic.yml`. The generic `deploy.yml` now supports both static inventory and dynamic VM input.

In Semaphore, create a simple localhost inventory:

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
```

Then create a task template with:

- Playbook path: `playbooks/deploy_dynamic.yml`
- Inventory: the localhost inventory above
- Survey/Webhook fields:
  - `vm_ip`
  - `vm_user`
  - `vm_port` if SSH is not on port 22
  - `vm_password`, `vm_ssh_private_key`, or `vm_ssh_private_key_file`
  - `vm_become_password` if sudo password is different
  - `app_name`
  - `domain`
  - `timezone`
  - app-specific variables

If these are Semaphore survey fields, Semaphore passes them to Ansible automatically. Do not create self-referencing extra vars like `vm_ip: "{{ vm_ip }}"` unless your Semaphore webhook template explicitly renders placeholders before Ansible runs.

For n8n, the resulting variables should be equivalent to:

```yaml
app_name: "n8n_queue"
vm_ip: "1.2.3.4"
vm_user: "root"
vm_password: "ssh-password"
vm_become_password: "sudo-password"

domain: "n8n.example.com"
timezone: "Asia/Singapore"
app_admin_username: "owner@example.com"
app_admin_password: "n8n-owner-password"
n8n_postgres_password: "postgres-password"
n8n_redis_password: "redis-password"
n8n_encryption_key: "long-random-encryption-key"
```

Mark password fields as sensitive in Semaphore. The playbook uses `add_host` to create the target VM at runtime, then deploys to that generated host.

For SSH key authentication from a dynamic Semaphore field, add a sensitive textarea field named:

```yaml
vm_ssh_private_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
```

The matching public key must already exist on the VM in the target user's `~/.ssh/authorized_keys`. For example, if `vm_user` is `root`, the public key must be in `/root/.ssh/authorized_keys`. A public key by itself cannot be used by Ansible to log in; Ansible needs the private key or a password.

If Semaphore stores the private key as a file on the runner instead, pass:

```yaml
vm_ssh_private_key_file: "/path/to/private_key"
```

If `vm_user` is `root`, the dynamic playbook disables sudo automatically because many minimal VM images do not include `sudo`. For non-root users, it uses sudo by default. You can override this with:

```yaml
vm_become: false
```

The error `/bin/sh: sudo: not found` usually means Semaphore ran the static inventory localhost instead of the dynamic VM, or the target user is root on a minimal image. Make sure `vm_ip` is passed and use the dynamic fields above.

## Deploy n8n Queue Mode

Create vars:

```bash
cp vars/apps/n8n_queue.yml.example vars/apps/n8n_queue.yml
```

Minimum vars:

```yaml
app_name: "n8n_queue"
domain: "n8n.example.com"
timezone: "Asia/Singapore"
app_admin_username: "owner@example.com"
app_admin_password: "strong-n8n-owner-password"

n8n_postgres_password: "strong-postgres-password"
n8n_redis_password: "strong-redis-password"
n8n_encryption_key: "long-random-encryption-key"
```

Run:

```bash
ansible-playbook playbooks/deploy.yml -e @vars/apps/n8n_queue.yml
```

If the controller cannot install `passlib[bcrypt]`, pass `n8n_password_hash` instead of `app_admin_password`.

## Semaphore Extra Vars For n8n

```yaml
app_name: "{{ app_name }}"
domain: "{{ domain }}"
timezone: "{{ timezone }}"
app_admin_username: "{{ app_admin_username }}"
app_admin_password: "{{ app_admin_password }}"
n8n_postgres_password: "{{ n8n_postgres_password }}"
n8n_redis_password: "{{ n8n_redis_password }}"
n8n_encryption_key: "{{ n8n_encryption_key }}"
```

If `domain` is `n8n.example.com`, the role uses `https://n8n.example.com`. If HTTP is required, pass `http://n8n.example.com`.

## Local Helper

PowerShell helper for generating local inventory and vars:

```powershell
.\scripts\prepare-deploy-inputs.ps1 `
  -AppName "n8n_queue" `
  -VmIp "1.2.3.4" `
  -VmUser "root" `
  -SshPassword "ssh-password" `
  -DomainName "n8n.example.com" `
  -Timezone "Asia/Singapore" `
  -AdminUsername "owner@example.com" `
  -AdminPassword "n8n-owner-password" `
  -PostgresPassword "postgres-password" `
  -RedisPassword "redis-password" `
  -EncryptionKey "long-random-encryption-key"
```

Then run:

```powershell
ansible-playbook playbooks/deploy.yml -e "@vars/n8n.yml"
```

## Adding Another App

1. Create a new role under `roles/apps/<app_name>`.
2. Put app defaults in `roles/apps/<app_name>/defaults/main.yml`.
3. Put deployment tasks in `roles/apps/<app_name>/tasks/main.yml`.
4. Put compose/env templates in `roles/apps/<app_name>/templates`.
5. Add the app to `supported_apps` in `playbooks/deploy.yml`.
6. Add an example vars file under `vars/apps/<app_name>.yml.example`.

The new app automatically reuses `roles/docker_host`.
