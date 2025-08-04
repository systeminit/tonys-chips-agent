#!/bin/bash
set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to display error message
show_claude_installation_error() {
    echo -e "${RED}❌ Error: 'claude' is not installed!${NC}" >&2
    echo -e "${YELLOW}📖 Please follow the documentation at: https://www.anthropic.com/claude-code${NC}" >&2
    echo -e "${YELLOW}💡 Summary: Install Node.js and run 'npm install -g @anthropic-ai/claude-code'${NC}" >&2
}

# Function to display docker error message
show_docker_installation_error() {
    echo -e "${RED}❌ Error: 'docker' is not installed!${NC}" >&2
    
    # Detect platform and provide specific guidance
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${YELLOW}🍎 On macOS: Install Docker Desktop from https://www.docker.com/products/docker-desktop/${NC}" >&2
    else
        echo -e "${YELLOW}🐧 Please consult your platform's documentation for Docker installation instructions${NC}" >&2
    fi
}

# Function to prompt for API token
prompt_for_api_token() {
    echo -e "${BLUE}🔑 System Initiative API Token Required${NC}"
    echo -e "${YELLOW}To get your API token:${NC}"
    echo -e "${YELLOW}1. Go to: https://auth.systeminit.com/workspaces${NC}"
    echo -e "${YELLOW}2. Click the 'gear' icon for your workspace${NC}"
    echo -e "${YELLOW}3. Select 'API Tokens'${NC}"
    echo -e "${YELLOW}4. Name it 'claude code'${NC}"
    echo -e "${YELLOW}5. Generate a new token with 1y expiration${NC}"
    echo -e "${YELLOW}6. Copy the token from the UI${NC}"
    echo ""
    
    local token
    while true; do
        echo -e "${BLUE}Please paste your API token:${NC}"
        read -r -s token
        
        if [[ -z "$token" ]]; then
            echo -e "${RED}❌ Token cannot be empty${NC}" >&2
            continue
        fi
        
        # Basic JWT format validation (three base64 parts separated by dots)
        if [[ "$token" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
            export SI_API_TOKEN="$token"
            echo -e "${GREEN}✅ API token set successfully${NC}"
            break
        else
            echo -e "${RED}❌ Invalid token format. System Initiative tokens are JWTs${NC}" >&2
        fi
    done
}

# Function to create .mcp.json file
create_mcp_config() {
    local mcp_file="${1:-}"
    if [[ -z "$mcp_file" ]]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        mcp_file="$script_dir/.mcp.json"
    fi
    
    echo -e "${BLUE}📄 Creating MCP configuration file${NC}"
    
    cat > "$mcp_file" << EOF
{
  "mcpServers": {
    "system-initiative": {
      "type": "stdio",
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        "--pull=always",
        "-e",
        "SI_API_TOKEN",
        "systeminit/si-mcp-server:stable"
      ],
      "env": {
        "SI_API_TOKEN": "${SI_API_TOKEN}"
      }
    }
  }
}
EOF
    
    echo -e "${GREEN}✅ Created .mcp.json at: $mcp_file${NC}"
}

# Main script logic
main() {
    local mcp_config_file="${1:-}"
    
    if ! command_exists claude; then
        show_claude_installation_error
        exit 1
    fi
    echo "✅ claude is installed and available"
    
    if ! command_exists docker; then
        show_docker_installation_error
        exit 1
    fi
    echo "✅ docker is installed and available"
    
    # Check if API token is already set in environment
    if [[ -n "${SI_API_TOKEN:-}" ]]; then
        echo -e "${GREEN}🔑 Found existing SI_API_TOKEN in environment${NC}"
        echo -e "${BLUE}Use existing token? (y/n):${NC}"
        read -r use_existing
        
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            echo "✅ Using existing SI_API_TOKEN"
            create_mcp_config "$mcp_config_file"
            return
        fi
    fi
    
    prompt_for_api_token
    
    # Create MCP configuration file
    create_mcp_config "$mcp_config_file"
}

# Run main function
main "$@"
