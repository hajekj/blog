---
title: Dealing with Outlook.com spam
date: 2023-10-10T09:30:00+02:00
author: Jan Hajek
categories:
  - Other
tags:
  - Spam
  - Outlook.com
  - E-mail
---

For the past couple of months, I have been really frustrated by the amount of spam appearing in my Inbox folder in my personal e-mail provided by [Outlook.com](https://outlook.com) (previously Hotmail or MSN). I have been using Outlook.com since 2007 and I have never had such a huge amount of spam bypass the filter. I am also a M365 Family subscriber. Nowadays, at least 5 messages make it through the spam filter and appear in my inbox.

<!-- more -->

# I am not the only one
There are plenty people complaining about this situation on Reddit ([1](https://www.reddit.com/r/Outlook/comments/16z6233/are_there_any_outlookcom_engineers_here_why_are/), [2](https://www.reddit.com/r/Outlook/comments/16g68nb/why_am_i_getting_so_many_junk_emails_now/), [3](https://www.reddit.com/r/Outlook/comments/16lu7g7/the_spam_is_unbearable/), [4](https://www.reddit.com/r/Outlook/comments/16mqmvc/has_the_spam_filter_on_outlookcom_been_completely/), [5](https://www.reddit.com/r/Outlook/comments/16mqmvc/has_the_spam_filter_on_outlookcom_been_completely/), [6](https://www.reddit.com/r/Outlook/comments/16wgdch/spam_emails_outlookcom/)), Microsoft Answers ([1](https://answers.microsoft.com/en-us/outlook_com/forum/all/receiving-a-massive-amount-of-spam-in-my-inbox/92c3a6e3-52bb-4ad8-868b-51e8837c1742), just Google for more yourself) and many more. The answers from Microsoft are really "helpful". I had a bunch of tickets open with Microsoft Support (#1056895825, #1056728569, ...), all of which resulted in the case being closed and being told "it's a known issue and we are working on it" and also "keep reporting the messages". Well, it's been 6+ months and nothing has changed (perhaps stop pushing Copilot everywhere and put more people on this issue?).

Recently, I [complained on Twitter](https://twitter.com/hajekj/status/1710542981294436784) and got another [very helpful response](https://support.microsoft.com/en-us/office/10-tips-on-how-to-help-reduce-spam-55f756e8-688b-41c3-a086-8f68ccc592f6) - most of this doesn't even apply to Outlook.com service.

# Why does this seem to happen?
...and why it doesn't happen with business Microsoft 365 accounts? Well, first of all, M365 for companies is using Exchange Online Protection (EOP) which seems to deal with spam really well, while M365 for consumer is using, I guess, Outlook Live Protection (OLP) which seem to be two very different systems. I suppose the issue with using EOP for consumer accounts would be, that it wasn't built for filtering spam of milions of user accounts and that consumer protections are not interoperable with business ones.

I have been trying to figure our why the e-mails bypass the filter and so far, I managed to find out the following:

Most e-mails which bypass the rules are sent from compromised accounts and domains (just ban them from the system, use [ZAP](https://learn.microsoft.com/en-us/microsoft-365/security/office-365-security/zero-hour-auto-purge?view=o365-worldwide) on all send messages within last X minutes and wait for their admin to reach out?).

Those messages have valid SPF and DKIM (a lot of legit e-mail server admins are behind with this, [Google will require it](https://www.bleepingcomputer.com/news/security/google-to-bolster-phishing-and-malware-delivery-defenses-in-2024/) soon anyways).

And the content is just remote pictures linking to websites. When you click the link, the [Safelinks](https://support.microsoft.com/en-us/office/advanced-outlook-com-security-for-microsoft-365-subscribers-882d2243-eab9-4545-a58a-b36fee4a46e2) feature should prevent you from continuing since it is usually phishing or scam, but it just redirects you. Seems like the verification and checks on the links could use some care too. Especially when e-mail and its content has been reported multiple times as spam by various users.

# What can you do?

Besides waiting for Microsoft to do something about this, which I am not really sure whether or when will it happen, there are few things you can configure yourself.

The things which worked for me are following:

1. Navigate to [Junk e-mail settings](https://outlook.live.com/mail/0/options/mail/junkEmail)
1. Make sure your safe sender list is up to date and you know all the addresses there
1. Scroll down to *Filters* and check both *Only trust email from addresses in my safe senders and domains list and safe mailing lists* and *Block attachments, pictures, and links from anyone not in my Safe senders and domains list*
1. **the steps below are for advanced users, if you are non-technical, ask someone to help you out**
1. Before saving, open developer tools in your browser (F12) and navigate to *Network* tab
1. Save the settings
1. In the Network tab, you will see a request containing `action=SetMailboxJunkEmailConfiguration`, right click it and select [*Edit and resend*](https://learn.microsoft.com/en-us/microsoft-edge/devtools-guide-chromium/network-console/network-console-tool#starting-from-the-network-tool)
1. Find a property in the body called `ContactsTrusted` and set its value to `true`
1. Resend the request

This will effectively allow only whitelisted senders (contacts and safe list members) to appear in your inbox. It is not the ideal solution, since you should at least once a week check your junk folder for any false positives and if so, add them to your contacts or safe list, but it's a much better solution than having to deal with loads of annoying spam messages.

# Conclusion

I would like to conclude this article with one statement: I love Outlook.com, I am a paying user, but the level of support and communication Microsoft is providing regarding this issue is completely unacceptable. The [status page](https://portal.office.com/ServiceStatus) says nothing is wrong, there is no support article publicly available regarding the spam issue and the biggest issue is that standard, non-technical users, who are much more vulnerable to falling for phishing are facing this as well. I am sure that Microsoft is aware and working to resolve this as fast as they can, but they should at least communicate this to their users like they do with other services.

> Continues with [part 2](https://hajekj.net/2023/10/11/dealing-with-outlook-com-spam-pt2/) where we use Logic Apps and OpenAI to classify the Junk mail and detect legit messages.