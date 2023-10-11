---
title: Dealing with Outlook.com spam part 2
date: 2023-10-11T15:30:00+02:00
author: Jan Hajek
categories:
  - Other
tags:
  - Spam
  - Outlook.com
  - E-mail
  - OpenAI
  - Logic Apps
---

[Continuing](https://hajekj.net/2023/10/10/dealing-with-outlook-com-spam/) my fight against spam in Outlook.com, I decided to employ [Azure OpenAI](https://azure.microsoft.com/en-us/products/ai-services/openai-service) to deal with false-positives (or legit) in the junk folder. We are going to look at how I did that.

<!-- more -->

> Before I go any further, false-positive, in the context of this article means that the message ended up in Junk mail folder, because the sender wasn't on my whitelist (either in contacts or safe-senders list) due to the settings I previously configured. So we are trying to identify the legit messages and senders which should be on the safe-list, but aren't there yet.

Since the last post, my inbox got 0 spam messages, everything I would consider junk ended up in the Junk folder. However, some of the messages ended up in the junk folder because I don't have the sender in my contacts or safe-senders list, and I don't want to check my Junk mail folder every day. Considering [Microsoft](https://blogs.microsoft.com/blog/2023/09/21/announcing-microsoft-copilot-your-everyday-ai-companion/) (and almost everyone in the tech sector) is crazy about AI and putting it everywhere at the expense of other things (pun intended), I thought, let's try to use OpenAI - GPT-4 model and see if it can further help out with Junk classification.

> If you don't have access to Azure OpenAI yet, you can request it [here](https://go.microsoft.com/fwlink/?linkid=2222006&clcid=0x409). Alternatively, you can make use of [OpenAI API](https://platform.openai.com/docs/api-reference/introduction), which doesn't require any specific access.

> You can also achieve the same thing in Power Automate, however you will need a Premium license which is unavailable for consumer accounts so you won't be able to call the OpenAI API. I suppose there could be some way around that, but I am not going to go into it in this article.

You can start by [creating a Logic App](https://learn.microsoft.com/en-us/azure/logic-apps/quickstart-create-example-consumption-workflow), you can go with Consumption which will be much cheaper in this case or also create a [Standard](https://learn.microsoft.com/en-us/azure/logic-apps/create-single-tenant-workflows-azure-portal) one.

Once the Logic App is created, you have to choose the trigger. You can either go with a [scheduled trigger](https://learn.microsoft.com/en-us/azure/logic-apps/concepts-schedule-automated-recurring-tasks-workflows) which can run say.. every 15 minutes or [When a new email arrives](https://learn.microsoft.com/en-us/connectors/outlook/#when-a-new-email-arrives-(v2)) trigger. I went with the first one, because I prefer to process multiple messages at once and having the possibility to throttle the run in case the mailbox is flooded with spam (this is important for cost control).

Next, we retrieve all undread emails via [Get emails](https://learn.microsoft.com/en-us/connectors/outlook/#get-emails-(v2)) action from the Junk folder. To prevent message flood, we only retrieve top 10 messages (set is higher or lower as needed).

Then, we will iterate through each email we retrieved in the action above via [For each](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-control-flow-loops?tabs=consumption#for-each) and assemble the request. I used multiple [Compose](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-perform-data-operations?tabs=consumption#compose-action) actions to assemble the body of the email and the request. The body has to be shortened to match the maximum amount of tokens which you can send to the API. In my case, I chose the [32k model](https://techcommunity.microsoft.com/t5/azure-ai-services-blog/working-with-gpt-4-and-chatgpt-models-on-azure-preview/ba-p/3773595) which means that I need to shorten the message to 32,000 characters. This is done via the following expression:

```
substring(
	string(item()?['Body']),
	0,
	if(
		greater(
			length(
				string(item()?['Body'])
			),
			32000
		),
		32000,
		length(string(item()?['Body']))
	)
)
```

Next, we assemble the email. I chose to provide the subject, body and sender address:

```json
{
  "body": "@{outputs('EmailBody')}",
  "from": "@{items('ForEach-Email')?['From']}",
  "subject": "@{items('ForEach-Email')?['Subject']}"
}
```

Next, we need to send the request to the [Azure OpenAI API](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference). This is a *POST* request to `https://<your-instance>.openai.azure.com/openai/deployments/<your-deployment>/chat/completions?api-version=2023-07-01-preview` with a header `Api-Key` containing the value of your key. The body will be the following:

```json
{
  "frequency_penalty": 0,
  "max_tokens": 10,
  "messages": [
    {
      "content": "You are e-mail spam filter. You will receive sender of a message, its subject and body. Based on this, you will reply with just a number, which corresponds to the confidence of the message being spam.",
      "role": "system"
    },
    {
      "content": "@{outputs('Email')}",
      "role": "user"
    }
  ],
  "presence_penalty": 0,
  "stream": false,
  "temperature": 0.7,
  "top_p": 0.95
}
```

You can of course play with the system prompt and other variables and set it to whatever fits you the best. You can also provide it with examples and so on.

As a response, you will receive something like this:

```json
{
  "id": "chatcmpl-88SYGSryVZQPr94CXFNo6Iu47qNKh",
  "object": "chat.completion",
  "created": 1697027068,
  "model": "gpt-4-32k",
  "prompt_filter_results": [
    {
      "prompt_index": 0,
      "content_filter_results": {...}
    }
  ],
  "choices": [
    {
      "index": 0,
      "finish_reason": "stop",
      "message": {
        "role": "assistant",
        "content": "100"
      },
      "content_filter_results": {...}
    }
  ],
  "usage": {
    "completion_tokens": 1,
    "prompt_tokens": 6303,
    "total_tokens": 6304
  }
}
```

And the result will be the `content` value which should contain a number between 0 and 100. Since `choices` is an array, you should pick the first element of it (you can use `first()` in expressions) and then get the value easily.

Based on the value retrieved above, you can decide what to do with the message - either store the summary somewhere and send yourself a daily digest of low confidence messages, move the message with low spam confidence to inbox etc. Up to you. Just make sure to mark the message as read when you are done, so it won't be processed again.

So far, this has processed 57 messages since yesterday in my Junk e-mail, and out of those 57 messages, OpenAI marked:

* 5 message as legit (0), and they actually were legit
* 1 message as legit (0), while it was spam - no subject, sent from Gmail and body saying *Hi*
* 1 message as legit (0.1), while it was spam - $10.5M offer for whatever
* 3 messages as legit (10), while they were spam - 2 emails about AI investing in times of war and 1 OSS security code scan scam

So it's not exactly perfect, but it can handle the basic filtering (which Microsoft kind of fails in right now) and save some of my time. Right now, I am running this in monitor mode, eg. it reports all processed messages to an Excel spreadsheet in OneDrive, and based on the results in a week or two, I am going to adjust the system prompt and eventually provide some examples to make the classification better. Based on that, I might have this "AI" decide about which mails from my Junk folder should go back to my inbox and eventually manage my safe senders list in the future. Have fun!