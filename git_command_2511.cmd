@echo off
setlocal EnableExtensions

set "SELF=%~f0"
set "WRAPPER=%TEMP%\git_command_wrapper_%RANDOM%%RANDOM%.ps1"

REM --- PowerShell ローダー部分 ---
> "%WRAPPER%" (
    echo param([string]^$path^)
    echo ^$content = Get-Content -Raw -Path ^$path -Encoding UTF8
    echo ^$marker = [regex]::Match(^$content, "`r?`n:__PS_PAYLOAD__`r?`n"^)
    echo if (-not ^$marker.Success^) { Write-Error "PowerShell payload marker not found."; exit 1 }
    echo ^$payload = ^$content.Substring(^$marker.Index + ^$marker.Length^)
    echo Invoke-Expression ^$payload
    echo exit ^$LASTEXITCODE
)

powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%WRAPPER%" "%SELF%"
set "ERR=%ERRORLEVEL%"
del "%WRAPPER%" >nul 2>&1
exit /b %ERR%

:__PS_PAYLOAD__
# -----------------------------------------------------------------------------
# Git Helper Script (PowerShell Perfect Edition)
# -----------------------------------------------------------------------------

# Gitの存在確認
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git command was not found. Please install Git."
    exit 1
}

$LogFile = Join-Path -Path $HOME -ChildPath "git_helper.log"

# --- ログ・実行関数 ---

function Write-HelperLog {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "$timestamp - $Message"
}

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [string]$Description
    )

    if (-not $Description) {
        $Description = "git " + ($Arguments -join " ")
    }

    Write-Host "Running: $Description" -ForegroundColor Cyan
    
    # 安全な呼び出し（Call Operator & を使用）
    & git $Arguments
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "Success" -ForegroundColor Green
        Write-HelperLog "SUCCESS: $Description"
        return $true
    } else {
        Write-Host "Failed (exit code $exitCode)" -ForegroundColor Red
        Write-HelperLog "FAILED: $Description (exit $exitCode)"
        return $false
    }
}

function Get-CurrentBranch {
    $branch = git symbolic-ref --short HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return "HEAD (Detached?)" }
    return $branch
}

# --- 個別ロジック ---

function Invoke-GitCommit {
    Write-Host "Choose commit mode:"
    Write-Host "0) Default: ""Update <Timestamp>"""
    Write-Host "1) Single-line message"
    Write-Host "2) Use default editor"
    $choice = Read-Host "Select mode [0-2] (default: 0)"

    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "0" }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

    switch ($choice) {
        "0" {
            $msg = "Update $timestamp"
            Write-Host "Message: ""$msg""" -ForegroundColor Cyan
            Invoke-GitCommand -Arguments @("commit", "-m", $msg) -Description "git commit -m '$msg'"
        }
        "1" {
            $msg = Read-Host "Enter message"
            if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "Update $timestamp" }
            Invoke-GitCommand -Arguments @("commit", "-m", $msg) -Description "git commit -m '$msg'"
        }
        "2" {
            Invoke-GitCommand -Arguments @("commit") -Description "git commit (editor)"
        }
        Default { Write-Host "Invalid choice." -ForegroundColor Red }
    }
}

function Invoke-StashPullRebase {
    $currentBranch = Get-CurrentBranch
    Write-Host "Target Branch: $currentBranch" -ForegroundColor Yellow
    Write-Host "Safe Sync: Stash -> Pull Rebase -> Pop"

    Invoke-GitCommand -Arguments @("stash") -Description "git stash"
    
    # Pullの結果を変数で受け取る (Invoke-GitCommandは成功時 $true を返すように修正済)
    $success = Invoke-GitCommand -Arguments @("pull", "--rebase", "origin", $currentBranch) -Description "git pull --rebase origin $currentBranch"

    if ($success) {
        Invoke-GitCommand -Arguments @("stash", "pop") -Description "git stash pop"
    } else {
        Write-Host "`n!!! Pull Failed. Stash pop skipped to protect your data. !!!" -ForegroundColor Red -BackgroundColor Black
        Write-Host "Please resolve conflicts manually." -ForegroundColor Yellow
    }
}

# --- メインメニュー ---

while ($true) {
    Write-Host ""
    $cur = Get-CurrentBranch
    Write-Host "=======================================" -ForegroundColor Yellow
    Write-Host "       Git Helper (PowerShell)" -ForegroundColor Yellow
    Write-Host "=======================================" -ForegroundColor Yellow
    Write-Host "Current Branch: $cur" -ForegroundColor Green
    Write-Host ""

    Write-Host "1.  git status"
    Write-Host "2.  git add (specify path)"
    Write-Host "3.  git commit"
    Write-Host "4.  git push"
    Write-Host "5.  git pull (Normal / --rebase)"
    Write-Host "6.  git log"
    Write-Host "7.  git branch"
    Write-Host "8.  git checkout"
    Write-Host "9.  git merge"
    Write-Host "10. git stash"
    Write-Host "11. git remote -v"
    Write-Host "12. git diff"
    Write-Host "13. [Safe] git stash -> pull --rebase -> pop"
    Write-Host "14. Enforce LF (Renormalize)"
    Write-Host "h.  Help"
    Write-Host "0.  Exit"
    Write-Host "---------------------------------------"

    $choice = Read-Host "Choose option"
    Write-Host ""

    switch ($choice) {
        "1"  { Invoke-GitCommand -Arguments @("status") }
        "2"  { 
            $p = Read-Host "Path (default: .)"
            if ([string]::IsNullOrWhiteSpace($p)) { $p = "." }
            Invoke-GitCommand -Arguments @("add", $p) 
        }
        "3"  { Invoke-GitCommit }
        "4"  { Invoke-GitCommand -Arguments @("push", "origin", $cur) }
        "5"  {
             Write-Host "0) Normal Pull  1) Rebase Pull"
             $m = Read-Host "Mode (def: 0)"
             if ($m -eq "1") { Invoke-GitCommand -Arguments @("pull", "--rebase", "origin", $cur) }
             else { Invoke-GitCommand -Arguments @("pull", "origin", $cur) }
        }
        "6"  { Invoke-GitCommand -Arguments @("log", "--oneline", "--graph", "--decorate", "-n", "15") }
        "7"  { Invoke-GitCommand -Arguments @("branch", "-a") }
        "8"  { 
            $b = Read-Host "Branch name"
            if ($b) { Invoke-GitCommand -Arguments @("checkout", $b) }
        }
        "9"  {
            $b = Read-Host "Merge target"
            if ($b) { Invoke-GitCommand -Arguments @("merge", $b) }
        }
        "10" { Invoke-GitCommand -Arguments @("stash") }
        "11" { Invoke-GitCommand -Arguments @("remote", "-v") }
        "12" { Invoke-GitCommand -Arguments @("diff") }
        "13" { Invoke-StashPullRebase }
        "14" { 
            Invoke-GitCommand -Arguments @("config", "core.autocrlf", "false")
            Invoke-GitCommand -Arguments @("add", "--renormalize", ".")
            Write-Host "Files renormalized to LF. Check status and commit." -ForegroundColor Yellow
        }
        "0"  { 
            Write-Host "Exiting..." -ForegroundColor Green
            break 
        }
        Default { 
            if ($choice -notin "h","H") { Write-Host "Invalid choice." -ForegroundColor Red }
        }
    }
}
