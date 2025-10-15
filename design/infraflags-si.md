# InfraFlags System Initiative Component Implementation Plan

## Overview

This document details the implementation plan for the `SI::CD::InfraFlags` schema in System Initiative. This component tracks which infrastructure flags are deployed to which environments, enabling CI/CD pipelines to verify infrastructure readiness before deployment.

## Schema Design

### Schema Details
- **Schema Name**: `SI::CD::InfraFlags`
- **Category**: `SI::CD`
- **Description**: Tracks infrastructure feature flags across environments for continuous delivery
- **Link**: (internal documentation)
- **Color**: `#4A90E2` (blue - representing CI/CD)

### Schema Properties

#### 1. Application Name (required)
- **Path**: `/domain/application`
- **Type**: `string`
- **Widget**: `text`
- **Required**: `true`
- **Documentation**: "The name of the application this InfraFlags component tracks (e.g., 'tonys-chips')"

#### 2. Environments (required)
- **Path**: `/domain/environments`
- **Type**: `array` of `string`
- **Widget**: array of `text` inputs
- **Required**: `true`
- **Documentation**: "List of deployment environments in order (e.g., ['pr', 'dev', 'preprod', 'prod'])"

#### 3. Flags (required)
- **Path**: `/domain/flags`
- **Type**: `map` where keys are flag names and values are arrays of environment names
- **Widget**: `map` with array values
- **Required**: `true`
- **Documentation**: "Map of infrastructure flags to the environments where they are deployed. Key is the flag name, value is an array of environment names where that flag is active."

Example:
```json
{
  "redis": ["pr", "dev"],
  "baseline": ["pr", "dev", "preprod", "prod"],
  "postgres": ["pr", "dev", "preprod"]
}
```

## Asset Builder TypeScript Code

```typescript
function main() {
  const asset = new AssetBuilder();

  // Application name property
  const applicationProp = new PropBuilder()
    .setName("application")
    .setKind("string")
    .setDocumentation("The name of the application this InfraFlags component tracks (e.g., 'tonys-chips')")
    .setWidget(new PropWidgetDefinitionBuilder().setKind("text").build())
    .build();

  // Environments array property
  const environmentsProp = new PropBuilder()
    .setName("environments")
    .setKind("array")
    .setDocumentation("List of deployment environments in order (e.g., ['pr', 'dev', 'preprod', 'prod'])")
    .setEntry(
      new PropBuilder()
        .setName("environment")
        .setKind("string")
        .setWidget(new PropWidgetDefinitionBuilder().setKind("text").build())
        .build()
    )
    .build();

  // Flags map property
  const flagsProp = new PropBuilder()
    .setName("flags")
    .setKind("map")
    .setDocumentation("Map of infrastructure flags to the environments where they are deployed. Key is the flag name, value is an array of environment names where that flag is active.")
    .setEntry(
      new PropBuilder()
        .setName("environments")
        .setKind("array")
        .setEntry(
          new PropBuilder()
            .setName("environment")
            .setKind("string")
            .setWidget(new PropWidgetDefinitionBuilder().setKind("text").build())
            .build()
        )
        .build()
    )
    .build();

  asset.addProp(applicationProp);
  asset.addProp(environmentsProp);
  asset.addProp(flagsProp);

  return asset.build();
}
```

## Code Generation Function

### Function Name
`environmentFlagMapping`

### Function Type
`codegen`

### Purpose
Generate a JSON output that shows which flags are enabled for each environment, making it easy for CI/CD systems to query flag status by environment.

### Input Format
Receives the component's domain properties:
```typescript
{
  domain: {
    application: string,
    environments: string[],
    flags: { [flagName: string]: string[] }
  }
}
```

### Output Format
```json
{
  "application": "tonys-chips",
  "byEnvironment": {
    "pr": ["redis", "baseline"],
    "dev": ["redis", "baseline"],
    "preprod": ["baseline", "postgres"],
    "prod": ["baseline"]
  },
  "byFlag": {
    "redis": ["pr", "dev"],
    "baseline": ["pr", "dev", "preprod", "prod"],
    "postgres": ["preprod", "prod"]
  }
}
```

### TypeScript Implementation

```typescript
async function main(component: Input): Promise<Output> {
  const application = _.get(component, ["domain", "application"], "");
  const environments = _.get(component, ["domain", "environments"], []);
  const flags = _.get(component, ["domain", "flags"], {});

  // Build environment-to-flags mapping
  const byEnvironment: { [env: string]: string[] } = {};

  for (const env of environments) {
    byEnvironment[env] = [];
  }

  for (const [flagName, flagEnvs] of Object.entries(flags)) {
    for (const env of flagEnvs as string[]) {
      if (byEnvironment[env]) {
        byEnvironment[env].push(flagName);
      }
    }
  }

  // Sort flag arrays for consistent output
  for (const env in byEnvironment) {
    byEnvironment[env].sort();
  }

  const result = {
    application,
    byEnvironment,
    byFlag: flags
  };

  return {
    format: "json",
    code: JSON.stringify(result, null, 2),
  };
}
```

## Qualification Function

### Function Name
`incompleteFlags`

### Function Type
`qualification`

### Purpose
Warn when any infrastructure flags are not deployed to all environments, indicating incomplete rollout that may block production deployments.

### Logic
1. Check if any flag exists in the `flags` map
2. For each flag, compare its environment list against the full `environments` list
3. If any flag is missing from one or more environments, emit a warning with details
4. If all flags are deployed to all environments, return success

### TypeScript Implementation

