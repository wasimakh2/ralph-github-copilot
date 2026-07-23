#!/bin/bash

# Ralph - Autonomous AI Development Loop - Global Installation Script
# Supports: opencode (default), Claude Code, GitHub Copilot
set -e

# Configuration
INSTALL_DIR="$HOME/.local/bin"
RALPH_HOME="$HOME/.ralph"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    local message=$2
    local color=""
    
    case $level in
        "INFO")  color=$BLUE ;;
        "WARN")  color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "SUCCESS") color=$GREEN ;;
    esac
    
    echo -e "${color}[$(date '+%H:%M:%S')] [$level] $message${NC}"
}

# Check dependencies
check_dependencies() {
    log "INFO" "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v node &> /dev/null && ! command -v npx &> /dev/null; then
        missing_deps+=("Node.js/npm")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies:"
        echo "  Ubuntu/Debian: sudo apt-get install nodejs npm jq git"
        echo "  macOS: brew install node jq git"
        echo "  CentOS/RHEL: sudo yum install nodejs npm jq git"
        exit 1
    fi
    
    # Check for AI providers
    log "INFO" "Checking for AI providers..."
    local providers_found=0
    
    # Claude Code CLI
    if command -v claude &> /dev/null; then
        log "SUCCESS" "Claude Code CLI found"
        providers_found=$((providers_found + 1))
    else
        log "INFO" "Claude Code CLI not found - will be available via npx"
    fi
    
    # GitHub Copilot CLI
    if command -v gh &> /dev/null; then
        if gh extension list 2>/dev/null | grep -q "copilot"; then
            log "SUCCESS" "GitHub Copilot CLI extension found"
            providers_found=$((providers_found + 1))
        else
            log "INFO" "GitHub CLI found but Copilot extension not installed"
            log "INFO" "  To add Copilot: gh extension install github/gh-copilot"
        fi
    else
        log "INFO" "GitHub CLI not found - Copilot provider unavailable"
    fi

    # opencode CLI (default provider)
    if command -v opencode &> /dev/null; then
        log "SUCCESS" "opencode CLI found"
        providers_found=$((providers_found + 1))
    else
        log "INFO" "opencode CLI not found - install with: npm install -g opencode-ai"
    fi

    if [[ $providers_found -eq 0 ]]; then
        log "WARN" "No AI providers found. Install at least one:"
        echo "  opencode: npm install -g opencode-ai"
        echo "  Claude Code: npm install -g @anthropic-ai/claude-code"
        echo "  GitHub Copilot: gh extension install github/gh-copilot"
    fi
    
    # Check tmux (optional)
    if ! command -v tmux &> /dev/null; then
        log "WARN" "tmux not found. Install for integrated monitoring: apt-get install tmux / brew install tmux"
    fi
    
    log "SUCCESS" "Dependencies check completed"
}

# Create installation directory
create_install_dirs() {
    log "INFO" "Creating installation directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$RALPH_HOME"
    mkdir -p "$RALPH_HOME/templates"
    mkdir -p "$RALPH_HOME/lib"

    log "SUCCESS" "Directories created: $INSTALL_DIR, $RALPH_HOME"
}

# Create default config file
create_default_config() {
    local config_file="$RALPH_HOME/config"
    
    # Only create if it doesn't exist (preserve user customizations)
    if [[ ! -f "$config_file" ]]; then
        log "INFO" "Creating default configuration file..."
        cat > "$config_file" << 'EOF'
# Ralph Global Configuration
# This file is sourced by ralph_loop.sh on startup
# You can override these settings per-project by creating .ralph.conf in your project directory

# =============================================================================
# AI PROVIDER SETTINGS
# =============================================================================

# Default AI provider: claude, copilot, or opencode
# Uncomment one of the lines below to override the default
#AI_PROVIDER="claude"
#AI_PROVIDER="copilot"

# Default provider (opencode is the default if not set)
AI_PROVIDER="${AI_PROVIDER:-opencode}"

# =============================================================================
# OPENCODE SETTINGS
# =============================================================================

# provider/model, e.g. anthropic/claude-sonnet-4; empty = opencode's own default
OPENCODE_MODEL="${OPENCODE_MODEL:-}"

# =============================================================================
# GITHUB COPILOT SETTINGS
# =============================================================================

# Copilot mode: suggest or explain
COPILOT_MODE="${COPILOT_MODE:-suggest}"

# Target type for suggest mode: shell, git, or gh
COPILOT_TARGET_TYPE="${COPILOT_TARGET_TYPE:-shell}"

# =============================================================================
# CLAUDE CODE SETTINGS
# =============================================================================

# Output format: json or text
CLAUDE_OUTPUT_FORMAT="${CLAUDE_OUTPUT_FORMAT:-json}"

# Allowed tools (comma-separated)
CLAUDE_ALLOWED_TOOLS="${CLAUDE_ALLOWED_TOOLS:-Write,Bash(git *),Read}"

# Enable session continuity
CLAUDE_USE_CONTINUE="${CLAUDE_USE_CONTINUE:-true}"

# =============================================================================
# EXECUTION SETTINGS
# =============================================================================

# Maximum API calls per hour
MAX_CALLS_PER_HOUR="${MAX_CALLS_PER_HOUR:-100}"

# Timeout in minutes for AI execution
CLAUDE_TIMEOUT_MINUTES="${CLAUDE_TIMEOUT_MINUTES:-15}"

# Show verbose progress during execution
VERBOSE_PROGRESS="${VERBOSE_PROGRESS:-false}"
EOF
        log "SUCCESS" "Default config created at $config_file"
    else
        log "INFO" "Config file already exists, preserving user settings"
    fi
}

