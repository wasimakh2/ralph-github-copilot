# Ralph - Windows/PowerShell Installer
# For Git Bash on Windows: use this OR run ./install.sh in Git Bash

param(
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Ralph Windows Installer

Usage:
  .\setup.ps1                   # Install Ralph globally
  .\setup.ps1 -Help            # Show this help

Requirements:
  - PowerShell 5.0+
  - Git Bash installed (for ralph scripts to run)
  - npm (for opencode/claude CLI)

What it does:
  1. Creates ~/.ralph and ~/.local/bin directories
  2. Copies Ralph scripts and templates
  3. Creates wrapper commands in ~/.local/bin
  4. Adds ~/.local/bin to PATH (if not already present)
  5. Tests provider availability

After install:
  1. Close and reopen PowerShell
  2. Run: ralph --monitor
  3. Or: ralph --provider claude

Troubleshooting:
  - If ralph not found: ensure ~/.local/bin is in your PATH
  - Run 'ralph --list-providers' to check available AI providers
"@
    exit 0
}

function Log-Info {
    Write-Host "[INFO] $args" -ForegroundColor Cyan
}

function Log-Success {
    Write-Host "[SUCCESS] $args" -ForegroundColor Green
}

function Log-Warn {
    Write-Host "[WARN] $args" -ForegroundColor Yellow
}

function Log-Error {
    Write-Host "[ERROR] $args" -ForegroundColor Red
}

# Detect script directory
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$RALPH_HOME = "$HOME/.ralph"
$INSTALL_DIR = "$HOME/.local/bin"

Log-Info "Ralph - Windows Installer"
Log-Info "Installing to: $RALPH_HOME"
Log-Info ""

# Create directories
Log-Info "Creating directories..."
New-Item -ItemType Directory -Force -Path $RALPH_HOME | Out-Null
New-Item -ItemType Directory -Force -Path "$RALPH_HOME/templates" | Out-Null
New-Item -ItemType Directory -Force -Path "$RALPH_HOME/lib" | Out-Null
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Log-Success "Directories created"

# Copy templates
Log-Info "Copying templates..."
Copy-Item "$SCRIPT_DIR/templates/*" "$RALPH_HOME/templates/" -Force -Recurse 2>$null
Copy-Item "$SCRIPT_DIR/lib/*" "$RALPH_HOME/lib/" -Force -Recurse 2>$null
Copy-Item "$SCRIPT_DIR/ralph_loop.sh" "$RALPH_HOME/" -Force
Copy-Item "$SCRIPT_DIR/ralph_monitor.sh" "$RALPH_HOME/" -Force
Copy-Item "$SCRIPT_DIR/setup.sh" "$RALPH_HOME/" -Force
Copy-Item "$SCRIPT_DIR/ralph_import.sh" "$RALPH_HOME/" -Force
Log-Success "Templates copied"

# Create config file if missing
$CONFIG_FILE = "$RALPH_HOME/config"
if (!(Test-Path $CONFIG_FILE)) {
    Log-Info "Creating default config..."
    @"
# Ralph Global Configuration
# Default AI provider: claude, copilot, or opencode
AI_PROVIDER=`${AI_PROVIDER:-opencode}

# Max API calls per hour
MAX_CALLS_PER_HOUR=`${MAX_CALLS_PER_HOUR:-100}

# Timeout in minutes
CLAUDE_TIMEOUT_MINUTES=`${CLAUDE_TIMEOUT_MINUTES:-15}

# Claude output format: json or text
CLAUDE_OUTPUT_FORMAT=`${CLAUDE_OUTPUT_FORMAT:-json}

# Allowed tools for Claude
CLAUDE_ALLOWED_TOOLS=`${CLAUDE_ALLOWED_TOOLS:-Write,Bash(git *),Read}
"@ | Out-File -Encoding UTF8 -FilePath $CONFIG_FILE
    Log-Success "Config created at $CONFIG_FILE"
}

# Create ralph command wrapper (batch file for direct execution)
$RALPH_BAT = "$INSTALL_DIR/ralph.bat"
@"
@echo off
REM Ralph - Windows batch wrapper
REM Requires Git Bash to run the bash scripts
bash "%USERPROFILE%/.ralph/ralph_loop.sh" %*
"@ | Out-File -Encoding ASCII -FilePath $RALPH_BAT -Force
Log-Success "Created ralph.bat"

# Add to PATH
$PATH_KEY = "HKCU:\Environment"
$PATH_VALUE = (Get-ItemProperty -Path $PATH_KEY -Name "Path").Path
if ($PATH_VALUE -notlike "*$INSTALL_DIR*") {
    Log-Info "Adding ~/.local/bin to PATH..."
    $NEW_PATH = "$INSTALL_DIR;$PATH_VALUE"
    Set-ItemProperty -Path $PATH_KEY -Name "Path" -Value $NEW_PATH
    Log-Success "PATH updated (restart terminal to take effect)"
} else {
    Log-Info "~/.local/bin already in PATH"
}

# Check providers
Log-Info ""
Log-Info "Checking AI providers..."
$PROVIDERS_FOUND = 0

if (Get-Command opencode -ErrorAction SilentlyContinue) {
    Log-Success "opencode CLI found"
    $PROVIDERS_FOUND++
} else {
    Log-Warn "opencode not found - install with: npm install -g opencode-ai"
}

if (Get-Command npx -ErrorAction SilentlyContinue) {
    Log-Success "npm/npx found - Claude Code available"
    $PROVIDERS_FOUND++
} else {
    Log-Warn "npm not found - Claude Code unavailable"
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $GH_COPILOT = gh extension list 2>$null | Select-String "copilot"
    if ($GH_COPILOT) {
        Log-Success "GitHub Copilot CLI found"
        $PROVIDERS_FOUND++
    } else {
        Log-Warn "GitHub CLI found but Copilot extension not installed"
    }
} else {
    Log-Warn "GitHub CLI not found - Copilot provider unavailable"
}

if ($PROVIDERS_FOUND -eq 0) {
    Log-Warn "No AI providers found. Install at least one:"
    Write-Host "  opencode:    npm install -g opencode-ai"
    Write-Host "  Claude Code: npm install -g @anthropic-ai/claude-code"
    Write-Host "  Copilot:     gh extension install github/gh-copilot"
}

Log-Info ""
Log-Success "Ralph installed successfully!"
Log-Info ""
Write-Host "Next steps:"
Write-Host "  1. Restart PowerShell to update PATH"
Write-Host "  2. Run: ralph --monitor"
Write-Host "  3. Or: ralph --provider claude"
Write-Host ""
Write-Host "Note: Ralph scripts require Git Bash to run."
Write-Host "Make sure Git Bash is installed: https://gitforwindows.org/"
