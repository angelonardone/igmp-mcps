# InstantGMP — Cowork desktop setup helper (literal-value JSON edition)
#
# Use this on Windows after you have downloaded the InstantGMP files
# from the GitHub repo. The script:
#
#   1. Asks you for your InstantGMP server URL, API user, and API password.
#   2. Probes the server to confirm it's reachable.
#   3. Writes a ready-to-paste MCP config to:
#         %USERPROFILE%\.instantgmp\mcp-config.json
#      with your URL/user/password as LITERAL values (no env-var
#      placeholders, since Cowork desktop's MCP config does not always
#      expand them).
#   4. Opens the file in Notepad so you can copy the JSON into
#      Cowork → Settings → Developer (or whichever section your build
#      exposes for MCP servers).
#
# Profile management for support staff who connect to multiple servers:
#
#   .\setup.ps1 -Save  qa            # prompt, save as profile "qa", activate
#   .\setup.ps1 -Use   qa            # load profile "qa" -> mcp-config.json
#   .\setup.ps1 -List                # show saved profiles (URL + user)
#   .\setup.ps1 -Delete qa           # delete profile "qa"
#
# Profiles live at  %USERPROFILE%\.instantgmp\profiles\<name>.json
# Passwords are DPAPI-encrypted per Windows user — only the same Windows
# account on the same machine can decrypt them.
#
# After every change, paste the new mcp-config.json into Cowork's
# settings (or replace the InstantGMP section) and fully restart Cowork.

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'Save')]
    [string]$Url,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'Save')]
    [string]$ApiUser,

    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'Save')]
    [string]$ApiPassword,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$NonInteractive,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$NoOpen,

    [Parameter(ParameterSetName = 'Save', Mandatory)]
    [string]$Save,

    [Parameter(ParameterSetName = 'Use',  Mandatory)]
    [string]$Use,

    [Parameter(ParameterSetName = 'List', Mandatory)]
    [switch]$List,

    [Parameter(ParameterSetName = 'Delete', Mandatory)]
    [string]$Delete
)

$ErrorActionPreference = 'Stop'

# -- paths -----------------------------------------------------------

$BaseDir       = Join-Path $env:USERPROFILE '.instantgmp'
$ProfileDir    = Join-Path $BaseDir 'profiles'
$ActiveConfig  = Join-Path $BaseDir 'mcp-config.json'
$ActiveProfile = Join-Path $BaseDir 'active-profile.txt'