```typescript
async function main(component: Input): Promise<Output> {
  const environments = _.get(component, ["domain", "environments"], []);
  const flags = _.get(component, ["domain", "flags"], {});
  const application = _.get(component, ["domain", "application"], "unknown");

  // If no flags defined, nothing to check
  if (Object.keys(flags).length === 0) {
    return {
      result: "success",
      message: "No infrastructure flags defined",
    };
  }

  // Check each flag against all environments
  const incompleteFlags: { [flagName: string]: string[] } = {};

  for (const [flagName, flagEnvs] of Object.entries(flags)) {
    const flagEnvSet = new Set(flagEnvs as string[]);
    const missingEnvs: string[] = [];

    for (const env of environments) {
      if (!flagEnvSet.has(env)) {
        missingEnvs.push(env);
      }
    }

    if (missingEnvs.length > 0) {
      incompleteFlags[flagName] = missingEnvs;
    }
  }

  // If any flags are incomplete, return warning
  if (Object.keys(incompleteFlags).length > 0) {
    const flagDetails = Object.entries(incompleteFlags)
      .map(([flag, envs]) => `  - '${flag}' missing from: ${envs.join(", ")}`)
      .join("\n");

    return {
      result: "warning",
      message: `Infrastructure flags not fully deployed across all environments for '${application}':\n${flagDetails}\n\nThese flags must be deployed to all environments before production promotion.`,
    };
  }

  return {
    result: "success",
    message: `All infrastructure flags are deployed across all environments for '${application}'`,
  };
}
```

## Implementation Steps

### 1. Create Schema ✅ COMPLETED
- ✅ Created change set named `infraflags-component` (ID: `01K7MNJJ0X4XNCMEFRBFBR4ZG5`)
- ✅ Created `SI::CD::InfraFlags` schema (ID: `01K7MNKQATP2K119YZW0ZRT1R6`)
- ✅ Set category to `SI::CD`
- ✅ Set color to `#4A90E2`
- ✅ Provided the Asset Builder TypeScript code as the definition function

### 2. Create Code Generation Function ✅ COMPLETED
- ✅ Created function `environmentFlagMapping` (ID: `01K7MNV3B4A94MD6F7BZWMTVJ2`)
- ✅ Set function type to `codegen`
- ✅ Attached to the `SI::CD::InfraFlags` schema
- ✅ Provided the code generation TypeScript implementation
- ✅ Added alphabetical sorting for both `byEnvironment` and `byFlag` arrays

### 3. Create Qualification Function ✅ COMPLETED
- ✅ Created function `incompleteFlags` (ID: `01K7MP0SNHKV8XDSQJ4NDX61JZ`)
- ✅ Set function type to `qualification`
- ✅ Attached to the `SI::CD::InfraFlags` schema
- ✅ Provided the qualification TypeScript implementation

### 4. Test the Component ✅ COMPLETED
- ✅ Created test component `tonys-chips-infraflags-test` (ID: `01K7MP6SKH7JBP81NFES1BJP95`)
- ✅ Set application to `tonys-chips`
- ✅ Set environments to `["pr", "dev", "preprod", "prod"]`
- ✅ Set flags with mixed deployment status:
  ```json
  {
    "redis": ["pr", "dev"],
    "baseline": ["pr", "dev", "preprod", "prod"]
  }
  ```
- ✅ Verified code generation outputs correct JSON with alphabetically sorted arrays
- ✅ Verified qualification shows warning for `redis` flag missing from preprod and prod

### 5. Apply Change Set ✅ COMPLETED
- ✅ Reviewed all changes in the change set
- ✅ Applied the change set to HEAD
- ✅ Schema `SI::CD::InfraFlags` is now available in the workspace

## Usage Example

Once deployed, teams will create `SI::CD::InfraFlags` components in their System Initiative workspace:

```yaml
Component Name: tonys-chips-infraflags
Schema: SI::CD::InfraFlags

Attributes:
  /domain/application: "tonys-chips"
  /domain/environments: ["pr", "dev", "preprod", "prod"]
  /domain/flags:
    redis: ["pr", "dev"]
    baseline: ["pr", "dev", "preprod", "prod"]
    postgres: ["pr", "dev", "preprod"]
```

The CI/CD pipeline can then:
1. Query System Initiative API for components with schema `SI::CD::InfraFlags`
2. Filter by application name
3. Read the code generation output to get flag status by environment
4. Check the qualification status to see if all flags are fully deployed
5. Parse the application's `infraflags.yaml` to get required flags
6. Compare required flags against deployed flags for the target environment
7. Block deployment if any required flags are missing

## Integration with CI/CD

The CI pipeline implementation (in `tonys-chips/ci`) should:

1. **Parse Application InfraFlags**: Read `infraflags.yaml` from the repository
2. **Query SI Component**: Use System Initiative API to find the `SI::CD::InfraFlags` component for the application
3. **Extract Code Generation**: Get the `environmentFlagMapping` code generation output
4. **Compare Requirements**: For the target environment (PR, dev, preprod, prod), check that all required flags from `infraflags.yaml` are present in the `byEnvironment[targetEnv]` array
5. **Report Status**:
   - ✅ Pass if all required flags are deployed to target environment
   - ❌ Fail if any required flags are missing, listing which flags need deployment

## Future Enhancements

1. **Flag Metadata**: Add optional description/documentation per flag
2. **Deployment Timestamps**: Track when each flag was deployed to each environment
3. **Flag Dependencies**: Model dependencies between flags (e.g., "postgres" requires "vpc")
4. **Rollback Tracking**: Track flag removals and rollbacks
5. **Multi-Application Support**: Single component tracking multiple applications
