# Client MVP

## Overview

This client MVP is a lightweight demo of the NordLedger platform. It is intended to show the core user flow and the underlying cloud architecture rather than a full production-ready accounting product.

## Architecture

The MVP follows a simple AWS-based design, as illustrated i Figure 1.

- **CloudFront** serves the client-facing web application
- **Amazon Cognito** handles user authentication
- **API Gateway** exposes backend endpoints
- **AWS Lambda** processes client and invoice requests
- **Amazon RDS PostgreSQL** stores customer and invoice data
- **Amazon S3** stores generated invoice PDFs

<p align="center">
  <img src="figures/nordledger-client-mvp.svg" alt="NordLedger Client MVP">
  <br>
  <em>Figure 1: Design concept for a client MVP demo.</em>
</p>

## User Flow

The demo focuses on a small set of actions:

- Sign in to the NordLedger client portal
- Register a new customer
- Register a new invoice
- Generate and store invoice PDFs
- View invoice status and download invoice PDFs