function Ensure-Dirs {
    foreach ($d in @($BaseDir, $ProfileDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function Get-ProfilePath {
    param([Parameter(Mandatory)] [string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Profile name '$Name' contains invalid characters. Use letters, digits, '.', '_', or '-' only."
    }
    return Join-Path $ProfileDir "$Name.json"
}

# -- output helpers --------------------------------------------------

function Write-Header {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  InstantGMP Cowork desktop — setup helper" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
}

# -- input helpers ---------------------------------------------------

function Read-RequiredString {
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [string]$Default = '',
        [scriptblock]$Validator = $null
    )
    while ($true) {
        $suffix = if ($Default) { " [$Default]" } else { '' }
        $value = Read-Host "$Prompt$suffix"
        if (-not $value -and $Default) { $value = $Default }
        if (-not $value) {
            Write-Host "  Value cannot be empty. Try again." -ForegroundColor Yellow
            continue
        }
        if ($Validator) {
            $err = & $Validator $value
            if ($err) {
                Write-Host "  $err" -ForegroundColor Yellow
                continue
            }
        }
        return $value
    }
}

function Read-RequiredSecret {
    param([Parameter(Mandatory)] [string]$Prompt)
    while ($true) {
        $secure = Read-Host -AsSecureString $Prompt
        if ($secure.Length -eq 0) {
            Write-Host "  Password cannot be empty. Try again." -ForegroundColor Yellow
            continue
        }
        return $secure
    }
}

function ConvertTo-PlainPassword {
    param([Parameter(Mandatory)] [System.Security.SecureString]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function ConvertTo-SecurePassword {
    param([Parameter(Mandatory)] [string]$Plain)
    return ConvertTo-SecureString -String $Plain -AsPlainText -Force
}

# -- validation ------------------------------------------------------

function Test-IgmpUrl {
    param([string]$CandidateUrl)
    try {
        $u = [System.Uri]$CandidateUrl
        if (-not ($u.Scheme -eq 'http' -or $u.Scheme -eq 'https')) {
            return "URL must start with http:// or https://"
        }
        if (-not $u.Host) { return "URL is missing a host." }
    } catch {
        return "Not a valid URL: $($_.Exception.Message)"
    }
    return $null
}

function Test-IgmpConnectivity {
    param(
        [string]$BaseUrl,
        [string]$User,
        [string]$Password
    )
    $probeUrl = ($BaseUrl.TrimEnd('/')) + '/rest/mcpservers/setup/mcpsetupserver'
    Write-Host ""
    Write-Host "Probing $probeUrl ..." -ForegroundColor Gray
    try {
        $headers = @{
            'X-Api-User'     = $User
            'X-Api-Password' = $Password
        }
        $resp = Invoke-WebRequest -Uri $probeUrl -Method Head -Headers $headers `
                                  -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Write-Host "  Server responded: HTTP $($resp.StatusCode)." -ForegroundColor Green
        return $true
    } catch {
        $status = $null
        try { $status = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($status) {
            Write-Host "  Server responded HTTP $status. URL is reachable." -ForegroundColor Green
            if ($status -eq 401 -or $status -eq 403) {
                Write-Host "  (Credentials look wrong - InstantGMP rejected them.)" -ForegroundColor Yellow
            }
            return $true
        }
        Write-Host "  Could not reach server: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# -- MCP config builder ---------------------------------------------

function Build-McpConfig {
    param(
        [Parameter(Mandatory)] [string]$BaseUrl,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$Password
    )
    $clean = $BaseUrl.TrimEnd('/')
    $servers = [ordered]@{}
    $servers['instantgmp-inventory'] = [ordered]@{
        type    = 'http'
        url     = "$clean/rest/mcpservers/inventory/mcpinventoryserver"
        headers = [ordered]@{ 'X-Api-User' = $User; 'X-Api-Password' = $Password }
    }
    $servers['instantgmp-setup'] = [ordered]@{
        type    = 'http'
        url     = "$clean/rest/mcpservers/setup/mcpsetupserver"
        headers = [ordered]@{ 'X-Api-User' = $User; 'X-Api-Password' = $Password }
    }
    $servers['instantgmp-logs'] = [ordered]@{
        type    = 'http'
        url     = "$clean/rest/mcpservers/logs/mcplogsserver"
        headers = [ordered]@{ 'X-Api-User' = $User; 'X-Api-Password' = $Password }
    }
    $servers['instantgmp-ebr'] = [ordered]@{
        type    = 'http'
        url     = "$clean/rest/mcpservers/ebr/mcpebrserver"
        headers = [ordered]@{ 'X-Api-User' = $User; 'X-Api-Password' = $Password }
    }
    $servers['instantgmp-qms'] = [ordered]@{
        type    = 'http'
        url     = "$clean/rest/mcpservers/qms/mcpqmsserver"
        headers = [ordered]@{ 'X-Api-User' = $User; 'X-Api-Password' = $Password }
    }
    $servers['instantgmp-projects'] = [ordered]@{
        type    = 'http'
        url     = "$clean/rest/mcpservers/projects/mcpprojectsserver"
        headers = [ordered]@{ 'X-Api-User' = $User; 'X-Api-Password' = $Password }
    }
    $servers['instantgmp-docs'] = [ordered]@{
        type    = 'http'
        url     = "$clean/rest/mcpservers/docs/mcpdocsserver"
        headers = [ordered]@{ 'X-Api-User' = $User; 'X-Api-Password' = $Password }
    }
    return [ordered]@{ mcpServers = $servers }
}

function Write-McpConfig {
    param(
        [Parameter(Mandatory)] [string]$BaseUrl,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$Password,
        [string]$ProfileName = $null
    )
    Ensure-Dirs
    $cfg = Build-McpConfig -BaseUrl $BaseUrl -User $User -Password $Password
    $json = $cfg | ConvertTo-Json -Depth 6
    Set-Content -Path $ActiveConfig -Value $json -Encoding UTF8
    if ($ProfileName) {
        Set-Content -Path $ActiveProfile -Value $ProfileName -Encoding UTF8
    } else {
        if (Test-Path $ActiveProfile) { Remove-Item $ActiveProfile -Force }
    }

    Write-Host ""
    Write-Host "Wrote MCP config to:" -ForegroundColor Green
    Write-Host "  $ActiveConfig"
    if ($ProfileName) {
        Write-Host "Active profile: $ProfileName" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "Next steps in Cowork desktop:" -ForegroundColor Cyan
    Write-Host "  1. Open Cowork -> Settings -> Developer (or wherever your build"
    Write-Host "     exposes MCP server configuration)."
    Write-Host "  2. Open the file above and copy its contents."
    Write-Host "  3. Paste it into Cowork's MCP server settings, replacing any"
    Write-Host "     previous InstantGMP section."
    Write-Host "  4. Fully quit Cowork (close the window AND the system tray icon)"
    Write-Host "     and reopen it so the MCP servers reload."
    Write-Host ""
}

# -- profile I/O -----------------------------------------------------

function Save-Profile {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$ProfileUrl,
        [Parameter(Mandatory)] [string]$ProfileUser,
        [Parameter(Mandatory)] [System.Security.SecureString]$ProfileSecure
    )
    Ensure-Dirs
    $encrypted = ConvertFrom-SecureString -SecureString $ProfileSecure
    $obj = [pscustomobject]@{
        name              = $Name
        url               = $ProfileUrl.TrimEnd('/')
        user              = $ProfileUser
        passwordEncrypted = $encrypted
        savedAt           = (Get-Date).ToString('o')
    }
    $path = Get-ProfilePath -Name $Name
    $obj | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
    Write-Host "Saved profile '$Name' -> $path" -ForegroundColor Green
}

function Load-Profile {
    param([Parameter(Mandatory)] [string]$Name)
    $path = Get-ProfilePath -Name $Name
    if (-not (Test-Path $path)) { throw "Profile '$Name' not found at $path" }
    $obj = Get-Content -Raw -Path $path | ConvertFrom-Json
    if (-not $obj.url -or -not $obj.user -or -not $obj.passwordEncrypted) {
        throw "Profile '$Name' is malformed (missing url/user/passwordEncrypted)."
    }
    try {
        $secure = ConvertTo-SecureString -String $obj.passwordEncrypted
    } catch {
        throw "Could not decrypt password for profile '$Name'. DPAPI keys are tied to the Windows user + machine. If you copied this profile from another machine you'll need to re-save it. Inner error: $($_.Exception.Message)"
    }
    return [pscustomobject]@{
        Name           = $obj.name
        Url            = $obj.url
        User           = $obj.user
        PasswordSecure = $secure
    }
}

function List-Profiles {
    Ensure-Dirs
    $files = Get-ChildItem -Path $ProfileDir -Filter '*.json' -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Host "No saved profiles. Save one with:  setup.ps1 -Save <name>" -ForegroundColor Yellow
        return
    }
    $active = if (Test-Path $ActiveProfile) { (Get-Content -Raw $ActiveProfile).Trim() } else { '' }
    Write-Host ""
    Write-Host "Saved InstantGMP profiles for user $env:USERNAME:" -ForegroundColor Cyan
    Write-Host ""
    "{0,-2} {1,-20} {2,-40} {3}" -f '', 'NAME', 'URL', 'API USER' | Write-Host
    "{0,-2} {1,-20} {2,-40} {3}" -f '', '----', '---', '--------' | Write-Host
    foreach ($f in $files) {
        try {
            $obj = Get-Content -Raw -Path $f.FullName | ConvertFrom-Json
            $marker = if ($obj.name -eq $active) { '*' } else { ' ' }
            "{0,-2} {1,-20} {2,-40} {3}" -f $marker, $obj.name, $obj.url, $obj.user | Write-Host
        } catch {
            Write-Host ("?? {0,-20} (could not read: {1})" -f $f.BaseName, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "  *  = profile currently written to mcp-config.json"
}

function Delete-Profile {
    param([Parameter(Mandatory)] [string]$Name)
    $path = Get-ProfilePath -Name $Name
    if (-not (Test-Path $path)) {
        Write-Host "Profile '$Name' does not exist (nothing to delete)." -ForegroundColor Yellow
        return
    }
    Remove-Item -Path $path -Force
    Write-Host "Deleted profile '$Name'." -ForegroundColor Green
    $active = if (Test-Path $ActiveProfile) { (Get-Content -Raw $ActiveProfile).Trim() } else { '' }
    if ($active -eq $Name) {
        Write-Host "Note: '$Name' was the active profile. Re-run setup to choose a new one." -ForegroundColor Yellow
    }
}

# -- interactive flow -----------------------------------------------

function Run-Interactive {
    param([string]$ProfileNameToSave = $null)

    if (-not $Url) {
        $Url = Read-RequiredString -Prompt "InstantGMP base URL (e.g. https://yourcompany.igmpapp.com)" `
                                   -Validator { param($v) Test-IgmpUrl $v }
    }
    if (-not $ApiUser) {
        $ApiUser = Read-RequiredString -Prompt "InstantGMP API user (X-Api-User)"
    }
    if (-not $ApiPassword) {
        $secure = Read-RequiredSecret -Prompt "InstantGMP API password (X-Api-Password)"
    } else {
        $secure = ConvertTo-SecurePassword -Plain $ApiPassword
    }

    $urlError = Test-IgmpUrl $Url
    if ($urlError) { Write-Host $urlError -ForegroundColor Red; exit 1 }

    $plain = ConvertTo-PlainPassword -Secure $secure
    $Url   = $Url.TrimEnd('/')

    $connOk = Test-IgmpConnectivity -BaseUrl $Url -User $ApiUser -Password $plain
    if (-not $connOk -and -not $NonInteractive) {
        $proceed = Read-Host "Save anyway? (y/N)"
        if ($proceed -ne 'y' -and $proceed -ne 'Y') {
            Write-Host "Aborted. No files were written." -ForegroundColor Yellow
            exit 1
        }
    }

    if ($ProfileNameToSave) {
        Save-Profile -Name $ProfileNameToSave -ProfileUrl $Url -ProfileUser $ApiUser -ProfileSecure $secure
        Write-McpConfig -BaseUrl $Url -User $ApiUser -Password $plain -ProfileName $ProfileNameToSave
    } else {
        Write-McpConfig -BaseUrl $Url -User $ApiUser -Password $plain
        if (-not $NonInteractive) {
            $reply = Read-Host "Also save these as a named profile for quick switching later? (name, or blank to skip)"
            if ($reply) {
                Save-Profile -Name $reply -ProfileUrl $Url -ProfileUser $ApiUser -ProfileSecure $secure
                Set-Content -Path $ActiveProfile -Value $reply -Encoding UTF8
                Write-Host "Active profile is now '$reply'." -ForegroundColor Green
            }
        }
    }

    if (-not $NoOpen -and -not $NonInteractive) {
        try { Start-Process notepad.exe $ActiveConfig } catch {}
    }
}

# -- dispatch --------------------------------------------------------

Write-Header

switch ($PSCmdlet.ParameterSetName) {
    'List'   { List-Profiles; return }
    'Delete' { Delete-Profile -Name $Delete; return }
    'Use'    {
        $p = Load-Profile -Name $Use
        $plain = ConvertTo-PlainPassword -Secure $p.PasswordSecure
        Write-Host "Loading profile '$($p.Name)' ..." -ForegroundColor Cyan
        $ok = Test-IgmpConnectivity -BaseUrl $p.Url -User $p.User -Password $plain
        if (-not $ok) { Write-Host "Server is not reachable, but applying profile anyway." -ForegroundColor Yellow }
        Write-McpConfig -BaseUrl $p.Url -User $p.User -Password $plain -ProfileName $p.Name
        if (-not $NoOpen) { try { Start-Process notepad.exe $ActiveConfig } catch {} }
        return
    }
    'Save'   { Run-Interactive -ProfileNameToSave $Save; return }
    default  { Run-Interactive }
}
