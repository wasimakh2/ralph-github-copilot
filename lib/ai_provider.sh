#!/bin/bash
# AI Provider Abstraction for Ralph
# Supports multiple AI assistants: Claude Code, GitHub Copilot, opencode
# Compatible with bash 3.x (macOS default) and bash 4.x+

# =============================================================================
# AI PROVIDER CONFIGURATION
# =============================================================================

# Supported providers
SUPPORTED_PROVIDERS=("claude" "copilot" "opencode")

# Default provider (can be overridden by environment variable or flag)
AI_PROVIDER="${AI_PROVIDER:-opencode}"

# Provider-specific configuration (bash 3.x compatible - individual variables)
# Claude Code configuration
CLAUDE_CMD="claude"
CLAUDE_OUTPUT_FORMAT="json"
CLAUDE_MIN_VERSION="2.0.76"
CLAUDE_ALLOWED_TOOLS="Write,Bash(git *),Read"
CLAUDE_CONTINUE_FLAG="--continue"
CLAUDE_OUTPUT_FORMAT_FLAG="--output-format"
CLAUDE_PROMPT_FILE_FLAG="--prompt-file"
CLAUDE_ALLOWED_TOOLS_FLAG="--allowedTools"
CLAUDE_SYSTEM_PROMPT_FLAG="--append-system-prompt"

# GitHub Copilot configuration
COPILOT_CMD="gh copilot"
COPILOT_OUTPUT_FORMAT="text"
COPILOT_MIN_VERSION="2.0.0"
COPILOT_SUGGEST_CMD="gh copilot suggest"
COPILOT_EXPLAIN_CMD="gh copilot explain"

# GitHub Copilot CLI extension configuration
# Copilot CLI modes: suggest (shell/git/gh commands), explain (code explanation)
COPILOT_MODE="${COPILOT_MODE:-suggest}"  # suggest or explain
COPILOT_TARGET_TYPE="${COPILOT_TARGET_TYPE:-shell}"  # shell, git, or gh
COPILOT_NO_CONFIRM="${COPILOT_NO_CONFIRM:-true}"  # Skip confirmation prompts

# Variable to store prompt content for Copilot execution
COPILOT_PROMPT_CONTENT=""

# opencode configuration (https://opencode.ai)
OPENCODE_CMD="opencode"
OPENCODE_MIN_VERSION="0.1.0"
OPENCODE_FORMAT="json"                 # opencode run --format: default|json
OPENCODE_MODEL="${OPENCODE_MODEL:-}"   # provider/model, e.g. anthropic/claude-sonnet-4; empty = opencode default

# Colors for output
AI_RED='\033[0;31m'
AI_GREEN='\033[0;32m'
AI_YELLOW='\033[1;33m'
AI_BLUE='\033[0;34m'
AI_NC='\033[0m'

# =============================================================================
# PROVIDER DETECTION AND VALIDATION
# =============================================================================

# Check if a provider is valid
is_valid_provider() {
    local provider=$1
    for p in "${SUPPORTED_PROVIDERS[@]}"; do
        if [[ "$p" == "$provider" ]]; then
            return 0
        fi
    done
    return 1
}

# Detect available AI providers on the system
detect_available_providers() {
    local available=()
    
    # Check for Claude Code CLI
    if command -v claude &> /dev/null; then
        available+=("claude")
    elif command -v npx &> /dev/null && npx @anthropic-ai/claude-code --version &> /dev/null 2>&1; then
        available+=("claude")
    fi
    
    # Check for GitHub Copilot CLI
    if command -v gh &> /dev/null; then
        if gh extension list 2>/dev/null | grep -q "copilot"; then
            available+=("copilot")
        fi
    fi

    # Check for opencode CLI
    if command -v opencode &> /dev/null; then
        available+=("opencode")
    fi

    echo "${available[@]}"
}

# Check if the selected provider is available
check_provider_available() {
    local provider=${1:-$AI_PROVIDER}
    
    case "$provider" in
        claude)
            if command -v claude &> /dev/null; then
                return 0
            elif command -v npx &> /dev/null; then
                return 0
            fi
            return 1
            ;;
        copilot)
            if command -v gh &> /dev/null; then
                if gh extension list 2>/dev/null | grep -q "copilot"; then
                    return 0
                fi
            fi
            return 1
            ;;
        opencode)
            command -v opencode &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Get the command for the selected provider
