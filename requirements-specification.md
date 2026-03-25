# NordLedger — Requirements Specification

> The fictional company specification used as the basis for this project.
> 
## 🏢 Company Snapshot

**NordLedger** is a B2B SaaS company focused on **subscription billing, invoicing, and analytics**.

### At a glance

- **Industry:** B2B SaaS
- **Employees:** ~85
- **Team composition:**
  - 40 in engineering / product
  - 20 in sales / customer success
  - 15 in finance / operations
  - 10 in leadership / admin
- **Customers:** ~1,200 SMB customers in Europe, plus a few in the US
- **Growth:** ~2× in 18 months
- **Traffic pattern:** Significant usage spikes during end-of-month billing runs

### What NordLedger does

NordLedger helps other businesses manage recurring billing by enabling them to:

- track who should pay what
- create and send invoices
- handle upgrades, downgrades, and cancellations
- generate reports showing revenue and billing trends

---

## 👥 Locations, Users, and Roles

### Physical locations

- **HQ:** Stockholm (~45 staff)
- **Satellite office:** Berlin (~15 staff)
- **Sales hub:** London (~10 staff)
- **Remote employees:** Distributed across the EU/UK, with occasional travel

### User groups

#### Engineering
- Includes backend, frontend, data, and QA teams. Requires access to dev, test, and prod environments with strict separation between environments.

#### DevOps / Platform
- Small team of 2 people. Requires elevated administrative access with strong control and auditing.

#### Customer Support
- Requires access to customer accounts, but not to raw payment details.

#### Finance
- Requires access to invoicing, payouts, accounting exports, and audit trails.

#### Sales / Customer Success
- Requires access to the CRM and limited customer metadata.

#### Executives
- Requires read-only access to reports and dashboards.

#### Contractors
- Requires time-limited access restricted to specific projects and environments.

---

## 💻 Devices (Managed vs BYOD)

### Managed devices

All employees are issued company-managed devices:

- laptops (mix of **macOS** and **Windows**)
- mobile devices (**iOS** / **Android**) for:
  - email
  - MFA
  - chat

### BYOD

Bring Your Own Device is allowed only for:

- contractors
- temporary exception cases for employees

**BYOD requirements:**

- device posture checks must be enforced
  - OS version
  - encryption enabled
  - screen lock enabled
- access must be limited mainly to:
  - SaaS apps
  - ticketing systems
  - documentation
- production access should be heavily restricted

---

## 🔐 Identity, SSO, MFA, and Admin Access

### Identity requirements

- Centralized **SSO** for all applications
  - cloud platforms
  - SaaS tools
  - internal systems
- **MFA required for all users**
- Stronger controls for privileged users
- Preference for:
  - modern authentication standards
  - conditional access policies

### Admin access rules

- No shared admin accounts
- Separate identities for:
  - day-to-day work
  - privileged/admin operations
- Least-privilege access model
- Role-based access control required
- High-risk actions require approval
- Privileged access should be:
  - just-in-time
  - time-boxed

### Break-glass access

Two emergency accounts must exist with:

- offline storage
- strict usage procedures
- full logging
- post-incident review

### Privileged actions must require

- MFA re-prompt
- strong device posture
- immutable audit logging

---

## 🌍 Access Method (Office vs Remote)

### Working model

NordLedger operates in a **hybrid work model**.

Users need secure access from:

- office networks
- home networks
- customer sites while traveling

### Access expectations

- Do not rely on flat network trust
- Prefer identity-aware access controls
- Administrative access should only happen from:
  - hardened endpoints
  - controlled access paths

### Remote access must be reliable for

- engineering workflows
  - CI/CD
  - repositories
  - artifact downloads
- support tooling
  - ticketing
  - customer lookups
- analytics dashboards

---

## 🗂️ Data Types, Residency, and Compliance

### Data handled by the platform

- customer account data
  - names
  - emails
  - addresses
- billing and invoice data
- usage analytics
- support tickets
- employee HR data
- audit logs and security events

### Compliance requirements

- Must comply with **GDPR**
- Strong data protection controls required
- Prefer **EU/EEA data residency** for:
  - customer PII
  - billing records

### Data classification levels

- **Public**
- **Internal**
- **Confidential**
- **Restricted**

### Data protection expectations

