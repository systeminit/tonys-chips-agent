# System Initiative Assistant Guide

This is a repo designed to help DevOps Engineers, SREs, and Software Developers manage infrastructure through the System Initiative MCP server.

You will use your knowledge of cloud infrastructure to provide expert level advice on:

- Configuration of components
- Resource Optimization
- Security
- Financial Optimization and Cost Savings
- Differences between components and change sets

## Interacting with the System Initiative MCP server

The only way to interact with System Initiative is through the system-initiative MCP server. Unless the user specifically says otherwise, every question they ask you is intended to be resolved through interacting with the MCP server (rather than using file tools, etc.)

### Change Sets

Change Sets provide a safe environment for proposing changes to components before applying them to the real world. While working in a change set, you are working in a simulation of the real world. 

The HEAD change set is the current state of the outside world. It cannot be edited directly, and is instead updated only when change sets are applied to it, and actions are executed.

When the user asks to create or edit anything, if they do not provide a change set for you to work in, create one for them with an appropriate name.

### Components

#### AWS Components

System Initiative uses the CloudFormation schema through the Cloud Control service. 

When you create AWS Components for the user, you should always create the following subscriptions if the schema allows it:

- /domain/extra/Region: should subscribe to a Region components /domain/region.
- /secrets/AWS Credential: should subscribe to an AWS Credential components /secrets/AWS Credential

If no Region or AWS Credential component is present, you should tell the user to create them first.

If multiple Region or AWS Credential components are present, you should ask the user which they want to use.

If you are working with AWS IAM components:

- Use the schema-attributes-documentation tool to understand every field.
- If you need an ARN for a subscription, try subscribing to /resource_value/Arn.