get_provider_cmd() {
    local provider=${1:-$AI_PROVIDER}
    case "$provider" in
        claude) echo "$CLAUDE_CMD" ;;
        copilot) echo "$COPILOT_CMD" ;;
        opencode) echo "$OPENCODE_CMD" ;;
        *) echo "" ;;
    esac
}

# Get provider version
get_provider_version() {
    local provider=${1:-$AI_PROVIDER}
    
    case "$provider" in
        claude)
            claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
            ;;
        copilot)
            gh copilot --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
            ;;
        opencode)
            opencode --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
            ;;
    esac
}

# Check provider version compatibility
check_provider_version() {
    local provider=${1:-$AI_PROVIDER}
    local version
    version=$(get_provider_version "$provider")
    local min_version
    case "$provider" in
        claude) min_version="$CLAUDE_MIN_VERSION" ;;
        copilot) min_version="$COPILOT_MIN_VERSION" ;;
        opencode) min_version="$OPENCODE_MIN_VERSION" ;;
        *) min_version="0.0.0" ;;
    esac

    if [[ -z "$version" ]]; then
        echo -e "${AI_YELLOW}WARN: Cannot detect $provider version${AI_NC}" >&2
        return 0
    fi

    # Simple version comparison
    local ver_parts=("${version//./ }")
    local req_parts=("${min_version//./ }")
    
    local ver_num=$((${ver_parts[0]:-0} * 10000 + ${ver_parts[1]:-0} * 100 + ${ver_parts[2]:-0}))
    local req_num=$((${req_parts[0]:-0} * 10000 + ${req_parts[1]:-0} * 100 + ${req_parts[2]:-0}))
    
    if [[ $ver_num -lt $req_num ]]; then
        echo -e "${AI_YELLOW}WARN: $provider version $version < $min_version${AI_NC}" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# PROVIDER-SPECIFIC COMMAND BUILDING
# =============================================================================

# Global array for AI command arguments
declare -a AI_CMD_ARGS=()

# Build command for Claude Code
build_claude_command() {
    local prompt_file=$1
    local loop_context=$2
    local output_format=${3:-json}
    local allowed_tools=$4
    local use_continue=${5:-true}
    
    AI_CMD_ARGS=("claude")
    
    # Add output format
    if [[ "$output_format" == "json" ]]; then
        AI_CMD_ARGS+=("--output-format" "json")
    fi
    
    # Add allowed tools
    if [[ -n "$allowed_tools" ]]; then
        AI_CMD_ARGS+=("--allowedTools")
        local IFS=','
        read -ra tools_array <<< "$allowed_tools"
        for tool in "${tools_array[@]}"; do
            tool=$(echo "$tool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -n "$tool" ]]; then
                AI_CMD_ARGS+=("$tool")
            fi
        done
    fi
    
    # Add session continuity
    if [[ "$use_continue" == "true" ]]; then
        AI_CMD_ARGS+=("--continue")
    fi
    
    # Add loop context
    if [[ -n "$loop_context" ]]; then
        AI_CMD_ARGS+=("--append-system-prompt" "$loop_context")
    fi
    
    # Add prompt file
    AI_CMD_ARGS+=("--prompt-file" "$prompt_file")
}

# Build command for GitHub Copilot
build_copilot_command() {
    local prompt_file=$1
    local loop_context=$2
    local mode=${3:-$COPILOT_MODE}
    local target_type=${4:-$COPILOT_TARGET_TYPE}
    
    # Read prompt content
    local prompt_content=""
    if [[ -f "$prompt_file" ]]; then
        prompt_content=$(cat "$prompt_file")
    fi
    
    # Add loop context to prompt
    if [[ -n "$loop_context" ]]; then
        prompt_content="Context: $loop_context\n\n$prompt_content"
    fi
    
    # Build command based on mode
    case "$mode" in
        suggest)
            # gh copilot suggest -t <type> "<prompt>"
            AI_CMD_ARGS=("gh" "copilot" "suggest")
            AI_CMD_ARGS+=("-t" "$target_type")
            ;;
        explain)
            # gh copilot explain "<prompt>"
            AI_CMD_ARGS=("gh" "copilot" "explain")
            ;;
        *)
            AI_CMD_ARGS=("gh" "copilot" "suggest")
            AI_CMD_ARGS+=("-t" "shell")
            ;;
    esac
    
    # Store prompt content for execution
    COPILOT_PROMPT_CONTENT="$prompt_content"
}

