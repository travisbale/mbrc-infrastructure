# mbrc-infrastructure

Infrastructure repository for deploying and managing the Manitoba Ryder Cup web application on AWS.

This setup is optimized for a small, single server environment with an emphasis on automation, portability, and security.

## Overview

This repository manages:

- Dockerized application stack (nginx, certbot, postgres database)
- TLS certificates via Certbot and Route 53 DNS-01
- Systemd based scheduling for TLS renewal

## Requirements

- Amazon EC2 Instance
- An IAM Role with appropriate permissions attached to the EC2 instance
- Route 53 hosted zone for your domain
- AWS Secrets Manager configured for JWT key storage
