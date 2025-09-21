---
title: GitHub Organization Management with Entra ID
date: 2025-09-21T14:00:00+02:00
author: Jan Hajek
categories:
  - Microsoft
  - Open Source
tags:
  - GitHub
  - Azure AD
  - Entra ID
  - SSO
---

We are continuously trying to release opensource software in NETWORG. One of the issue with doing so on GitHub however, is the management of users. Since we heavily rely on Azure DevOps internally, we are used to tight integration of Identity & Access Management. GitHub however offers this only for [enterprise plans](https://github.com/pricing).

<!-- more -->

# GitHub Enteprise pricing

NETWORG is a Microsoft Partner and we get some of our licenses from [Microsoft Partner program](https://learn.microsoft.com/en-us/partner-center/benefits/mpn-benefits-visual-studio) (Visual Studio Enterprise in this matter). Visual Studio Enterprise grants the user full access to Azure DevOps, but doesn't grant any benefits in regards to GitHub (yes, there is some separate SKU, but you don't get that). Additionally, a seat in Azure DevOps costs $6 per month per user, while with GitHub Enterprise, it is $21 per month per user.

I don't want to speculate on the topic GitHub vs Azure DevOps so I will leave it out on purpose.

# Why on earth do you need GitHub Enterprise when doing OSS?

Security and identity management. We streamlined our IAM into Entra ID. May it be for SSO enabled apps, [Bitwarden](https://hajekj.net/2023/09/18/entra-id-user-and-group-provisioning-with-bitwarden/) or other apps. I want to have a single place to manage access, and especially onboarding and offboarding users.

Besides, we use GitHub for Open Source projects, our customer project are still in Azure DevOps, and things are going to stay that way.

# You want security, you have to pay more!

This is not just limited to GitHub Enterprise, there are many software vendors who include SSO only in their Enterprise plans - which are literally unaffordable for small businesses. May it be [Twilio](https://www.twilio.com/en-us/editions), [Cloudflare](https://www.cloudflare.com/plans/) and many others.

One of the things I am really having a hard time wrapping my head around - everybody is boosting about how secure their platforms are, yet, making every user own another account (and setting additional credentials) and adding administative overhead (for onboarding and offboarding) probably doesn't count, because in the end of the day, it's on the shoulders of their customer, eg. us for example.

# Our approach and solution

Since we won't have SSO with GitHub without getting Enterprise, and the costs for that are not really justifiable for doing just OSS and giving some bits back to the community, we decided to at least handle user provisioning and deprovisioning and team mebership based on Entra information. This is where **[github-organization-management](https://github.com/NETWORG/github-organization-management)** comes in.

# GitHub Orgaization Management

We decided to utilize GitHub's rich [APIs for organization management](https://docs.github.com/en/rest/orgs/members?apiVersion=2022-11-28#create-an-organization-invitation) to handle invites, removals and team meberships and synchronize it with Entra ID. This is not a first of its kind project - Microsoft already made and opensourced something similar - their [Open Source Management Portal](https://github.com/microsoft/opensource-management-portal). However their solution is a little bit overkill for our use - it handles roles, repo management, compliance and much - many of the things you don't need when you are a small business.

Focusing on the basics we needed, it features the following:

* Invite users to GitHub organizations
* Remove disabled/deleted/out-of-scope users from GitHub organizations
* Maintain team memberships based on Entra ID group memberships
* Supports B2B guest accounts and their membership in groups
* Doesn't require GitHub Enterprise
* Doesn't interfere with external collaborators
* Doesn't interfere with direct assignments and teams not linked to Entra ID groups
* Supports multiple organizations against a single Entra ID tenant
* Exempt users (e.g. service accounts, admins) from organization removal (in case things go wrong)

Through a simple user interface, users are required to link their Entra ID account with their GitHub account by signing in to both (GitHub account ID is persisted as a [directory schema extension](https://learn.microsoft.com/en-us/graph/api/resources/extensionproperty?view=graph-rest-1.0) in Microsoft Graph), and then, based on the groups the person is member of, the access is calculated and applied - user is invited, and upon accepting invitation added and synchronized into GitHub Teams linked with Entra ID groups. When the account is disabled or deleted in Entra, the user will be removed from the organization (or when they loose access to the teams giving them the entitlement). GitHub Teams are linked based on an Entra Group ID provided in the team's description field, eg. `Entra: <group_id>`.

Currently, you have to manually trigger the sync process via an HTTP endpoint, but this will be soon moved to a worker.

We are currently running this project in [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/dotnet-overview).

The project is opensource and currently is still work in progress, but I just wanted to share the progress.