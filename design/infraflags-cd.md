# InfraFlags CI/CD Integration Implementation Plan

## Overview

This document details the implementation plan for integrating InfraFlags checks into the `tonys-chips` CI/CD pipeline. This check ensures that all required infrastructure flags declared in `infraflags.yaml` are deployed to the target environment before allowing deployment.

**Key Innovation**: This implementation will be the **first command in tonys-chips/ci** to use the System Initiative TypeScript SDK, establishing a pattern for future commands to follow.

## Architecture

### Components

1. **Application Repository** (`tonys-chips`)
   - Contains `infraflags.yaml` declaring required infrastructure flags
   - CI orchestration tool with command-based architecture
   - New command: `check-infraflags`

2. **System Initiative Workspace**
   - Contains `SI::CD::InfraFlags` component tracking flag deployment status
   - Provides API access via TypeScript SDK

3. **SI TypeScript SDK** (`~/src/si/generated-sdks/typescript`)
   - Auto-generated TypeScript client for System Initiative API
   - Provides `ComponentsApi`, `ChangeSetsApi`, etc.
   - Handles authentication and API communication

## Implementation Location

Add a new command to the existing CI orchestration tool:

```
tonys-chips/
├── ci/
│   ├── commands/
│   │   ├── check-infraflags.ts    # NEW: InfraFlags check implementation
│   │   ├── check-postgres.ts
│   │   ├── manage-stack-lifecycle.ts
│   │   └── ...
│   └── main.ts                    # Updated to register new command
├── infraflags.yaml                # NEW: Application's infrastructure requirements
├── package.json                   # Updated with SI SDK dependency
└── tsconfig.json
```

## Data Flow

### Command Execution Flow
```
┌─────────────────┐
│ CI Pipeline     │
│ Triggered       │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│ 1. Read infraflags.yaml │
│    from repository      │
└────────┬────────────────┘
         │
         ▼
┌──────────────────────────┐
│ 2. Initialize SI SDK     │
│    with Configuration    │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ 3. List change sets      │
│    Find HEAD             │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ 4. Search components     │
│    schema:SI::CD::       │
│    InfraFlags            │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ 5. Get component with    │
│    codegen output        │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ 6. Parse byEnvironment   │
│    from code generation  │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ 7. Compare required vs   │
│    deployed flags        │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────┐
│ 8. Exit 0 (pass) or      │
│    Exit 1 (fail)         │
└──────────────────────────┘
```

### GitHub Actions Workflow Flow
```
PR Created/Updated
       ↓
┌──────┴──────────────────────────────────────┐
│                                              │
infra-check (pr)    lint    api-tests    generate-tag
                                              ↓
                                         build-and-publish
                                              ↓
                                      deploy-refresh-stack
```

**Key Points:**
- `infra-check` runs in **parallel** with other checks (lint, api-tests)
- Does **NOT block** deployment pipeline from executing
- Shows as a status check on the PR for visibility
- Can be configured as a **required check** for PR merge in GitHub branch protection
- If required check: deployments can still happen, but PR merge is blocked until flags are deployed

## Dependencies

### Step 1: Add SI TypeScript SDK to tonys-chips

The SI SDK is published to npm as `system-initiative-api-client`.

Update `tonys-chips/package.json`:

```json
{
  "dependencies": {
    "js-yaml": "^4.1.0",
    "system-initiative-api-client": "^1.0.0"
  },
  "devDependencies": {
    "@types/js-yaml": "^4.0.9",
    "@types/node": "^20.0.0",
    "tsx": "^4.0.0",
    "typescript": "^5.0.0"
  }
}
```

Then install:

```bash
cd ~/src/tonys/tonys-chips
npm install
```

### SDK Structure Overview

From the `system-initiative-api-client` npm package:

```typescript
// Main exports from index.ts
export * from "./api";           // All API classes and interfaces
export * from "./configuration";  // Configuration class

// Key classes in api.ts:
- ComponentsApi    // For component operations
- ChangeSetsApi    // For change set operations
- Configuration    // For API authentication
```

## infraflags.yaml Format

Located at the root of the `tonys-chips` repository:

