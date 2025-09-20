# On-Chain Leasing System 🏠

A decentralized rental contract system built on Stacks blockchain using Clarity smart contracts. This system enables property owners and tenants to create legally binding lease agreements with automatic payment enforcement and dispute resolution mechanisms.

## Overview

The On-Chain Leasing System revolutionizes traditional rental agreements by bringing transparency, automation, and security to the leasing process. Property owners can list their properties, set rental terms, and automatically collect payments, while tenants benefit from transparent agreements and secure deposit management.

## Key Features

### For Property Owners
- **Property Registration**: Register properties with detailed information and rental terms
- **Automated Rent Collection**: Automatic monthly rent collection from tenant deposits
- **Security Deposit Management**: Secure handling of security deposits with automatic refund mechanisms
- **Lease Agreement Creation**: Create standardized, transparent lease agreements
- **Payment History Tracking**: Complete payment history and lease status monitoring

### For Tenants
- **Transparent Agreements**: View all lease terms and conditions on-chain
- **Secure Payments**: Make rent payments through smart contracts with full transparency
- **Deposit Protection**: Security deposits held in escrow with automatic refund conditions
- **Payment Verification**: Proof of payment stored on blockchain
- **Dispute Resolution**: Built-in mechanisms for handling lease disputes

### Smart Contract Features
- **Automatic Payment Processing**: Monthly rent deducted automatically from tenant deposits
- **Late Payment Penalties**: Configurable late fees for overdue payments
- **Lease Termination Logic**: Automated lease termination and deposit refund processes
- **Emergency Pause**: Contract owner can pause operations in emergency situations
- **Multi-Property Support**: Single contract supports multiple properties and leases

## Technical Architecture

### Core Contracts

1. **Lease Management Contract**: Handles property registration, lease creation, and agreement management
2. **Payment Enforcement Contract**: Manages automatic payments, deposits, and financial transactions

### Key Data Structures

- **Properties**: Property details, owner information, and rental terms
- **Leases**: Active lease agreements with tenant and payment information
- **Payment Records**: Complete history of all rent payments and transactions
- **Security Deposits**: Escrow management for tenant security deposits

## Usage Flow

1. **Property Registration**: Owner registers property with rental terms
2. **Lease Application**: Tenant applies for lease and deposits security amount
3. **Lease Activation**: Owner approves lease, activating automatic payment schedule
4. **Monthly Payments**: Rent automatically deducted from tenant's deposit balance
5. **Lease Termination**: Either party can terminate lease with proper notice
6. **Deposit Refund**: Security deposit automatically refunded after lease termination

## Security Features

- **Access Control**: Function-level permissions for owners, tenants, and contract admin
- **Input Validation**: Comprehensive validation of all user inputs and parameters
- **State Management**: Proper lease state transitions and validation
- **Emergency Controls**: Pause functionality for emergency situations
- **Audit Trail**: Complete transaction history stored on-chain

## Getting Started

### Prerequisites
- Clarinet CLI installed
- Node.js and npm
- Stacks wallet for testing

### Installation
```bash
git clone <repository-url>
cd on-chain-lease
npm install
```

### Testing
```bash
clarinet check
npm test
```

### Deployment
```bash
clarinet deploy
```

## Contract Specifications

- **Language**: Clarity
- **Blockchain**: Stacks
- **Testing Framework**: Clarinet + Vitest
- **Code Style**: Clean, documented, and well-structured

## Legal Considerations

This system provides a technical framework for lease agreements but does not replace legal counsel. Users should ensure compliance with local rental laws and regulations. The smart contracts provide transparency and automation but legal enforceability may vary by jurisdiction.

## Contributing

We welcome contributions to improve the On-Chain Leasing System. Please ensure all code follows our style guidelines and includes appropriate tests.

## License

This project is open source and available under standard licensing terms.

---

*Built with ❤️ using Clarity and the Stacks blockchain*