# Build command for opencode
build_opencode_command() {
    local prompt_file=$1
    local loop_context=$2
    local use_continue=${3:-true}

    local prompt_content=""
    if [[ -f "$prompt_file" ]]; then
        prompt_content=$(cat "$prompt_file")
    fi

    if [[ -n "$loop_context" ]]; then
        prompt_content="Context: $loop_context

$prompt_content"
    fi

    # ponytail: message passed as one positional arg (no --prompt-file in opencode CLI);
    # fine for typical prompt sizes, raise if ARG_MAX ever bites.
    AI_CMD_ARGS=("$OPENCODE_CMD" "run" "$prompt_content" "--format" "$OPENCODE_FORMAT")

    if [[ "$use_continue" == "true" ]]; then
        AI_CMD_ARGS+=("--continue")
    fi

    if [[ -n "$OPENCODE_MODEL" ]]; then
        AI_CMD_ARGS+=("--model" "$OPENCODE_MODEL")
    fi
}

# Build command based on selected provider
build_ai_command() {
    local provider=${1:-$AI_PROVIDER}
    local prompt_file=$2
    local loop_context=$3
    local output_format=${4:-}
    local allowed_tools=${5:-}
    local use_continue=${6:-true}

    case "$provider" in
        claude)
            build_claude_command "$prompt_file" "$loop_context" "$output_format" "$allowed_tools" "$use_continue"
            ;;
        copilot)
            build_copilot_command "$prompt_file" "$loop_context"
            ;;
        opencode)
            build_opencode_command "$prompt_file" "$loop_context" "$use_continue"
            ;;
        *)
            echo "ERROR: Unknown provider: $provider" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# PROVIDER-SPECIFIC EXECUTION
# =============================================================================

# Execute AI command with the selected provider
execute_ai_command() {
    local provider=${1:-$AI_PROVIDER}
    local prompt_file=$2
    local output_file=$3
    local timeout_seconds=${4:-900}
    local loop_context=$5
    local output_format=${6:-}
    local allowed_tools=${7:-}
    local use_continue=${8:-true}
    
    # Build the command
    build_ai_command "$provider" "$prompt_file" "$loop_context" "$output_format" "$allowed_tools" "$use_continue"
    
    case "$provider" in
        claude)
            # Modern execution for Claude
            if timeout "${timeout_seconds}s" "${AI_CMD_ARGS[@]}" > "$output_file" 2>&1; then
                return 0
            else
                local exit_code=$?
                # Try legacy mode if modern fails
                if [[ $exit_code -ne 0 ]]; then
                    if timeout "${timeout_seconds}s" claude < "$prompt_file" > "$output_file" 2>&1; then
                        return 0
                    fi
                fi
                return $exit_code
            fi
            ;;
        copilot)
            # GitHub Copilot execution
            # Build the command first
            build_copilot_command "$prompt_file" "$loop_context"
            
            # Copilot CLI works interactively by default
            # We use script/expect-like approach or pass via stdin where possible
            local prompt_content="$COPILOT_PROMPT_CONTENT"
            
            # Method 1: Try using the --help flag to detect non-interactive capabilities
            # Method 2: Pipe the prompt and hope for the best
            # Note: gh copilot suggest expects interactive input, so we simulate it

            # Create a temporary prompt file for Copilot
            local temp_prompt
            temp_prompt=$(mktemp)
            echo "$prompt_content" > "$temp_prompt"
            
            # Execute with the prompt content
            # gh copilot suggest can take input via stdin in some scenarios
            if echo "$prompt_content" | timeout "${timeout_seconds}s" gh copilot suggest -t "${COPILOT_TARGET_TYPE:-shell}" > "$output_file" 2>&1; then
                rm -f "$temp_prompt"
                return 0
            fi

            # Fallback: Try with explain mode which may handle stdin better
            if timeout "${timeout_seconds}s" gh copilot explain "$prompt_content" > "$output_file" 2>&1; then
                rm -f "$temp_prompt"
                return 0
            fi
            
            rm -f "$temp_prompt"
            return 1
            ;;
        opencode)
            timeout "${timeout_seconds}s" "${AI_CMD_ARGS[@]}" > "$output_file" 2>&1
            return $?
            ;;
        *)
            echo "ERROR: Unknown provider: $provider" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# PROVIDER-SPECIFIC OUTPUT PARSING