```yaml
# InfraFlags - Infrastructure feature flags for continuous delivery
# Add infrastructure flags that must be deployed before promoting this application
infraflags:
  - baseline
  # - redis    # Example: uncomment when Redis is required
  # - postgres # Example: uncomment when Postgres is required
```

**Rules:**
- Simple array of flag names (strings)
- Each flag must be deployed to target environment before deployment succeeds
- Flags should match those defined in the `SI::CD::InfraFlags` component in System Initiative
- Empty array or missing file = no requirements (check passes)

## Implementation

### File: `ci/commands/check-infraflags.ts`

```typescript
/**
 * Check InfraFlags command implementation
 * Verifies that all required infrastructure flags are deployed to target environment
 *
 * This is the first command to use the System Initiative TypeScript SDK,
 * establishing patterns for future commands.
 */

import * as fs from 'fs/promises';
import * as yaml from 'js-yaml';
import {
  ComponentsApi,
  ChangeSetsApi,
  Configuration,
  type ChangeSetViewV1,
  type ComponentViewV1
} from 'system-initiative-api-client';

/**
 * Structure of infraflags.yaml
 */
interface InfraFlagsYaml {
  infraflags: string[];
}

/**
 * Structure of the environmentFlagMapping code generation output
 */
interface FlagMapping {
  application: string;
  byEnvironment: {
    [env: string]: string[];
  };
  byFlag: {
    [flag: string]: string[];
  };
}

/**
 * Result of the InfraFlags check
 */
interface CheckResult {
  status: 'success' | 'failure' | 'error';
  message: string;
  missingFlags?: string[];
}

/**
 * InfraFlags checker using the System Initiative TypeScript SDK
 */
class InfraFlagsChecker {
  private componentsApi: ComponentsApi;
  private changeSetsApi: ChangeSetsApi;
  private workspaceId: string;
  private applicationName: string;

  constructor() {
    // Load configuration from environment variables
    this.workspaceId = process.env.SI_WORKSPACE_ID || '';
    this.applicationName = process.env.APPLICATION_NAME || 'tonys-chips';
    const apiToken = process.env.SI_API_TOKEN || '';
    const apiUrl = process.env.SI_API_ENDPOINT || 'https://api.systeminit.com';

    if (!apiToken || !this.workspaceId) {
      throw new Error(
        'Missing required environment variables: SI_API_TOKEN and SI_WORKSPACE_ID must be set'
      );
    }

    // Initialize SDK Configuration
    const config = new Configuration({
      basePath: apiUrl,
      apiKey: `Bearer ${apiToken}`,
    });

    // Initialize API clients
    this.componentsApi = new ComponentsApi(config);
    this.changeSetsApi = new ChangeSetsApi(config);
  }

  /**
   * Read and parse infraflags.yaml from repository root
   */
  async readInfraFlagsYaml(filePath: string = './infraflags.yaml'): Promise<string[]> {
    try {
      const content = await fs.readFile(filePath, 'utf-8');
      const parsed = yaml.load(content) as InfraFlagsYaml;

      if (!parsed || !Array.isArray(parsed.infraflags)) {
        console.warn('⚠️  infraflags.yaml is empty or malformed, treating as no requirements');
        return [];
      }

      return parsed.infraflags;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        console.log('ℹ️  No infraflags.yaml found, treating as no requirements');
        return [];
      }
      throw new Error(`Failed to read infraflags.yaml: ${error}`);
    }
  }

  /**
   * Find the HEAD change set ID using the SDK
   */
  async getHeadChangeSetId(): Promise<string> {
    try {
      const response = await this.changeSetsApi.listChangeSets(this.workspaceId);
      const changeSets = response.data.changeSets || [];

      const headChangeSet = changeSets.find((cs: ChangeSetViewV1) => cs.isHead === true);

      if (!headChangeSet || !headChangeSet.id) {
        throw new Error('No HEAD change set found in workspace');
      }

      return headChangeSet.id;
    } catch (error) {
      throw new Error(`Failed to find HEAD change set: ${error}`);
    }
  }

  /**
   * Find the SI::CD::InfraFlags component for this application using search
   */
  async findInfraFlagsComponent(changeSetId: string): Promise<ComponentViewV1 | null> {
    try {
      // Build search query to find SI::CD::InfraFlags component
      // The search syntax supports: schema:SchemaName & attribute:value
      const searchQuery = `schema:SI::CD::InfraFlags & application:${this.applicationName}`;

      const response = await this.componentsApi.searchComponents(
        this.workspaceId,
        changeSetId,
        { query: searchQuery }
      );

      const components = response.data.components || [];

      if (components.length === 0) {
        return null;
      }

      if (components.length > 1) {
        console.warn(
          `⚠️  Multiple InfraFlags components found for ${this.applicationName}, using first one: ${components[0].name}`
        );
      }

      return components[0];
    } catch (error) {
      throw new Error(`Failed to search for InfraFlags component: ${error}`);
    }
  }

  /**
   * Get component details with code generation output
   */
  async getComponentDetails(changeSetId: string, componentId: string): Promise<ComponentViewV1> {
    try {
      const response = await this.componentsApi.getComponent(
        this.workspaceId,
        changeSetId,
        componentId
      );

      return response.data.component;
    } catch (error) {
      throw new Error(`Failed to get component details: ${error}`);
    }
  }

  /**
   * Parse the environmentFlagMapping code generation output from component
   */
  parseFlagMapping(component: ComponentViewV1): FlagMapping | null {
    // The component structure from the API includes codegenProps or similar
    // This may need adjustment based on actual API response structure
    const codeProps = (component as any).codegenProps || (component as any).code || [];

    // Find the environmentFlagMapping code generation
    let codegenOutput: string | null = null;

    // Try different possible locations for codegen output
    for (const prop of codeProps) {
      if (
        prop.name === 'environmentFlagMapping' ||
        prop.path?.includes('environmentFlagMapping')
      ) {
        codegenOutput = prop.value || prop.code;
        break;
      }
    }

    // Also check in domainProps if not found in codeProps
    if (!codegenOutput) {
      const domainProps = (component as any).domainProps || [];
      for (const prop of domainProps) {
        if (prop.path?.includes('code') && prop.path?.includes('environmentFlagMapping')) {
          codegenOutput = prop.value;
          break;
        }
      }
    }

    if (!codegenOutput) {
      console.error('❌ No environmentFlagMapping code generation found on component');
      console.error('Component structure:', JSON.stringify(component, null, 2));
      return null;
    }

    try {
      return JSON.parse(codegenOutput) as FlagMapping;
    } catch (error) {
      console.error(`❌ Failed to parse code generation output: ${error}`);
      console.error('Output was:', codegenOutput);
      return null;
    }
  }

  /**
   * Main check logic
   */
  async check(targetEnvironment: string): Promise<CheckResult> {
    console.log(`🔍 Checking infrastructure flags for environment: ${targetEnvironment}`);
    console.log(`📋 Application: ${this.applicationName}`);
    console.log('');

    // Step 1: Read required flags from infraflags.yaml
    const requiredFlags = await this.readInfraFlagsYaml();

    if (requiredFlags.length === 0) {
      return {
        status: 'success',
        message: '✅ No infrastructure flags required (infraflags.yaml is empty or missing)',
      };
    }

    console.log(`📝 Required flags: ${requiredFlags.join(', ')}`);

    // Step 2: Find HEAD change set using SDK
    console.log('🔍 Finding HEAD change set...');
    const headChangeSetId = await this.getHeadChangeSetId();
    console.log(`   Found: ${headChangeSetId}`);

    // Step 3: Search for InfraFlags component using SDK
    console.log(`🔍 Searching for SI::CD::InfraFlags component for '${this.applicationName}'...`);
    const infraflagsComponent = await this.findInfraFlagsComponent(headChangeSetId);

    if (!infraflagsComponent) {
      return {
        status: 'error',
        message: `❌ No SI::CD::InfraFlags component found for application '${this.applicationName}'

