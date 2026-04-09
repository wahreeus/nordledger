# Resource Design

## Overview

This document describes the main AWS resources used in the NordLedger application architecture. The network layout, subnet structure, and routing design are documented separately in the network design file. This document instead focuses on the application-facing and data-facing services that run on top of that network foundation.

NordLedger uses a serverless application layer together with a managed relational database and object storage. The design supports the platform’s core MVP workflow: receiving requests from the frontend, processing business logic, storing structured customer and invoice data, and generating invoice PDFs for storage and retrieval.

A visual representation of the resource design is presented below.

<p align="center">
  <img src="diagrams/resources.svg" alt="Resource diagram">
</p>

---

## Resource Summary

| Resource | Service | Purpose |
|---|---|---|
| Public API | Amazon API Gateway | Receives HTTPS requests from the frontend and forwards them to backend logic |
| Application compute | AWS Lambda | Runs backend logic for customer creation, invoice creation, and PDF generation |
| Relational database | Amazon RDS for PostgreSQL | Stores customer and invoice data |
| Database high availability | Multi-AZ RDS deployment | Provides failover capability across two Availability Zones |
| Database subnet placement | DB subnet group | Allows RDS to be deployed across private subnets in multiple AZs |
| Document storage | Amazon S3 | Stores generated invoice PDFs |
| Private S3 access | Gateway VPC endpoint for S3 | Allows VPC-connected resources to access S3 without traversing the public internet |

---

## Amazon API Gateway

Amazon API Gateway acts as the public HTTPS entry point for NordLedger’s backend.

Its role is to receive requests from the frontend and expose a clean API surface for backend operations such as:

- registering a new customer
- registering a new invoice
- retrieving invoice-related data
- triggering invoice PDF generation

Using API Gateway makes the backend accessible through standard HTTPS endpoints instead of exposing internal services directly. This keeps the database layer private and ensures that all application requests pass through a controlled entry point.

In this design, API Gateway forwards requests to AWS Lambda, which performs the actual application logic.

---

## AWS Lambda

AWS Lambda is the compute layer for NordLedger.

Lambda functions contain the backend logic that handles incoming API requests. In this design, Lambda is responsible for tasks such as:

- validating and transforming request data
- inserting and reading customer records
- inserting and reading invoice records
- generating invoice PDFs
- uploading generated PDFs to Amazon S3

Lambda is a good fit for NordLedger because the application workflow is event-driven and request-based. The platform does not need permanently running application servers for the MVP. Instead, backend logic can execute only when needed.

Although Lambda is an AWS-managed service, the functions can be attached to the VPC so they can securely communicate with private resources such as the RDS database.

---

## Amazon RDS for PostgreSQL

Amazon RDS for PostgreSQL is used as the primary transactional database for NordLedger.

The database stores the structured application data required for the invoicing workflow. This includes customer records, invoice records, and related invoice metadata. PostgreSQL is a strong fit because the platform works with structured business entities and relationships between them.

Using a managed relational database reduces operational overhead compared with self-managing a database on EC2. Backups, failover support, patching workflows, and database provisioning are handled through a managed AWS service rather than through custom database administration.

In this design, the database is not publicly accessible. It is deployed in private subnets and is intended to be reached only through backend application logic.

---

## Multi-AZ RDS Deployment

The PostgreSQL database is deployed as a Multi-AZ RDS instance.

This means the database runs with:

- one **primary** DB instance
- one **standby** DB instance in a different Availability Zone

The primary instance handles active database traffic. The standby instance exists to support failover if the primary instance or its Availability Zone becomes unavailable.

This is an important design choice for NordLedger because invoice and customer data are business-critical. Even in an MVP or portfolio setting, a Multi-AZ database better reflects how a production-oriented billing platform should protect its transactional data layer.

---

## DB Subnet Group

The RDS deployment uses a DB subnet group.

A DB subnet group defines which subnets Amazon RDS is allowed to use when deploying the database. In this design, the DB subnet group spans the private subnets in both Availability Zones. This is required for Multi-AZ placement and allows RDS to maintain the standby instance in a separate AZ.

The DB subnet group is therefore not an application workload by itself, but it is an essential supporting resource for the database design.

---

## Amazon S3

Amazon S3 is used as the document storage layer for NordLedger.

Its purpose in this architecture is to store generated invoice PDFs. This keeps binary document storage separate from the relational database. Instead of storing PDF files inside PostgreSQL, the application stores them as objects in S3 and can later return references or download links when needed.

This is a better fit than storing generated files in the database because S3 is designed for durable object storage and scales naturally for document retrieval.

In the NordLedger workflow, Lambda generates an invoice PDF and uploads it to the S3 bucket.

---

## Gateway VPC Endpoint for S3

The design includes a gateway VPC endpoint for Amazon S3.

This resource allows VPC-connected workloads to access S3 without routing that traffic through the public internet. In practice, this means that when Lambda is attached to the VPC and needs to upload invoice PDFs to S3, that access can occur through the VPC endpoint rather than through a NAT gateway.

This improves the design in two ways. First, it keeps S3 access more private and explicit. Second, it avoids using NAT for traffic that is specifically destined for S3.

For NordLedger, this is a clean design choice because PDF generation is a core backend workflow and S3 is a first-class application resource.

---

## Resource Interaction Flow

The main service interaction flow is:

**Frontend / client → Amazon API Gateway → AWS Lambda → Amazon RDS for PostgreSQL**

For invoice document generation, the flow is:

**AWS Lambda → Amazon S3**

This means that the frontend never communicates directly with the database or the storage bucket. Instead, Lambda acts as the application layer that mediates access to internal resources and enforces backend logic.