- Encryption in transit
- Encryption at rest
- Strong key management
- Key rotation

### Auditability

- Retain security and audit logs for **12–24 months**
- Key audit trails must be stored in tamper-evident systems

### Legal hold / eDiscovery

- Must be able to preserve specific customer records on request

---

## 📈 Availability Targets, RTO, and RPO

### Availability targets

- **Customer-facing app:** 99.95% monthly availability
- **Internal tools:** 99.9% availability acceptable

### Recovery objectives

| System | RTO | RPO |
|---|---:|---:|
| Core transactional system | 1 hour | 5 minutes |
| Analytics / reporting | 24 hours | 24 hours |
| Invoice / PDF generation | 3 hours | 15 minutes |

### Operational expectations

- Disaster recovery approach must be documented
- Recovery testing must be performed regularly
- Customer-facing maintenance should aim for near-zero downtime
- Must plan for:
  - regional outages
  - dependency failures

---

## ⚙️ Workloads, Scale, and Traffic Patterns

### Customer-facing workloads

- web application
- API used by customers
- background workers for:
  - billing runs
  - invoice PDF generation
  - outbound webhooks
  - email notifications
- public integration endpoints supporting:
  - webhooks
  - API keys
  - OAuth-style flows

### Internal workloads

- data warehouse / analytics pipeline
- admin portal
- CI/CD pipelines
- observability systems
  - logs
  - metrics
  - traces

### Current scale

- **Typical load:** ~150–300 requests/second
- **Peak load:** ~1,500–2,500 requests/second during billing/reporting bursts
- **Background jobs at peak:** up to ~200k jobs/day

### Data volume

- **Transactional data:** ~2–4 TB, growing ~150 GB/month
- **Logs / telemetry:** ~1–2 TB/month
- **File objects (invoices/exports):** ~5–10 TB total, growing ~300 GB/month

### Architecture expectations

- Support horizontal scaling
- Maintain strong separation between:
  - dev
  - test
  - stage
  - prod
- Support blue/green or canary rollouts
- Remain vendor-neutral at the requirements level

---

## 🔌 Integrations (SaaS, Partners, Legacy)

### SaaS in use

- ticketing / helpdesk
- chat and video meetings
- version control and CI
- document management / knowledge base
- CRM
- accounting system
- transactional email provider
- payment processor(s)

### Partner and customer integrations

- webhooks to customer systems such as:
  - ERP
  - ecommerce
  - CRM
- SFTP-like batch exports for some enterprise customers
- API access for partners, with:
  - rate limiting
  - auditing

### Legacy / on-prem footprint

- minimal on-prem environment today
  - office networking
  - printers
- one legacy finance reporting server to retire within 6 months

### Integration requirements

- Secure connectivity to SaaS and partner endpoints
- Centralized secrets management for credentials and API keys
- Preference for standard protocols and portability

---

## 🛠️ Operational Constraints

### Team structure

- **Platform / DevOps:** 2 engineers
- **Security:** no dedicated team
  - shared responsibility
  - one engineering security champion
- **Support:** 8 agents

### On-call model

- One engineer on-call rotation
- Escalation only for **P1 incidents**
- Goal is to reduce pager fatigue through:
  - automation
  - SLO-based alerting
  - clearer operational processes

### Release expectations

Engineering wants to deploy **daily**.

This requires:

- automated testing gates
- automated rollback capability
- change tracking
- auditability

### Desired maturity improvements

- infrastructure managed as code
- improved monitoring
- consistent tracing
- centralized logs
- standardized runbooks
- clearer incident response processes

---

## 💰 Budget and Cost Preferences

### Budget posture

- Willing to invest upfront for a solid foundation
- Wants predictable operating costs
- Prefers managed services where they reduce ops burden
- Wants to avoid deep lock-in to proprietary patterns

### Cost requirements

- Tagging and cost allocation by:
  - environment
  - team / product area
  - customer tier where possible
- Budget alerts and cost guardrails
- Automatic scale-down of non-production environments
- Long-term commitments only when usage is stable and measurable

### Initial target spend

- **Estimated monthly cloud budget:** €25k–€45k/month

### Financial visibility desired

- Strong cost transparency
- Unit economics such as:
  - cost per invoice
  - cost per active customer