# =============================================================================

# Detect output format based on provider
detect_provider_output_format() {
    local provider=${1:-$AI_PROVIDER}
    local output_file=$2
    
    case "$provider" in
        claude)
            # Claude can output JSON or text
            if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
                local first_char
                first_char=$(head -c 1 "$output_file" 2>/dev/null | tr -d '[:space:]')
                if [[ "$first_char" == "{" || "$first_char" == "[" ]]; then
                    if jq empty "$output_file" 2>/dev/null; then
                        echo "json"
                        return
                    fi
                fi
            fi
            echo "text"
            ;;
        copilot)
            # GitHub Copilot typically outputs text with code suggestions
            echo "text"
            ;;
        opencode)
            # opencode --format json emits a JSONL event stream, not one JSON blob;
            # parsed as text (parse_opencode_output greps events directly).
            echo "text"
            ;;
        *)
            echo "text"
            ;;
    esac
}

# Parse output based on provider
parse_provider_output() {
    local provider=${1:-$AI_PROVIDER}
    local output_file=$2
    local result_file=${3:-.ai_parse_result}

    local format
    format=$(detect_provider_output_format "$provider" "$output_file")
    
    case "$provider" in
        claude)
            if [[ "$format" == "json" ]]; then
                # Use existing JSON parser
                parse_json_response "$output_file" "$result_file"
            else
                # Use text analysis
                analyze_text_response "$output_file" "$result_file"
            fi
            ;;
        copilot)
            # Parse GitHub Copilot text output
            parse_copilot_output "$output_file" "$result_file"
            ;;
        opencode)
            parse_opencode_output "$output_file" "$result_file"
            ;;
        *)
            analyze_text_response "$output_file" "$result_file"
            ;;
    esac
}

# Parse GitHub Copilot specific output
parse_copilot_output() {
    local output_file=$1
    local result_file=${2:-.copilot_parse_result}

    if [[ ! -f "$output_file" ]]; then
        echo "ERROR: Output file not found: $output_file" >&2
        return 1
    fi

    local content
    content=$(cat "$output_file")
    local has_completion="false"
    local is_stuck="false"
    local files_modified=0
    local summary=""
    
    # Check for completion signals in Copilot output
    if echo "$content" | grep -qiE '(completed|done|finished|no more suggestions)'; then
        has_completion="true"
    fi
    
    # Check for error patterns
    if echo "$content" | grep -qiE '(error|failed|exception|cannot)'; then
        is_stuck="true"
    fi
    
    # Count file mentions
    files_modified=$(echo "$content" | grep -cE '\.(sh|js|ts|py|go|rs|java|cpp|c|rb|php)' || echo "0")
    
    # Extract summary (first meaningful line)
    summary=$(echo "$content" | head -5 | tr '\n' ' ' | head -c 200)
    
    # Write result
    cat > "$result_file" << EOF
{
    "status": "ANALYZED",
    "exit_signal": $has_completion,
    "is_test_only": false,
    "is_stuck": $is_stuck,
    "has_completion_signal": $has_completion,
    "files_modified": $files_modified,
    "error_count": 0,
    "summary": "$summary",
    "provider": "copilot"
}
EOF
    
    return 0
}