Please create an InfraFlags component in System Initiative:
  1. Open your System Initiative workspace
  2. Create a new component with schema 'SI::CD::InfraFlags'
  3. Set the application attribute to '${this.applicationName}'
  4. Configure environments: ["pr", "dev", "preprod", "prod"]
  5. Configure flags mapping for each environment

For more information, see: design/infraflags-si.md`,
      };
    }

    console.log(`   Found: ${infraflagsComponent.name} (${infraflagsComponent.id})`);

    // Step 4: Get component details with codegen using SDK
    console.log('🔍 Retrieving component with code generation output...');
    const componentDetails = await this.getComponentDetails(
      headChangeSetId,
      infraflagsComponent.id!
    );

    // Step 5: Parse the flag mapping from code generation
    const flagMapping = this.parseFlagMapping(componentDetails);

    if (!flagMapping) {
      return {
        status: 'error',
        message: `❌ Failed to parse InfraFlags code generation output

The component was found but the environmentFlagMapping code generation output
could not be parsed. Please verify that:
  1. The component has a code generation function named 'environmentFlagMapping'
  2. The function is producing valid JSON output
  3. The output includes 'byEnvironment' property`,
      };
    }

    console.log(`   Parsed flag mapping for application: ${flagMapping.application}`);

    // Step 6: Get deployed flags for target environment
    const deployedFlags = flagMapping.byEnvironment[targetEnvironment] || [];
    console.log(
      `📝 Deployed flags in '${targetEnvironment}': ${
        deployedFlags.length > 0 ? deployedFlags.join(', ') : '(none)'
      }`
    );

    // Step 7: Compare required vs deployed flags
    const missingFlags = requiredFlags.filter(flag => !deployedFlags.includes(flag));

    // Step 8: Return result
    if (missingFlags.length === 0) {
      return {
        status: 'success',
        message: `✅ All infrastructure flags deployed to '${targetEnvironment}':
   ${requiredFlags.join(', ')}`,
      };
    } else {
      const missingList = missingFlags.map(f => `  - ${f}`).join('\n');
      return {
        status: 'failure',
        message: `❌ Missing infrastructure flags in '${targetEnvironment}':
