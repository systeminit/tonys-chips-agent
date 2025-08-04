#!/usr/bin/env bats

setup() {
    # Create a temporary directory for fake binaries
    export FAKE_BIN_DIR=$(mktemp -d)
    export ORIGINAL_PATH="$PATH"
}

teardown() {
    # Restore PATH first
    export PATH="$ORIGINAL_PATH"
    # Clean up temporary directory
    /bin/rm -rf "$FAKE_BIN_DIR"
}

# Helper function to create fake binaries
create_fake_binary() {
    local binary_name="$1"
    echo '#!/bin/bash' > "$FAKE_BIN_DIR/$binary_name"
    echo 'exit 0' >> "$FAKE_BIN_DIR/$binary_name"
    chmod +x "$FAKE_BIN_DIR/$binary_name"
}

@test "both claude and docker are installed" {
    create_fake_binary "claude"
    create_fake_binary "docker"
    export PATH="$FAKE_BIN_DIR:$PATH"
    export SI_API_TOKEN="fake_header.fake_payload.fake_signature"
    
    # Create a temporary directory for test config
    local test_dir=$(mktemp -d)
    local test_mcp_file="$test_dir/.mcp.json"
    
    run bash -c "echo 'y' | ./setup.sh '$test_mcp_file'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ claude is installed and available"* ]]
    [[ "$output" == *"✅ docker is installed and available"* ]]
    [[ "$output" == *"✅ Using existing SI_API_TOKEN"* ]]
    
    # Clean up
    rm -rf "$test_dir"
}

@test "claude is missing" {
    create_fake_binary "docker"
    export PATH="$FAKE_BIN_DIR"
    export SI_API_TOKEN="fake_header.fake_payload.fake_signature"
    
    run ./setup.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"❌ Error: 'claude' is not installed!"* ]]
    [[ "$output" == *"https://www.anthropic.com/claude-code"* ]]
    [[ "$output" == *"npm install -g @anthropic-ai/claude-code"* ]]
}

@test "docker is missing" {
    create_fake_binary "claude"
    export PATH="$FAKE_BIN_DIR"
    export SI_API_TOKEN="fake_header.fake_payload.fake_signature"
    
    run ./setup.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"✅ claude is installed and available"* ]]
    [[ "$output" == *"❌ Error: 'docker' is not installed!"* ]]
}

@test "both claude and docker are missing" {
    export PATH="$FAKE_BIN_DIR"
    export SI_API_TOKEN="fake_header.fake_payload.fake_signature"
    
    run ./setup.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"❌ Error: 'claude' is not installed!"* ]]
    # Script exits after claude check, so docker error won't appear
}

@test "docker error message on macOS" {
    create_fake_binary "claude"
    export PATH="$FAKE_BIN_DIR"
    export OSTYPE="darwin21"
    export SI_API_TOKEN="fake_header.fake_payload.fake_signature"
    
    run ./setup.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"🍎 On macOS: Install Docker Desktop from https://www.docker.com/products/docker-desktop/"* ]]
}

@test "docker error message on Linux" {
    create_fake_binary "claude"
    export PATH="$FAKE_BIN_DIR"
    export OSTYPE="linux-gnu"
    export SI_API_TOKEN="fake_header.fake_payload.fake_signature"
    
    run ./setup.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"🐧 Please consult your platform's documentation for Docker installation instructions"* ]]
}

@test "script handles empty PATH gracefully" {
    export PATH=""
    export SI_API_TOKEN="fake_header.fake_payload.fake_signature"
    
    run ./setup.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"❌ Error: 'claude' is not installed!"* ]]
    # Script exits after claude check, so docker error won't appear
}

@test "prompts for API token when none exists" {
    create_fake_binary "claude"
    create_fake_binary "docker"
    export PATH="$FAKE_BIN_DIR:$PATH"
    unset SI_API_TOKEN
    
    # Create a temporary directory for test config
    local test_dir=$(mktemp -d)
    local test_mcp_file="$test_dir/.mcp.json"
    
    run bash -c "echo 'test_header.test_payload.test_signature' | ./setup.sh '$test_mcp_file'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"🔑 System Initiative API Token Required"* ]]
    [[ "$output" == *"Please paste your API token:"* ]]
    [[ "$output" == *"✅ API token set successfully"* ]]
    
    # Clean up
    rm -rf "$test_dir"
}

