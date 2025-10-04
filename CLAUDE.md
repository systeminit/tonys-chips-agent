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

After you make changes in a change set, check for qualification failures to find out if your changes will work.

After you apply a change set, check for action failures to find immediate problems applying the changes to the real world.

### Components

#### Hetzner Cloud Components

System Initiative supports Hetzner Cloud infrastructure management through dedicated schemas.

##### Available Hetzner Schemas

**Credential:**
- **Hetzner::Credential::ApiToken** - API token for authenticating with Hetzner Cloud

**Core Infrastructure:**
- **Hetzner::Cloud::Servers** - Virtual machines
- **Hetzner::Cloud::Volumes** - Block storage for servers
- **Hetzner::Cloud::Networks** - Private networks for server-to-server communication
- **Hetzner::Cloud::Firewalls** - Network access control
- **Hetzner::Cloud::LoadBalancers** - Load balancers for traffic distribution
- **Hetzner::Cloud::SshKeys** - SSH public keys for server authentication

**IP Management:**
- **Hetzner::Cloud::FloatingIps** - Globally assignable IPs (note: "Ips" not "IPs")
- **Hetzner::Cloud::PrimaryIps** - Datacenter-bound IPs

**Certificates & High Availability:**
- **Hetzner::Cloud::Certificates** - TLS/SSL certificates
- **Hetzner::Cloud::PlacementGroups** - Control server placement for availability

**Reference Resources:**
- **Hetzner::Cloud::Images** - VM disk blueprints
- **Hetzner::Cloud::ServerTypes** - Available server configurations
- **Hetzner::Cloud::LoadBalancerTypes** - Available load balancer configurations
- **Hetzner::Cloud::Locations** - Geographic locations
- **Hetzner::Cloud::Datacenters** - Virtual datacenters
- **Hetzner::Cloud::Isos** - ISO images for custom OS (note: lowercase "isos")
- **Hetzner::Cloud::Pricing** - Pricing information

##### Creating Hetzner Components

**Important Naming Convention:**
- Schema names use **plural** form (e.g., `Hetzner::Cloud::Servers`, not `Server`)

**Credential Requirements:**
When creating Hetzner components, always set:
- `/secrets/Hetzner Api Token`: should subscribe to a Hetzner::Credential::ApiToken component's `/secrets/Hetzner::Credential::ApiToken`

**Free Resources:**
These resources are free to create and maintain:
- SSH Keys
- Networks (private network definitions)
- Firewalls (firewall rule definitions)
- Placement Groups

**Array Attribute Paths:**
When setting array attributes, the schema uses specific patterns:
- For simple arrays like `source_ips`, use indexed path: `/domain/rules/0/source_ips/0`
- Do NOT append field names like `source_ipsItem` to indexed arrays

**Example: Creating a Network**
```
/domain/name: "my-network"
/domain/ip_range: "10.0.0.0/16"
/domain/expose_routes_to_vswitch: false
/secrets/Hetzner Api Token: {$source: {component: "credential-id", path: "/secrets/Hetzner::Credential::ApiToken"}}
```

**Example: Creating a Firewall**
```
/domain/name: "my-firewall"
/domain/rules/0/direction: "in"
/domain/rules/0/protocol: "tcp"
/domain/rules/0/port: "22"
/domain/rules/0/source_ips/0: "0.0.0.0/0"
/domain/rules/0/description: "Allow SSH"
/secrets/Hetzner Api Token: {$source: {component: "credential-id", path: "/secrets/Hetzner::Credential::ApiToken"}}
```

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

#### AWS IAM Component Creation Guide

When creating and configuring AWS IAM components (roles, users, policies, etc.) for specific use cases, follow these guidelines:

##### Available AWS IAM Schemas

These are the ONLY IAM schemas available in System Initiative:
- **AWS::IAM::Role** - For service roles and cross-account access
- **AWS::IAM::User** - For human users or programmatic access  
- **AWS::IAM::Group** - For grouping users with similar permissions
- **AWS::IAM::ManagedPolicy** - For reusable permission policies
- **AWS::IAM::RolePolicy** - For inline policies attached to roles
- **AWS::IAM::UserPolicy** - For inline policies attached to users
- **AWS::IAM::InstanceProfile** - For EC2 instance roles

**IMPORTANT**: These seven schemas are the ONLY IAM-related schemas available. Do not attempt to create or reference any other IAM schemas as they do not exist in this system.

**Analyze Requirements**  
   - Based on the use case, determine which IAM components are needed
   - Consider security best practices (principle of least privilege)
   - Plan the relationships between components

**Query Schema Actions and Create Core IAM Components**
   - **FIRST**: Use schema query tools to discover available actions for your target schema
   - Start with the primary component (usually Role or User)  
   - Use component-create tool with appropriate schema
   - Configure all required properties with proper values
   - Note: Action names are System Initiative-specific, not standard AWS API names

**Configure Policies (CRITICAL - JSON Formatting)**
   
   **Policy Configuration Rules:**
   - ALWAYS provide complete, valid JSON as a string  
   - Use proper JSON escaping for quotes
   - Include Version field ("2012-10-17")
   - Follow AWS policy syntax exactly

   **Good Example:**
   ```
   Trust policy for EC2 role:
   "{
     \"Version\": \"2012-10-17\",
     \"Statement\": [{
       \"Effect\": \"Allow\",
       \"Principal\": { \"Service\": \"ec2.amazonaws.com\" },
       \"Action\": \"sts:AssumeRole\"
     }]
   }"
   ```

   **Bad Example:**
   ```
   [object Object]
   "{{ trust_policy }}"
   undefined
   ```

6. **Create Supporting Components**
   - Add any required ManagedPolicies with specific permissions
   - Create InstanceProfile if needed for EC2 roles

7. **Configure Relationships**
   - Use component-update to set attribute subscriptions
   - Link roles to instance profiles
   - Attach policies to roles/users/groups
   - Set up proper ARN references

8. **Validate Configuration and Check Qualifications**
   - Review all components for completeness
   - Ensure JSON policies are properly formatted
   - Verify relationships are correctly established
   - **CRITICAL**: Query the qualifications on each schema to check for validation errors before applying the change set
   - Address any qualification failures before proceeding

##### Planning Framework

Before creating components, analyze:
- What AWS services need to be accessed?
- Is this for human users or service roles?  
- What's the minimum set of permissions required?
- Are there existing policies that can be reused?
- What security constraints should be applied?

##### Common Policy Templates

**S3 Read-Only Access Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::bucket-name/*", "arn:aws:s3:::bucket-name"]
  }]
}
```

**Lambda Execution Role Trust Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow", 
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

**EC2 Instance Role Trust Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"  
  }]
}
```
