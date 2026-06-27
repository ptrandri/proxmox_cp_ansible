param(
    [string]$AppName = "n8n_queue",

    [Parameter(Mandatory = $true)]
    [string]$VmIp,

    [Parameter(Mandatory = $true)]
    [string]$VmUser,

    [string]$SshPassword,
    [string]$SudoPassword,
    [string]$SshKeyFile,

    [Parameter(Mandatory = $true)]
    [Alias("Domain")]
    [string]$DomainName,

    [string]$Timezone = "Asia/Singapore",

    [Parameter(Mandatory = $true)]
    [Alias("N8nUsername")]
    [string]$AdminUsername,

    [Parameter(Mandatory = $true)]
    [Alias("N8nPassword")]
    [string]$AdminPassword,

    [string]$PostgresUser = "n8n",

    [Parameter(Mandatory = $true)]
    [string]$PostgresPassword,

    [Parameter(Mandatory = $true)]
    [string]$RedisPassword,

    [Parameter(Mandatory = $true)]
    [string]$EncryptionKey
)

function ConvertTo-YamlDoubleQuoted {
    param([string]$Value)

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

if ([string]::IsNullOrWhiteSpace($SshPassword) -and [string]::IsNullOrWhiteSpace($SshKeyFile)) {
    throw "Provide either -SshPassword or -SshKeyFile."
}

if ([string]::IsNullOrWhiteSpace($SudoPassword)) {
    $SudoPassword = $SshPassword
}

$inventoryDir = Join-Path $PSScriptRoot "..\inventories\production"
$varsDir = Join-Path $PSScriptRoot "..\vars"

New-Item -ItemType Directory -Path $inventoryDir -Force | Out-Null
New-Item -ItemType Directory -Path $varsDir -Force | Out-Null

if (-not [string]::IsNullOrWhiteSpace($SshKeyFile)) {
    $authLines = "          ansible_ssh_private_key_file: $(ConvertTo-YamlDoubleQuoted $SshKeyFile)"
} else {
    $authLines = @"
          ansible_password: $(ConvertTo-YamlDoubleQuoted $SshPassword)
          ansible_become_password: $(ConvertTo-YamlDoubleQuoted $SudoPassword)
"@
}

$inventory = @"
---
all:
  children:
    app_servers:
      hosts:
        app-prod:
          ansible_host: $(ConvertTo-YamlDoubleQuoted $VmIp)
          ansible_user: $(ConvertTo-YamlDoubleQuoted $VmUser)
$authLines
"@

$vars = @"
---
app_name: $(ConvertTo-YamlDoubleQuoted $AppName)
domain: $(ConvertTo-YamlDoubleQuoted $DomainName)
timezone: $(ConvertTo-YamlDoubleQuoted $Timezone)
app_admin_username: $(ConvertTo-YamlDoubleQuoted $AdminUsername)
app_admin_password: $(ConvertTo-YamlDoubleQuoted $AdminPassword)
n8n_postgres_user: $(ConvertTo-YamlDoubleQuoted $PostgresUser)
n8n_postgres_password: $(ConvertTo-YamlDoubleQuoted $PostgresPassword)
n8n_redis_password: $(ConvertTo-YamlDoubleQuoted $RedisPassword)
n8n_encryption_key: $(ConvertTo-YamlDoubleQuoted $EncryptionKey)
"@

Set-Content -Path (Join-Path $inventoryDir "hosts.yml") -Value $inventory -Encoding UTF8
Set-Content -Path (Join-Path $varsDir "n8n.yml") -Value $vars -Encoding UTF8

Write-Host "Generated inventories/production/hosts.yml and vars/n8n.yml"

