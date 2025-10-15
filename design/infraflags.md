# InfraFlags

InfraFlags is a pattern for doing continuous delivery of applications inter-leaved with required infrastructure changes. 

## Description

InfraFlags functions from the perspective of the application developer. Lets say you craft a PR, and it requires the deployment of a Redis server. The developer will edit the infraflags.yaml file:

```yaml
infraflags:
  - redis
  - baseline
```

Adding the 'redis' flag. The developer is then responsible for adding the appropriate infrastructure to the development stack through docker compose, making it work locally and for other software developers.

When the PR is opened, there will be an additional runtime check for `Infrastructure Needed`. This check will use the System Initiative API to search the workspace for a component whose schema is `SI::CD::InfraFlags`, and that has its `application` attribute set to the application in question. It will then look at the `flags` object, whose keys will be the set of infraflags, and values are an array of strings mapping to environments. For example:

```json
{
    "application": "tonys-chips",
    "environments": [
        "pr",
        "dev",
        "preprod",
        "prod"
    ],
    "flags": {
        "redis": ["pr","dev"],
        "baseline": ["pr","dev","preprod","prod"],
    }
}
```

It will search all the enabled infraflags and their environments, and if each flag is present in the environment, the check passes. If any are missing, it collects them all and responds to the PR with the failed infrastructure.

The same check applies as a requiremnet for any promotion in the pipeline.

## Components to build

- The check for the infraflags should be implemented in the ../tonys-chips/ci project as an infraflags check.
- The infraflags component should be implemented as a component in system initiative, with a schema. It should have a code generation function that shows the flags enabled for each environment in an easy form (probably a json output that shows "pr": [..]). It should have a qualification that warns when any flags are not implemented for all environments. 