# Install Ralph scripts
install_scripts() {
    log "INFO" "Installing Ralph scripts..."
    
    # Copy templates to Ralph home
    cp -r "$SCRIPT_DIR/templates/"* "$RALPH_HOME/templates/"

    # Copy lib scripts (response_analyzer.sh, circuit_breaker.sh)
    cp -r "$SCRIPT_DIR/lib/"* "$RALPH_HOME/lib/"
    
    # Create the main ralph command
    cat > "$INSTALL_DIR/ralph" << 'EOF'
#!/bin/bash
# Ralph for Claude Code - Main Command

RALPH_HOME="$HOME/.ralph"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the actual ralph loop script with global paths
exec "$RALPH_HOME/ralph_loop.sh" "$@"
EOF

    # Create ralph-monitor command
    cat > "$INSTALL_DIR/ralph-monitor" << 'EOF'
#!/bin/bash
# Ralph Monitor - Global Command

RALPH_HOME="$HOME/.ralph"

exec "$RALPH_HOME/ralph_monitor.sh" "$@"
EOF

    # Create ralph-setup command
    cat > "$INSTALL_DIR/ralph-setup" << 'EOF'
#!/bin/bash
# Ralph Project Setup - Global Command

RALPH_HOME="$HOME/.ralph"

exec "$RALPH_HOME/setup.sh" "$@"
EOF

    # Create ralph-import command
    cat > "$INSTALL_DIR/ralph-import" << 'EOF'
#!/bin/bash
# Ralph PRD Import - Global Command

RALPH_HOME="$HOME/.ralph"

exec "$RALPH_HOME/ralph_import.sh" "$@"
EOF

    # Copy actual script files to Ralph home with modifications for global operation
    cp "$SCRIPT_DIR/ralph_monitor.sh" "$RALPH_HOME/"
    
    # Copy PRD import script to Ralph home
    cp "$SCRIPT_DIR/ralph_import.sh" "$RALPH_HOME/"
    
    # Make all commands executable
    chmod +x "$INSTALL_DIR/ralph"
    chmod +x "$INSTALL_DIR/ralph-monitor" 
    chmod +x "$INSTALL_DIR/ralph-setup"
    chmod +x "$INSTALL_DIR/ralph-import"
    chmod +x "$RALPH_HOME/ralph_monitor.sh"
    chmod +x "$RALPH_HOME/ralph_import.sh"
    chmod +x "$RALPH_HOME/lib/"*.sh

    log "SUCCESS" "Ralph scripts installed to $INSTALL_DIR"
}

# Install global ralph_loop.sh
install_ralph_loop() {
    log "INFO" "Installing global ralph_loop.sh..."
    
    # Create modified ralph_loop.sh for global operation
    sed \
        -e "s|RALPH_HOME=\"\$HOME/.ralph\"|RALPH_HOME=\"\$HOME/.ralph\"|g" \
        -e "s|\$script_dir/ralph_monitor.sh|\$RALPH_HOME/ralph_monitor.sh|g" \
        -e "s|\$script_dir/ralph_loop.sh|\$RALPH_HOME/ralph_loop.sh|g" \
        "$SCRIPT_DIR/ralph_loop.sh" > "$RALPH_HOME/ralph_loop.sh"
    
    chmod +x "$RALPH_HOME/ralph_loop.sh"
    
    log "SUCCESS" "Global ralph_loop.sh installed"
}