# Parse opencode specific output (JSONL event stream from --format json)
# ponytail: keyword-grep heuristic, not a real event-schema parser — opencode's
# JSON event shape wasn't verified against a live run. Ceiling: misses/misfires
# on wording changes. Upgrade: `jq` per-line parse once the event schema (event
# `type` field names) is confirmed from a real `opencode run --format json` log.
parse_opencode_output() {
    local output_file=$1
    local result_file=${2:-.opencode_parse_result}

    if [[ ! -f "$output_file" ]]; then
        echo "ERROR: Output file not found: $output_file" >&2
        return 1
    fi

    local content
    content=$(cat "$output_file")
    local has_completion="false"
    local is_stuck="false"
    local files_modified=0
    local summary=""

    if echo "$content" | grep -qiE '(session\.idle|"type":"?finish|completed|all tasks complete)'; then
        has_completion="true"
    fi

    if echo "$content" | grep -qiE '(^Error:|^ERROR:|^error:|[Ee]xception|Fatal|FATAL)'; then
        is_stuck="true"
    fi

    files_modified=$(echo "$content" | grep -cE '"tool":"?(write|edit)' || echo "0")

    summary=$(echo "$content" | tail -20 | tr '\n' ' ' | head -c 200)

    cat > "$result_file" << EOF
{
    "status": "ANALYZED",
    "exit_signal": $has_completion,
    "is_test_only": false,
    "is_stuck": $is_stuck,
    "has_completion_signal": $has_completion,
    "files_modified": $files_modified,
    "error_count": 0,
    "summary": "$summary",
    "provider": "opencode"
}
EOF

    return 0
}

# Analyze text response (fallback for both providers)
analyze_text_response() {
    local output_file=$1
    local result_file=${2:-.text_parse_result}

    if [[ ! -f "$output_file" ]]; then
        return 1
    fi

    local content
    content=$(cat "$output_file")
    local has_completion="false"
    local is_stuck="false"
    
    # Check for completion signals
    if echo "$content" | grep -qiE '(all tasks complete|project complete|done|finished)'; then
        has_completion="true"
    fi
    
    # Check for stuck patterns
    if echo "$content" | grep -qiE '(error:|failed:|exception|fatal)'; then
        is_stuck="true"
    fi
    
    cat > "$result_file" << EOF
{
    "status": "ANALYZED",
    "exit_signal": $has_completion,
    "is_stuck": $is_stuck,
    "has_completion_signal": $has_completion,
    "provider": "${AI_PROVIDER:-unknown}"
}
EOF
}

# =============================================================================
# PROVIDER INFO AND HELP
# =============================================================================

# Show available providers
show_available_providers() {
    echo "Available AI Providers:"
    echo ""

    local available
    available=$(detect_available_providers)
    
    for provider in "${SUPPORTED_PROVIDERS[@]}"; do
        local status="❌ Not installed"
        local version=""
        
        if [[ " $available " =~ " $provider " ]]; then
            status="✅ Available"
            version=$(get_provider_version "$provider")
            if [[ -n "$version" ]]; then
                version=" (v$version)"
            fi
        fi
        
        echo "  $provider: $status$version"
    done
    echo ""
    echo "Current provider: $AI_PROVIDER"
}

# Show provider installation instructions
show_provider_install_help() {
    local provider=$1
    
    case "$provider" in
        claude)
            echo "Install Claude Code CLI:"
            echo "  npm install -g @anthropic-ai/claude-code"
            echo "  OR"
            echo "  npx @anthropic-ai/claude-code"
            ;;
        copilot)
            echo "Install GitHub Copilot CLI:"
            echo "  1. Install GitHub CLI: https://cli.github.com/"
            echo "  2. gh auth login"
            echo "  3. gh extension install github/gh-copilot"
            ;;
        opencode)
            echo "Install opencode:"
            echo "  macOS/Linux: curl -fsSL https://opencode.ai/install | bash"
            echo "  macOS (brew): brew install sst/tap/opencode"
            echo "  npm (all platforms incl. Windows): npm install -g opencode-ai"
            ;;
    esac
}

# Set the active provider
set_ai_provider() {
    local provider=$1
    
    if ! is_valid_provider "$provider"; then
        echo "ERROR: Invalid provider '$provider'. Valid options: ${SUPPORTED_PROVIDERS[*]}" >&2
        return 1
    fi
    
    if ! check_provider_available "$provider"; then
        echo "ERROR: Provider '$provider' is not available on this system" >&2
        show_provider_install_help "$provider"
        return 1
    fi
    
    AI_PROVIDER="$provider"
    export AI_PROVIDER
    echo "AI provider set to: $AI_PROVIDER"
}
