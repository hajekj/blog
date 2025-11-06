---
title: "Calling TDS endpoint from plugins"
date: 2025-11-06T11:45:00+01:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
tags:
  - Dataverse
---

In Dataverse, you can use the [Tabular Data Stream (TDS) endpoint](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/dataverse-sql-query) to perform advanced queries over your data. It then allows you to talk to Dataverse as if it was a SQL server (read-only operations). In this post, we're going to look at how to do this from plugin in a more native way.

<!-- more -->

# Why would you want to use TDS in your plugin?

For example to perform advanced [roll-up](https://www.inogic.com/blog/2025/02/retrieving-dynamics-365-data-using-sql-in-plugin-tds-endpoint/) like operations - to calculate things in real-time or handle the calculation more efficiently - because FetchXML is limited compared to SQL.

For example, you can perform a query like this:

```sql
SELECT contact = (SELECT COUNT(lastname) as count FROM contact), account = (SELECT COUNT(name) as count FROM account)
```

Which will return a real-time count of the records (yes, even if it's above 5,000), do multiple nested `GROUP BY` statements and much more.

# Your options

## Connecting directly via SQL

Probably the easiest option is to connect to the SQL directly from plugin which has been described [here](https://www.inogic.com/blog/2025/02/retrieving-dynamics-365-data-using-sql-in-plugin-tds-endpoint/) or [here](https://temmyraharjo.wordpress.com/2024/10/12/dataverse-retrieve-data-using-tds-endpoint-in-plugin/) for example. The issue with the code here, is that you also need to create an app registration and the query will then be authorized by the service principal's permissions, rather than the user's, which potentially introduces security risks. And there is no way to retrieve user's token in the plugin to perform proper impersonation.

## Using `ExecutePowerBISql` request from within plugin

Previously "documented" by Mark Carrington ([here](https://markcarrington.dev/2020/08/04/msdyn365-internals-t-sql-endpoint/) and [here](https://markcarrington.dev/2020/05/19/cds-t-sql-endpoint-pt-7-extensibility/)), you can make use of the `ExecutePowerBISql` message which allows you to pass in SQL query and retrieve the response. This message can be executed only through the `IOrganizationService` interface (calling it via `Xrm.WebApi.online.execute` won't work) and it can be called from within a plugin which wasn't previously possible (we created our own proxy in Azure Functions to be able to call TDS from client/server/Power Automate).

So from within your plugin, you can call code like this:

```csharp
var request = new OrganizationRequest("ExecutePowerBISql")
{
    Parameters = new ParameterCollection
    {
        ["QueryText"] = "select * from account"
        // ["NameMappingOptions"] = SqlNameMappingOptions.LogicalName  // Optional: https://learn.microsoft.com/en-us/dotnet/api/microsoft.xrm.sdk.sqlnamemappingoptions?view=dataverse-sdk-latest
        // ["QueryParameters"] =  new ParameterCollection // Optional: https://learn.microsoft.com/en-us/dotnet/api/microsoft.xrm.sdk.tdspowerbisqlrequest?view=dataverse-sdk-latest
        // {
        //     { "@parameter1", "Value1" },
        //     { "@parameter2", 123 },
        // }
    }
};
var response = localPluginContext.PluginUserService.Execute(request);
var dataset = (System.Data.DataSet)response.Results["Records"];
// ...
```

You don't need to perform any other authentication or create an app registration because it will use the calling user for authorization automatically, so it is much more convenient.

This however **only works in a synchronous plugin**, if you set it to run as asynchronous, you will end up with a missing dependency exception:

```
System.ServiceModel.FaultException`1[Microsoft.Xrm.Sdk.OrganizationServiceFault]: An unexpected error occurred. (Fault Detail is equal to Exception details: 
ErrorCode: 0x80040216
Message: An unexpected error occurred.
TimeStamp: 2025-11-05T08:02:47.0000000Z
OriginalException: System.ServiceModel.FaultException`1[Microsoft.Xrm.Sdk.OrganizationServiceFault]: An unexpected error occurred. (Fault Detail is equal to Exception details: 
ErrorCode: 0x80040216
Message: An unexpected error occurred.
TimeStamp: 2025-11-05T08:02:47.6476346Z
--
Exception details: 
ErrorCode: 0x80040216
Message: System.IO.FileNotFoundException: Could not load file or assembly 'Microsoft.SqlServer.TransactSql.ScriptDom, Version=16.1.0.0, Culture=neutral, PublicKeyToken=[REDACTED] or one of its dependencies. The system cannot find the file specified.
at Microsoft.Crm.ObjectModel.PSqlService.GetSqlQueryEvaluationVisitor(String queryText, IExecutionContext executionContext, PSqlDatabaseContext pSqlDatabaseContext)
at Microsoft.Crm.ObjectModel.PSqlService.GetSqlExecutor(IExecutionContext executionContext, String queryText, PSqlDatabaseContext pSqlDatabaseContext...).
```

### Calling from client

If you want to call this from the client (eg. client-script or PCF) the easiest option is to wrap the above into a [Custom API](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/custom-api). This will also allow you to call it from Power Automate.

Alternatively, you can call the organization service web proxy through JavaScript (`ExecutePowerBISql` is not available through OData endpoints unfortunately, so you have to use the SOAP call below):

```javascript
async function executePowerBISql(queryText) {
    // You can provide additional parameters as shown above
    const soapEnvelope = `
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
      <s:Body>
        <Execute xmlns="http://schemas.microsoft.com/xrm/2011/Contracts/Services">
          <request i:type="a:OrganizationRequest" xmlns:a="http://schemas.microsoft.com/xrm/2011/Contracts" xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
            <a:Parameters xmlns:b="http://schemas.datacontract.org/2004/07/System.Collections.Generic">
              <a:KeyValuePairOfstringanyType>
                <b:key>QueryText</b:key>
                <b:value i:type="c:string" xmlns:c="http://www.w3.org/2001/XMLSchema">${queryText}</b:value>
              </a:KeyValuePairOfstringanyType>
            </a:Parameters>
            <a:RequestName>ExecutePowerBISql</a:RequestName>
          </request>
        </Execute>
      </s:Body>
    </s:Envelope>`;

    const response = await fetch("/XRMServices/2011/Organization.svc/web", {
        method: "POST",
        headers: {
            "Content-Type": "text/xml; charset=utf-8",
            "SOAPAction": "http://schemas.microsoft.com/xrm/2011/Contracts/Services/IOrganizationService/Execute"
        },
        body: soapEnvelope
    });

    const responseText = await response.text();
    return responseText;
}

const result = executePowerBISql("select * from account");
// parse result...
```

# Wrap up

You can see that calling TDS is possible from both client and plugin without any additional authentication requirements. While it's probably not officially supported, it is quite a nice way to quickly perform advanced queries. I am not really happy that these things are not exposed to Power Platform developers because it just creates more complications when trying to do something a little more advanced (but it is what it is).