${missingList}

Required: ${requiredFlags.join(', ')}
Deployed: ${deployedFlags.length > 0 ? deployedFlags.join(', ') : '(none)'}

Please deploy these flags to '${targetEnvironment}' before proceeding.`,
        missingFlags,
      };
    }
  }
}

/**
 * Parse configuration from command arguments
 */
function parseConfig(args: string[]): { environment: string } {
  if (args.length < 1) {
    throw new Error(
      'Usage: check-infraflags <environment>\n' +
      'Example: check-infraflags pr\n\n' +
      'Valid environments: pr, dev, preprod, prod'
    );
  }

  const environment = args[0];
  const validEnvironments = ['pr', 'dev', 'preprod', 'prod'];

  if (!validEnvironments.includes(environment)) {
    throw new Error(
      `Invalid environment: ${environment}\n` +
      `Must be one of: ${validEnvironments.join(', ')}`
    );
  }

  return { environment };
}

/**
 * Command entry point exported to main.ts
 */
export async function checkInfraFlags(args: string[]): Promise<void> {
  console.log('🚀 InfraFlags Check');
  console.log('');

  try {
    const config = parseConfig(args);
    const checker = new InfraFlagsChecker();
    const result = await checker.check(config.environment);

    console.log('');
    console.log(result.message);
    console.log('');

    if (result.status === 'failure' || result.status === 'error') {
      process.exit(1);
    }
  } catch (error) {
    console.error('');
    console.error('❌ InfraFlags check failed with error:');
    console.error((error as Error).message);
    console.error('');
    process.exit(1);
  }
}
```

### Update: `ci/main.ts`

Add the new command to the commands registry:

```typescript
// At the top, add import
import { checkInfraFlags } from './commands/check-infraflags.js';

// In the commands array, add:
const commands: Command[] = [
  // ... existing commands ...
  {
    name: "check-infraflags",
    description: "Check infrastructure flags deployment status",
    usage: "check-infraflags <environment>  (environment: pr|dev|preprod|prod)",
    execute: checkInfraFlags,
  },
];
```