@test "accepts existing token when user says yes" {
    create_fake_binary "claude"
    create_fake_binary "docker"
    export PATH="$FAKE_BIN_DIR:$PATH"
    export SI_API_TOKEN="existing_header.existing_payload.existing_signature"
    
    # Create a temporary directory for test config
    local test_dir=$(mktemp -d)
    local test_mcp_file="$test_dir/.mcp.json"
    
    run bash -c "echo 'y' | ./setup.sh '$test_mcp_file'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"🔑 Found existing SI_API_TOKEN in environment"* ]]
    [[ "$output" == *"✅ Using existing SI_API_TOKEN"* ]]
    
    # Clean up
    rm -rf "$test_dir"
}

@test "prompts for new token when user says no to existing" {
    create_fake_binary "claude"
    create_fake_binary "docker"
    export PATH="$FAKE_BIN_DIR:$PATH"
    export SI_API_TOKEN="existing_header.existing_payload.existing_signature"
    
    # Create a temporary directory for test config
    local test_dir=$(mktemp -d)
    local test_mcp_file="$test_dir/.mcp.json"
    
    run bash -c "printf 'n\nnew_header.new_payload.new_signature\n' | ./setup.sh '$test_mcp_file'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"🔑 Found existing SI_API_TOKEN in environment"* ]]
    [[ "$output" == *"Please paste your API token:"* ]]
    [[ "$output" == *"✅ API token set successfully"* ]]
    
    # Clean up
    rm -rf "$test_dir"
}

@test "rejects invalid token format" {
    create_fake_binary "claude"
    create_fake_binary "docker"
    export PATH="$FAKE_BIN_DIR:$PATH"
    unset SI_API_TOKEN
    
    # Create a temporary directory for test config
    local test_dir=$(mktemp -d)
    local test_mcp_file="$test_dir/.mcp.json"
    
    run bash -c "printf 'invalid-token\nvalid_header.valid_payload.valid_signature\n' | ./setup.sh '$test_mcp_file'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"❌ Invalid token format. System Initiative tokens are JWTs"* ]]
    [[ "$output" == *"✅ API token set successfully"* ]]
    
    # Clean up
    rm -rf "$test_dir"
}

@test "creates .mcp.json file with correct content" {
    create_fake_binary "claude"
    create_fake_binary "docker"
    export PATH="$FAKE_BIN_DIR:$PATH"
    unset SI_API_TOKEN
    
    # Create a temporary directory for test
    local test_dir=$(mktemp -d)
    local test_mcp_file="$test_dir/.mcp.json"
    
    # Run setup with custom mcp config location, providing API token when prompted
    run bash -c "echo 'test_header.test_payload.test_signature' | ./setup.sh '$test_mcp_file'"
    [ "$status" -eq 0 ]
    
    # Check that .mcp.json was created in the test directory
    [ -f "$test_mcp_file" ]
    
    # Verify the content structure
    local mcp_content=$(cat "$test_mcp_file")
    [[ "$mcp_content" == *'"mcpServers"'* ]]
    [[ "$mcp_content" == *'"system-initiative"'* ]]
    [[ "$mcp_content" == *'"type": "stdio"'* ]]
    [[ "$mcp_content" == *'"command": "docker"'* ]]
    [[ "$mcp_content" == *'"systeminit/si-mcp-server:stable"'* ]]
    [[ "$mcp_content" == *'"SI_API_TOKEN": "test_header.test_payload.test_signature"'* ]]
    
    # Check that output indicates file creation
    [[ "$output" == *"📄 Creating MCP configuration file"* ]]
    [[ "$output" == *"✅ Created .mcp.json at: $test_mcp_file"* ]]
    
    # Clean up
    rm -rf "$test_dir"
}