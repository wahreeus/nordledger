# Network Design

## Overview

The network is deployed in a **single VPC** spanning **two Availability Zones** (AZs). 

Each AZ contains:

- **A public subnet**
- **A private subnet**
- **A NAT gateway located in the public subnet**
- **A private route table in the private subnet**

The VPC also includes:

- **An internet gateway**
- **A shared public route table**

This design places internet-facing resources in the public subnets, while internal workloads run in the private subnets. Private subnets do not receive direct inbound internet access, but they can initiate outbound internet connectivity through the NAT gateways. I visual representation of the network setup is presented below.

<p align="center">
  <img src="diagrams/network.svg" alt="Network diagram">
</p>

---

## VPC Configuration

| Component | Value |
|---|---|
| VPC Name | `nordledger-shared-vpc` |
| CIDR Block | `10.0.0.0/20` |
| DNS Support | Enabled |
| DNS Hostnames | Enabled |

The VPC uses the private address range `10.0.0.0/20`, which provides room for subnet growth while keeping the design compact and easy to understand.

---

## Availability Zones and Subnets

The network spans two Availability Zones for better resilience in case of AZ failure.

### Availability Zone A

| Subnet | Role | CIDR | Notes |
|---|---|---|---|
| `public_a` | Public | `10.1.1.0/24` | Hosts NAT Gateway A and other internet-facing resources |
| `private_a` | Private | `10.1.2.0/24` | Hosts internal workloads without direct public IPs |

### Availability Zone B

| Subnet | Role | CIDR | Notes |
|---|---|---|---|
| `public_b` | Public | `10.1.3.0/24` | Hosts NAT Gateway B and other internet-facing resources |
| `private_b` | Private | `10.1.4.0/24` | Hosts internal workloads without direct public IPs |


---

## Internet Connectivity

An **Internet Gateway (IGW)** is attached to the VPC.

The IGW allows resources in public subnets to communicate with the internet. The two public subnets share a single public route table with the following route:

- `0.0.0.0/0 -> Internet Gateway`

This means resources in public subnets can reach the internet directly.

---

## NAT Gateway Design

Each public subnet contains a dedicated NAT Gateway:

| NAT Gateway | Subnet | AZ | Elastic IP |
|---|---|---|---|
| NAT Gateway A | `public_a` | AZ A | Yes |
| NAT Gateway B | `public_b` | AZ B | Yes |

Each NAT Gateway is assigned its own Elastic IP, allowing private workloads to initiate outbound internet connections without being directly reachable from the internet. Using one NAT gateway per AZ improves resilience and avoids cross-AZ dependency for outbound traffic.

---

## Route Table Design

### Public Route Table

A single public route table is used for both public subnets.

**Route:**

- `0.0.0.0/0 -> Internet Gateway`

**Associations:**

- `public_a`
- `public_b`

### Private Route Tables

Each private subnet has its own route table.

#### Private Route Table A

**Associated subnet:** `private_a`

**Route:**

- `0.0.0.0/0 -> NAT Gateway A`

#### Private Route Table B

**Associated subnet:** `private_b`

**Route:**

- `0.0.0.0/0 -> NAT Gateway B`

Each private subnet sends outbound internet-bound traffic to the NAT Gateway in the same Availability Zone.