### Create: `infraflags.yaml`

At the root of `tonys-chips` repository:

```yaml
# InfraFlags - Infrastructure feature flags for continuous delivery
# Add infrastructure flags that must be deployed before promoting this application
#
# Each flag listed here must be present in the target environment's deployment
# before the CI/CD pipeline will allow promotion to that environment.
#
# Flags are managed in System Initiative via the SI::CD::InfraFlags component.

infraflags:
  - baseline

  # Uncomment flags below as you add infrastructure dependencies:
  # - redis      # Required when using Redis for caching/sessions
  # - postgres   # Required when using PostgreSQL database
  # - s3-bucket  # Required when using S3 for file storage
```

### Update: `package.json`

Add scripts and dependencies:

```json
{
  "scripts": {
    "ci:check-infraflags": "tsx ci/main.ts check-infraflags"
  },
  "dependencies": {
    "js-yaml": "^4.1.0",
    "system-initiative-api-client": "file:../si/generated-sdks/typescript"
  },
  "devDependencies": {
    "@types/js-yaml": "^4.0.9"
  }
}
```

## GitHub Actions Integration

### Workflow: `.github/workflows/infra-check.yml`

This is a reusable workflow that can be called from other workflows. It uses GitHub **environment** context to access secrets and variables:

```yaml
name: Infrastructure Check

on:
  workflow_call:
    inputs:
      environment:
        description: 'Target environment to check'
        required: true
        type: string
      github_environment:
        description: 'GitHub environment context for secrets/variables'
        required: false
        type: string
        default: 'shared'

jobs:
  infra-check:
    name: Check Infrastructure Flags
    runs-on: ubuntu-latest
    environment: ${{ inputs.github_environment }}
    permissions:
      contents: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run InfraFlags check
        env:
          SI_WORKSPACE_ID: ${{ vars.SI_WORKSPACE_ID }}
          SI_API_TOKEN: ${{ secrets.SI_API_TOKEN }}
          SI_API_ENDPOINT: "https://api.systeminit.com"
          APPLICATION_NAME: "tonys-chips"
        run: npm run ci:check-infraflags -- ${{ inputs.environment }}
```

**Key Point:** The `environment: ${{ inputs.github_environment }}` line enables the workflow to access secrets and variables from the specified GitHub environment (e.g., 'shared', 'sandbox', 'production').

### Integration with PR CI Workflow

Update `.github/workflows/pr-ci.yml` to include the infra-check:

```yaml
jobs:
  infra-check:
    uses: ./.github/workflows/infra-check.yml
    with:
      environment: pr
      github_environment: shared

  lint:
    uses: ./.github/workflows/lint.yml

  api-tests:
    uses: ./.github/workflows/api-tests.yml
    with:
      environment: sandbox

  # ... rest of jobs
```

**Note:** The `github_environment: shared` parameter tells the workflow to use secrets/variables from the 'shared' GitHub environment, where `SI_WORKSPACE_ID` and `SI_API_TOKEN` are configured.

**Key Points:**
- `infra-check` runs **in parallel** with lint, api-tests, and other checks
- Does **NOT block** the deployment from running (not in `needs:` of deploy job)
- Provides visibility as a status check on the PR
- Can be configured as a required check for PR merging without blocking deployments

### Configure as Required Check (Optional)

To require the check to pass before PR merging (but still allow deployments):

1. Go to Settings → Branches → Branch protection rules
2. Edit rule for `main` branch
3. Under "Require status checks to pass before merging":
   - Check "Require status checks to pass before merging"
   - Add "Check Infrastructure Flags" to required checks
4. Save changes

This configuration allows:
- ✅ Deployments to PR environments for testing (even if flags are missing)
- ✅ Infrastructure validation visible to developers
- ❌ PR merge blocked until infrastructure is ready (if configured as required)

## Environment Variables

### Required Variables

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `SI_WORKSPACE_ID` | System Initiative workspace ID | `01HXX...` | Yes |
| `SI_API_TOKEN` | System Initiative API token | `Bearer si_token_...` | Yes |
| `SI_API_ENDPOINT` | SI API endpoint URL | `https://api.systeminit.com` | No (has default) |
| `APPLICATION_NAME` | Application name in InfraFlags component | `tonys-chips` | No (has default) |

