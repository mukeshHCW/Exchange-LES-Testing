# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository contains documentation for Last Exchange Server. Please refer link: https://learn.microsoft.com/en-us/exchange/hybrid-deployment/enable-exchange-attributes-cloud-management to understand features already available generally to customers. 

Now, the goal of this repository to add documentation of features that are pending to be released to customers. 
We are targetting Enable Writeback feature for LES enabled mailboxes. Go through documents containing Enable Writeback in the name of the file, to get context of how to enable the feature. 

After getting the full understanding, go through the target document i.e *LES Test Scenarios.docx** and write the section titled: "Phase 2: Test Scenarios for LES Recipient Management with WriteBack"
You need to add follwoign two subsections: 
a) detailed steps to enable the Writeback feature.
b) After enabling the test scenarios required to evaluate the feature.

For review, put this section in Writeback.md file with proper formatting. 

## Key Files
For Context: 
- **Enable Writeback Script.ps1**: Example PowerShell script for configuring Exchange Online Attribute Writeback
- **Enable Writeback - doc 1.docx** and **Enable Writeback - doc 2.docx**: Documentation for the writeback setup process
- **Last Exchange Server PRD.docx**: Product Requirements Document for the Last Exchange Server project


Document to be edited (Target doc)
- **LES Test Scenarios.docx**: Test scenarios for validating the writeback functionality



## Important Notes

- You DON'T need to run the scripts or command. Focus on documentation. I need help in documentation of Enabling the feature and Testing the feature.

## Key Assumptions for Documentation

- **Exchange Hybrid is already enabled** - No need to document Exchange Hybrid setup
- **AD Schema is already extended for Exchange** - No need for `Setup.exe /PrepareSchema` steps
- **Connect Sync is already installed** - Need to document installation/configuration of Cloud Sync (required for writeback)
- **When in doubt**, refer to Microsoft Learn documentation:
  - [Exchange hybrid writeback with Cloud Sync](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/exchange-hybrid)
  - [Cloud-managed Exchange attributes](https://learn.microsoft.com/en-us/exchange/hybrid-deployment/enable-exchange-attributes-cloud-management)
  - [Cloud Sync Prerequisites](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/how-to-prerequisites)
  - [Provisioning Agent Installation](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/how-to-install)

## LES Attributes Written Back to On-Premises AD

Source: https://learn.microsoft.com/en-us/exchange/hybrid-deployment/enable-exchange-attributes-cloud-management#identity-exchange-attributes-and-writeback

| AD Attribute | Exchange Cmdlet Parameter |
|--------------|---------------------------|
| extensionAttribute1-15 | CustomAttribute1-15 |
| msExchExtensionCustomAttribute1-5 | ExtensionCustomAttribute1-5 |
| msExchRecipientDisplayType | Type |
| msExchRecipientTypeDetails | Type |
| proxyAddresses | EmailAddresses, WindowsEmailAddress |