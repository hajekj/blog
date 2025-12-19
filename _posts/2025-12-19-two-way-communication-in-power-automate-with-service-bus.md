---
title: "Two way communication in Power Automate with Service Bus"
date: 2025-12-19T17:00:00+01:00
author: Jan Hajek
categories:
  - Microsoft
  - Microsoft Power Platform
  - Microsoft Azure
tags:
  - Power Automate
  - Service Bus
---

When we need to communicate with on-premise environment, we usually utilize Service Bus. Up until now, most of the messages have been fire and forget, however recently, we had a situation where we needed to perform two way communication (basically request and response) to basically perform some calculation on top of on-prem data and return the data.

<!-- more -->

There are actually multiple solutions to this problem - we could go with [on-premises data gateway](https://learn.microsoft.com/en-us/data-integration/gateway/service-gateway-onprem) (which would most-likely require running a web server at customer's environment - and handling auth etc.), we could go with [Azure Relay](https://learn.microsoft.com/en-us/azure/azure-relay/relay-what-is-it) (but that requires calling it via HTTP from Power Automate, and it's Service Bus behind the scenes anyways), so we decided to go with [Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/).

Service Bus supports [sessions](https://learn.microsoft.com/en-us/azure/service-bus-messaging/message-sessions) which can be used for implementing a [request and response pattern](https://learn.microsoft.com/en-us/azure/service-bus-messaging/message-sessions#request-response-pattern).

The implementation is really simple. Everything starts when a Power Automate gets triggered with some data payload ([from frontend](https://hajekj.net/2025/05/08/dynamically-executing-power-automate-flows-from-client/) in our case). Next, we generate the session's ID by using expression [`guid()`](https://learn.microsoft.com/en-us/azure/logic-apps/expression-functions-reference#guid) - we persist it in a variable, because we will also need it later.

In Service Bus, we [create two topics](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quickstart-topics-subscriptions-portal#create-a-topic-using-the-azure-portal) - `request` with on-premise [subscriber](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quickstart-topics-subscriptions-portal#create-subscriptions-to-the-topic) and `response` with Power Automate [subscriber](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-quickstart-topics-subscriptions-portal#create-subscriptions-to-the-topic) (make sure to enable sessions).

Next we [send the message to the queue/topic](https://learn.microsoft.com/en-us/connectors/servicebus/#send-message) and fill *Session Id* with the ID generated earlier. We also provide the message's payload and any other things we need. This will send the message.

You then have a simple listener created via [`CreateProcessor`](https://learn.microsoft.com/en-us/dotnet/api/azure.messaging.servicebus.servicebusclient.createprocessor?view=azure-dotnet):

```csharp
public async Task DoWork(CancellationToken stoppingToken)
{
    _serviceBusProcessor = _serviceBusClient.CreateProcessor("<topic>", "<subscription>", new ServiceBusProcessorOptions
    {
        AutoCompleteMessages = true,
        MaxConcurrentCalls = 1,
        MaxAutoLockRenewalDuration = TimeSpan.FromMinutes(1)
    });
    _serviceBusProcessor.ProcessMessageAsync += MessageHandler;
    _serviceBusProcessor.ProcessErrorAsync += ErrorHandler;

    await _serviceBusProcessor.StartProcessingAsync(stoppingToken);

    while (!stoppingToken.IsCancellationRequested)
    {
        await Task.Delay(10000, stoppingToken);
    }
}
```

And in the `MessageHandler`:

```csharp
private async Task MessageHandler(ProcessMessageEventArgs args)
{
    var sessionId = args.Message.SessionId;
    var message = args.Message.Body.ToObjectFromJson<Message>();

    try
    {
        // ... do your processing
        await _serviceBusSender.SendMessageAsync(new ServiceBusMessage
        {
            SessionId = sessionId,
            ReplyToSessionId = sessionId,
            Body = BinaryData.FromObjectAsJson(new Message
            {
                // Your response data...
            }),
        });
        await args.CompleteMessageAsync(args.Message);
    }
    // You should do proper error handling...
    catch (Exception ex)
    {
        await args.DeadLetterMessageAsync(args.Message, ex.Message);
    }

}
```

Next in Power Automate, you will add a trigger into the flow's body (yes, that's right, you can use triggers mid-flow). In this case, we use [*When a message is received in a topic subscription (peek-lock)*](https://learn.microsoft.com/en-us/connectors/servicebus/#when-a-message-is-received-in-a-topic-subscription-(peek-lock)) trigger. The important thing is to provide the *Session id* parameter, so the flow will get triggered only on the reply to the initial message. When you receive the message, make sure to [complete the message](https://learn.microsoft.com/en-us/connectors/servicebus/#complete-the-message-in-a-queue) since the trigger is only peek-lock (the [auto-complete](https://learn.microsoft.com/en-us/connectors/servicebus/#when-a-message-is-received-in-a-topic-subscription-(auto-complete)) doesn't support sessions).

This way, the flow pauses and just resumes running when a response arrives and thanks to it, you don't need to manually store flow's state and restore it.

If you are using HTTP Request trigger / Response action (or a connector based on these), remember the maximum execution time is [2 minutes](https://learn.microsoft.com/en-us/power-automate/limits-and-config#timeout), so if the execution time is longer, make sure to enable the [asynchronous response pattern](https://learn.microsoft.com/en-us/power-automate/guidance/coding-guidelines/asychronous-flow-pattern) and properly consume it on the client.