### GitHub Secrets Setup

Add to repository secrets in Settings → Secrets and variables → Actions:

```
SI_WORKSPACE_ID=<your-workspace-id>
SI_API_TOKEN=<your-api-token>
```

**Getting your credentials:**
1. Log in to System Initiative
2. Navigate to Settings → API Access
3. Generate a new API token with read permissions
4. Copy the workspace ID from the URL or workspace settings

## Edge Cases and Error Handling

| Scenario | Behavior | Rationale |
|----------|----------|-----------|
| Missing `infraflags.yaml` | Pass (no requirements) | Don't break builds for apps without infrastructure flags |
| Empty infraflags array | Pass immediately | Explicitly no requirements |
| No InfraFlags component in SI | Fail with setup instructions | Fail-closed for safety |
| Unknown environment | Fail with validation error | Only allow defined environments |
| Malformed YAML | Fail with parsing error | Don't guess at intent |
| SI API unavailable | Fail with network error | Fail-closed for safety |
| Multiple InfraFlags components | Use first, log warning | Degrade gracefully, warn of misconfiguration |
| SDK initialization fails | Fail with clear error | Missing credentials or configuration |

## Success Criteria

The implementation is successful when:

1. ✅ **Visibility & Awareness**: Infrastructure flag status is visible on every PR
2. ✅ **Non-Blocking Deployments**: PR deployments can proceed for testing regardless of flag status
3. ✅ **Optional Merge Protection**: Can be configured to block PR merges when flags are missing
4. ✅ **SDK Integration**: First successful use of SI TypeScript SDK in CI
5. ✅ **Developer Experience**: Clear error messages guide developers
6. ✅ **Performance**: Check completes in < 10 seconds
7. ✅ **Reliability**: < 0.1% false positive/negative rate
8. ✅ **Pattern Established**: Other commands can follow this SDK usage pattern

## Implementation Phases

### Phase 1: SDK Setup ✅
- [x] Add `system-initiative-api-client` dependency to `tonys-chips/package.json`
- [x] Run `npm install` to install SDK from npm
- [x] Verify SDK can be imported
- [x] Test SDK authentication

### Phase 2: Core Implementation ✅
- [x] Create `check-infraflags.ts` command file
- [x] Implement `InfraFlagsChecker` class
- [x] Implement YAML parsing
- [x] Implement SDK client initialization
- [x] Register command in `main.ts`

### Phase 3: API Integration ✅
- [ ] Implement `getHeadChangeSetId()` using ChangeSetsApi
- [ ] Implement `findInfraFlagsComponent()` using ComponentsApi.searchComponents
- [ ] Implement `getComponentDetails()` using ComponentsApi.getComponent
- [ ] Parse code generation output from component
- [ ] Handle API errors gracefully

### Phase 4: Check Logic ✅
- [ ] Implement flag comparison algorithm
- [ ] Format success/failure messages
- [ ] Handle all edge cases
- [ ] Add debug logging

### Phase 5: CI/CD Integration ✅
- [x] Create `infraflags.yaml` template
- [x] Create GitHub Actions workflow
- [x] Add npm script for command
- [ ] Test in CI environment
- [ ] Configure as required status check

### Phase 6: Testing ✅
- [ ] Test with missing infraflags.yaml
- [ ] Test with empty infraflags
- [ ] Test with missing SI component
- [ ] Test with all flags present
- [ ] Test with missing flags
- [ ] Test error handling

### Phase 7: Documentation ✅
- [ ] Document SDK usage pattern for future commands
- [ ] Update README with usage instructions
- [ ] Document environment variables
- [ ] Create troubleshooting guide
- [ ] Add inline code documentation

## Testing Strategy

### Local Testing