# Install global setup.sh
install_setup() {
    log "INFO" "Installing global setup script..."
    
    # Create modified setup.sh for global operation
    cat > "$RALPH_HOME/setup.sh" << 'EOF'
#!/bin/bash

# Ralph Project Setup Script - Global Version
set -e

PROJECT_NAME=${1:-"my-project"}
RALPH_HOME="$HOME/.ralph"

echo "🚀 Setting up Ralph project: $PROJECT_NAME"

# Create project directory in current location
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# Create structure
mkdir -p {specs/stdlib,src,examples,logs,docs/generated}

# Copy templates from Ralph home
cp "$RALPH_HOME/templates/PROMPT.md" .
cp "$RALPH_HOME/templates/fix_plan.md" @fix_plan.md
cp "$RALPH_HOME/templates/AGENT.md" @AGENT.md
cp -r "$RALPH_HOME/templates/specs/"* specs/ 2>/dev/null || true

# Initialize git
git init
echo "# $PROJECT_NAME" > README.md
git add .
git commit -m "Initial Ralph project setup"

echo "✅ Project $PROJECT_NAME created!"
echo "Next steps:"
echo "  1. Edit PROMPT.md with your project requirements"
echo "  2. Update specs/ with your project specifications"  
echo "  3. Run: ralph --monitor"
echo "  4. Monitor: ralph-monitor (if running manually)"
EOF

    chmod +x "$RALPH_HOME/setup.sh"
    
    log "SUCCESS" "Global setup script installed"
}

# Check PATH
check_path() {
    log "INFO" "Checking PATH configuration..."
    
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        log "WARN" "$INSTALL_DIR is not in your PATH"
        echo ""
        echo "Add this to your ~/.bashrc, ~/.zshrc, or ~/.profile:"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        echo "Then run: source ~/.bashrc (or restart your terminal)"
        echo ""
    else
        log "SUCCESS" "$INSTALL_DIR is already in PATH"
    fi
}

# Main installation
main() {
    echo "🚀 Installing Ralph - Autonomous AI Development Loop..."
    echo "   Supports: opencode (default), Claude Code, GitHub Copilot"
    echo ""
    
    check_dependencies
    create_install_dirs
    create_default_config
    install_scripts
    install_ralph_loop
    install_setup
    check_path
    
    echo ""
    log "SUCCESS" "🎉 Ralph installed successfully!"
    echo ""
    echo "Global commands available:"
    echo "  ralph --monitor              # Start Ralph with integrated monitoring (opencode by default)"
    echo "  ralph --provider claude      # Use Claude Code instead"
    echo "  ralph --provider copilot     # Use GitHub Copilot instead"
    echo "  ralph --list-providers       # Show available AI providers"
    echo "  ralph --help                 # Show all Ralph options"
    echo "  ralph-setup my-project       # Create new Ralph project"
    echo "  ralph-import prd.md          # Convert PRD to Ralph project"
    echo "  ralph-monitor                # Manual monitoring dashboard"
    echo ""
    echo "Quick start:"
    echo "  1. ralph-setup my-awesome-project"
    echo "  2. cd my-awesome-project"
    echo "  3. # Edit PROMPT.md with your requirements"
    echo "  4. ralph --monitor                    # Use opencode (default)"
    echo "     OR"
    echo "     ralph --monitor --provider claude  # Use Claude Code"
    echo "     ralph --monitor --provider copilot # Use GitHub Copilot"
    echo ""
    
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "⚠️  Don't forget to add $INSTALL_DIR to your PATH (see above)"
    fi
}

# Handle command line arguments
case "${1:-install}" in
    install)
        main
        ;;
    uninstall)
        log "INFO" "Uninstalling Ralph for Claude Code..."
        rm -f "$INSTALL_DIR/ralph" "$INSTALL_DIR/ralph-monitor" "$INSTALL_DIR/ralph-setup" "$INSTALL_DIR/ralph-import"
        rm -rf "$RALPH_HOME"
        log "SUCCESS" "Ralph for Claude Code uninstalled"
        ;;
    --help|-h)
        echo "Ralph for Claude Code Installation"
        echo ""
        echo "Usage: $0 [install|uninstall]"
        echo ""
        echo "Commands:"
        echo "  install    Install Ralph globally (default)"
        echo "  uninstall  Remove Ralph installation"
        echo "  --help     Show this help"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac