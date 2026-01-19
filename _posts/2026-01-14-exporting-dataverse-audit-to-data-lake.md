---
title: "Exporting Dataverse audit to Data Lake"
date: 2026-01-14T12:30:00+01:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
  - Microsoft Azure
tags:
  - Dataverse
---

Dataverse has very powerful [auditing](https://learn.microsoft.com/en-us/power-platform/admin/manage-dataverse-auditing), however, if you are running a larger system, you may quickly [run out of log storage](https://learn.microsoft.com/en-us/power-platform/admin/capacity-storage) which will then start [consuming your database storage](https://learn.microsoft.com/en-us/power-platform/admin/capacity-storage#example-storage-capacity-scenario-no-overage). The log storage is quite expensive (9.87EUR per GB per month) so let's look at an easy way to offload your audit logs.

<!-- more -->

There are already GUI tools to export the [Audit table](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/audit) - some available through [XrmToolbox](https://www.xrmtoolbox.com/) but we want this to be done automatically in the background without having to do manual cleanup. And we can achieve this via export to Data Lake Storage in Azure. While there is [already a guide for this](https://learn.microsoft.com/en-us/power-platform/admin/audit-data-azure-synapse-link) it requires you to deploy Azure Synapse Workspace and an Apache Spark pool which will incur additional costs but you can do it without all of that.

First, you need to decide on what you plan to use those audit logs for - if you have them just as a backup, or access them in a very infrequent way, you can safely offload the audit elsewhere. You can offload everything and then for example keep 1 year of audit in Dataverse for easy access, and over that in Data Lake for long-term retention. Remember that once you offload the audit, it will be in the [CSV format](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/azure-synapse-link-data-lake#view-your-data-in-azure-data-lake-storage-gen2) in the Data Lake, so you will need another tool (like Power BI or actual Azure Synapse Link) to search through the data easily. So let's get it running:

First, [create a Data Lake storage account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal) in Azure, preferrably in the same region as your Dataverse and make sure to enable [*Hierarchical Namespace*](https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-namespace) (you can follow [this](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/azure-synapse-link-data-lake#prerequisites) guide). Next, proceed with connecting the Data Lake to Dataverse, you can follow [these steps](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/azure-synapse-link-data-lake#connect-dataverse-to-azure-data-lake-storage-gen2), however you will notice, that there is no Auditing table available. That's fine, just select some other table (preferrably some table which you are not using like `adx_ads`), save it, and wait for it to complete.

Next, open [F12 Developer Tools](https://learn.microsoft.com/en-us/microsoft-edge/devtools/overview) and select the [Network](https://learn.microsoft.com/en-us/microsoft-edge/devtools/network/) tab. With those tools open, navigate to the Data Lake configuration, and find the GET request going to the *athenawebservice.\*.gateway.prod.island.powerapps.com*. From the GET request's body and headers, you need to populate the code below:

```javascript
const url = "<url>"; // https://athenawebservice.neu-il103.gateway.prod.island.powerapps.com/environment/2b780552-3247-473b-ba66-e3681799d66f/lakeprofile/39ee4c30-8487-48e6-b476-a55731f66171
const authorization = "<authorization_header_value>"; // Bearer ...
const id = "<id>"; // GUID
const name = "<name>"; // name
const organizationId = "<organization_id>"; // GUID
const organizationUrl = "<organization_url>"; // URL
const lakeId = "<lake_id>"; // GUID

await fetch(url, {
  "headers": {
    "accept": "*/*",
    "authorization": authorization,
    "cache-control": "no-cache",
    "content-type": "application/json",
  },
  "body": JSON.stringify({
    "Id": id,
    "Version": "1.0",
    "State": 1,
    "LastModified": "2023-11-20T22:10:17",
    "Name": name,
    "OrganizationId": organizationId,
    "OrganizationUrl": organizationUrl,
    "Entities": [
        {
            "Type": "audit",
            "EntitySource": "Dataverse",
            "AppendOnlyMode": false,
            "PartitionStrategy": "Month",
            "RecordCountPerBlock": 0,
            "Settings": {}
        }
    ],
    "DestinationType": 4,
    "DestinationKeyVaultUri": "dummy",
    "DestinationPrefix": "",
    "LakeId": lakeId,
    "RetryPolicy": {
        "MaxRetryCount": 12,
        "IntervalInSeconds": 5,
        "Backoff": 0
    },
    "Status": {
        "ExportStatus": "Success",
        "InitialSyncState": "Completed",
        "TotalNotifications": 0,
        "SuccessNotifications": 0,
        "FailureNotifications": 0,
        "LastExportDate": null,
        "LastModifiedOn": "2023-11-20T22:10:17",
        "MetadataState": "Created",
        "ForceRefreshState": "NotStarted",
        "LastForceRefreshRequestTime": null,
        "LastForceRefreshStartTime": null,
        "LastForceRefreshEndTime": null
    },
    "WriteDeleteLog": true,
    "CountFeature": false,
    "CreationTime": "2023-11-20T22:10:17",
    "ActivationTime": "2022-04-11T12:26:19",
    "UpdateTime": null,
    "DestinationSchemaName": "dbo",
    "NeedCopyAttachmentsToBlob": false,
    "NeedCopyFileTypeAttachmentsToBlob": false,
    "EnabledForJobs": true,
    "EnabledForIncrementalUpdate": false,
    "EnabledForDeltaLake": false,
    "EnabledForDlw": false,
    "IncrementalUpdateTimeInterval": 60,
    "SynapseSyncState": "NotStarted",
    "LinkedToFabric": false,
    "EnabledForFnOTablesBaseEnumSupport": false,
    "IsDeDuplicationJobsSubmitted": false,
    "LinkedFnOEnvironmentLastObservedValue": null,
    "ShouldSkipShortCutsDeletionInOLCFlow": false,
    "ProfilePauseResumeOperationsType": 8,
    "LinkedFnOEnvironmentCurrentAOSCount": 0,
    "LinkedFnOEnvironmentAdditionalAOSCount": 0
  }),
  "method": "PUT",
  "mode": "cors",
  "credentials": "include"
});

await fetch(`${url}/activate`, {
  "headers": {
    "accept": "*/*",
    "authorization": authorization,
    "cache-control": "no-cache",
    "content-type": "application/json",
  },
  "body": null,
  "method": "POST",
  "mode": "cors",
  "credentials": "include"
});
```

Once you do that, you can copy paste it to the console in the developer tools and execute. It will update the export profile and active it, and in a minute the audit log will begin to be exported into the Data Lake.

> **WARNING:** Remember, you are executing a code from the Internet, so always make sure it is going to do what you expect it to do.

Once the intial export finishes, you can then [configure the audit log retention](https://learn.microsoft.com/en-us/power-platform/admin/manage-dataverse-auditing#turn-on-auditing) to a lower time in Dataverse and also [trigger the audit deletion](https://learn.microsoft.com/en-us/power-platform/admin/manage-dataverse-auditing#delete-audit-logs) if you want to delete older logs immediatelly (more on that in another article).

And you are all set, audit is now persisted in much cheaper storage. I am kind of surprised that exporting audit to Data Lake directly without Azure Synapse Link is not supported, but at least it works this way.