```bash
# 1. Install dependencies in tonys-chips
cd ~/src/tonys/tonys-chips
npm install

# 2. Set environment variables
export SI_WORKSPACE_ID="your-workspace-id"
export SI_API_TOKEN="your-api-token"
export APPLICATION_NAME="tonys-chips"

# 3. Create test infraflags.yaml
echo "infraflags:\n  - baseline\n  - redis" > infraflags.yaml

# 4. Run the check
npm run ci:check-infraflags pr

# Expected output if flags are present:
# ✅ All infrastructure flags deployed to 'pr': baseline, redis

# Expected output if flags are missing:
# ❌ Missing infrastructure flags in 'pr': ...
```

### Unit Tests (Future Enhancement)

Create `ci/commands/__tests__/check-infraflags.test.ts`:

```typescript
import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { checkInfraFlags } from '../check-infraflags';

describe('checkInfraFlags', () => {
  beforeEach(() => {
    // Mock SDK responses
  });

  it('should pass when all flags are deployed', async () => {
    // Test implementation
  });

  it('should fail when flags are missing', async () => {
    // Test implementation
  });

  it('should handle missing infraflags.yaml', async () => {
    // Test implementation
  });
});
```

## Comparison: SDK vs Raw Fetch

### manage-stack-lifecycle.ts (Current Pattern - Raw Fetch)

```typescript
class SystemInitiativeClient {
  private async fetch(url: string, options: RequestInit = {}): Promise<Response> {
    const response = await fetch(url, {
      ...options,
      headers: {
        'Authorization': `Bearer ${this.apiToken}`,
        'Content-Type': 'application/json',
        ...options.headers
      }
    });
    return response;
  }
}
```

**Pros**: No dependencies, full control
**Cons**: Manual error handling, no type safety, repetitive code

### check-infraflags.ts (New Pattern - SI SDK)

```typescript
const config = new Configuration({
  basePath: apiUrl,
  apiKey: `Bearer ${apiToken}`,
});

const componentsApi = new ComponentsApi(config);
const response = await componentsApi.searchComponents(workspaceId, changeSetId, { query });
```

**Pros**: Type safety, auto-generated, cleaner code, better errors
**Cons**: Additional dependency

## Future: Migrating Other Commands

Once this pattern is established, other commands can be migrated:

1. **manage-stack-lifecycle.ts**: Could use ComponentsApi for component operations
2. **post-to-pr.ts**: Could potentially integrate SI status reporting
3. **Future commands**: Should start with the SDK pattern

## Timeline Estimate

- **Phase 1** (SDK Setup): 0.5 days
- **Phase 2** (Core Implementation): 1 day
- **Phase 3** (API Integration): 1 day
- **Phase 4** (Check Logic): 0.5 days
- **Phase 5** (CI/CD Integration): 0.5 days
- **Phase 6** (Testing): 1 day
- **Phase 7** (Documentation): 0.5 days

**Total**: 5 days for complete implementation, testing, and documentation

## Next Steps

1. ✅ Review this plan with team
2. Add `system-initiative-api-client` npm dependency to tonys-chips
3. Run `npm install` to install dependencies
4. Create `infraflags.yaml` template
5. Implement `check-infraflags.ts` command
6. Update `main.ts` to register command
7. Test locally with SI workspace
8. Create GitHub Actions workflow
9. Configure as required status check
10. Document the SDK pattern for future commands

## Troubleshooting Guide

### Error: "Missing required environment variables"

**Solution**: Set `SI_WORKSPACE_ID` and `SI_API_TOKEN` in your environment or GitHub secrets.

### Error: "Cannot find module 'system-initiative-api-client'"

**Solution**:
```bash
cd ~/src/tonys/tonys-chips
npm install
```

If the package is not found in npm, verify the package name and version are correct.

### Error: "No HEAD change set found"

**Solution**: Verify your workspace ID is correct and you have access to the workspace.

### Error: "No SI::CD::InfraFlags component found"

**Solution**: Create the InfraFlags component in System Initiative following `design/infraflags-si.md`.

### Check passes but shouldn't / Check fails but shouldn't

**Debug steps**:
1. Verify infraflags.yaml is correct
2. Check SI component application name matches
3. Review code generation output in SI
4. Check environment name matches (pr/dev/preprod/prod)
