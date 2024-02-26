---
title: Searching for a lost MacBook
date: 2024-02-25T21:32:53+02:00
author: Jan Hajek
categories:
  - Apple
  - Open Source
tags:
  - Python
  - Find My
---

This is going to be a very unusual post for this blog, but I found this a very interesting topic which no one has written about yet. And I also believe it may be very helpful to others, so let's get on with it!

One very close person to me (привет Вова!) told me on Friday (16th February 2024), that their MacBook has been stolen in Hamburk a day before. Luckily, it had the Find My and Offline Find (more about both later) enabled, and they managed to track it all the way to Berlin, into a 9 story hotel/hostel. They contacted the police, and the police managed to get into the hostel on Friday evening. They even obtained the details of the person who probably took the MacBook from Hamburk and brought it to Berlin (I will avoid discussing any personal information since that could just [cause problems](https://www.lupa.cz/aktuality/muz-ktery-si-sam-nasel-ukradeny-macbook-nepravomocne-prohral-dalsi-soud/) - it's in Czech, use translator if you wanna get to know the story), they likely "searched" the room he stayed in but didn't find anything.

Me and my friend headed to Berlin on Friday evening to search for it. Unfortunately, we didn't find anything. But through Find My, the MacBook was still broadcasting its location via Offline Find.

# The story of Find My and why it's both great and stupid
Personally I believe that [Apple's Find My](https://www.apple.com/icloud/find-my/) is one of the greatest inventions. You can easily track both online and offline devices, and in some cases (like AirTags or AirPods) even locate them via [Find Nearby](https://support.apple.com/en-us/109021). Unfortunately, this doesn't work for MacBooks.

## Offline Find
The greatest feature of Find My is, that your device can be located even when it is offline, using [Offline Find](https://support.apple.com/en-gb/guide/security/sece994d0126/web) (OF). It works in a way, that when your device looses internet connection, it will start broadcasting it's temporary public key (more on that later), which is then picked up by other devices which have OF enabled and they send their location along with the device information to Apple's servers. This effectively makes Apple devices an amazing tracking network. And it's also anonymous, and secure.

You can learn more about how OF works from [Apple docs](https://support.apple.com/en-gb/guide/security/sec6cbc80fd0/web), but to shortly explain it (it works different for devices vs AirTags or trackable accessories, and I will just focus on the devices - MacBooks here): A device generates its private and public key on P224 curve, a shared secret, stores it as encrypted file in iCloud (more on that later as well), and from this initial key derives a new key-pair every 15 minutes and broadcasts it over Bluetooth Low Energy (BLE). This makes the devices impossible to track from longer periods of time, unless you know the private key and the shared secret.

The derived public key is then broadcasted every 2 seconds or so, so other devices can pick it up, encrypt their location information with the public key, and upload it to iCloud, so your other device can then open it (this works only for Find My in your devices, not on the web as far as I know). And not even Apple can read these information.

## Why is it stupid?
So far, everything about this sounds great, anonymously tracking devices, so you can see where they are, privacy preserved (there are [some](https://blog.cryptographyengineering.com/2019/06/05/how-does-apple-privately-find-your-offline-devices/) [discussions](https://www.theregister.com/2021/05/12/apples_find_network/) about improving this, but whatever). The stupid thing is, that Apple gives you only limited information - like the last location. But they have the whole location history, so you could pull a map of where the device has been to, reconstruct robber's moves, but this data is kept from you.

It is also very stupid, that since the device is broadcasting on BLE, there is no tool, to easily see that you are close to your device, or getting closer etc. Which would have helped us with the search in the hostel.

# Continuing the search
Going to the hostel, completely unprepared, I quickly went through how Find My works and downloaded some random BLE tracker app to my iPhone. I was hoping to see something useful there, but there were some iPhones around, Google Nest cameras (which the reception told us are not working anyways), some Androids, Bluetooth speakers and a lot of devices tagged as Unknown.

Going through the building both on Friday and Saturday, we returned back to Prague. On the way back, I realized that there has to be a way to track the device, and started looking into how Find My works much closer. I really regret not doing it beforehand, because we could've came in ready.

# Figuring out Find My Offline Find
Thankfully there's a lot of Open Source. I started with getting myself a MacBook from a colleague (thanks Martin!), and going through the [OpenHaystack](https://github.com/seemoo-lab/openhaystack) project, which is attempting to use Apple's Find My network to enable use of custom made AirTags. This project provided me with a very important research paper [Who Can Find My Devices? Security and Privacy of Apple’s Crowd-Sourced Bluetooth Location Tracking System](https://www.petsymposium.org/2021/files/papers/issue3/popets-2021-0045.pdf) which pretty much explains everything about this technology.

Unfortunately OpenHaystack is quite old, and doesn't work on the latest MacOS because it relies on some hacks via a plugin in the Mail app (shame on you Apple, for not giving us a proper API for this at least!), and it pulls data from the Find My servers which is quite useless in the case, where we need to see how far we are from the device.

Luckily, there is a [FindMy.py](https://github.com/malmeloo/FindMy.py) project, which does a lot of things for you (I am skipping the part, where I tried to figure a lot of this on my own). Basically, it uses [bleak](https://github.com/hbldh/bleak) library to interact with Bluetooth stack on the device, perform the search and decode the returned packets.

> Apple encodes part of the public key into the broadcasted MAC address, so it changes every 15 minutes, like mentioned above. See the [paper](https://www.petsymposium.org/2021/files/papers/issue3/popets-2021-0045.pdf) to learn more about the packet structure.

One issue is, that when this code is run on MacBook, Apple [will return UUID for the BT device instead of a MAC](https://bleak.readthedocs.io/en/latest/backends/macos.html#specific-features-for-the-macos-backend), so you have to specifically say, that you want a MAC address back - by passing `cb=dict(use_bdaddr=True)` into `BleakScanner`.

After getting myself a second MacBook for testing (thanks Karel!), I managed to discover it, verify that the keys are changing every 15 minutes and that I am able to track the device's proximity based on signal strength (more on that later).

Now to the next challenge - finding the needle in the haystack. There are many MacBooks broadcasting things like this. Take a trip by metro and try the discovery, or at a dentist's office, or at your work. Without knowing what we're looking for, this would be just a bruteforce search which would be set for failure.

## Identifying the right device
Like mentioned above, the initial keypair and shared secret, and also the pair time are stored in iCloud protected by a keychain stored password. Luckily, [someone already managed](https://gist.github.com/YeapGuy/f473de53c2a4e8978bc63217359ca1e4) to find a way to get the keychain password and decrypt the files, yay (there is [another version](https://gist.github.com/airy10/5205dc851fbd0715fcd7a5cdde25e7c8) which wasn't working for me)!

Once we manage to get the keys required to generate the device's current public key, we can move on. [FindMy.py](https://github.com/malmeloo/FindMy.py) also includes a code to generate the public keys for a specific period of time, so we are going to use it. It is made for AirTags, which use two shared secrets, but with MacBook (and phones), we only have one. So modifying the code slightly, we obtain the list of all possible public keys for the specific device.

> I also modified it to get the future keys, because keys of the past are useless for realtime search.

We then feed the public keys to the scanner, so that we can filter out the device we are looking for, and we have built a proximity sensor, which will alert us of the right device in the viscinity. We can then use the signal strength (RSSI) to see how far (approximately) it is. Find the right room or place and...

After this, I performed bunch of tests in the office building to make sure that I can get the lock on the signal, see how it behaves through floors, outside and so on (thanks Dominik!).

I also pulled the 7 day location history of the device from OF, so we built an location history map.

# Returning back to Berlin
After the first failed attempt to search (without proper knowledge), we returned back to the hostel in Berlin. Unfortunely, the last OF ping was from Sunday 18th, and we we returned on Friday 23rd. The chances to find it were already low by then, due to the fact that the battery could've died, which would render all above useless. I remained optimistic, and from the last visit to the hotel, I was thinking that it was just nobody with an iPhone or iPad around to pick the OF beacon.

We arrived in late evening, started walking through the building and trying to scan for any signal. We discovered bunch of devices broadcasting OF beacon, but none of them matched the key of the one we were searching for. At that time, I already knew that the method above is not going to work, since if it's not broadcasting, we cannot detect it.

Our last shot was calling the police and having them search the room again. Kudos to them, but unfortunately, the room search (I am however not very confident that they searched the right room) turned out nothing.

So unless someone finds the MacBook and brings it to the police or reception, it is lost forever.

# Next steps...
We were too late. We couldn't have retrieved this one (or maybe yes, but by breaking law and being very annoying by going door to door). But we could've if we had the knowledge beforehand. And that's the thing I am going to focus on - a chance to help others to find their lost devices leveraging Find My and Offline Find.

Starting by putting together all the Python scripts we used during the search and putting together a guide to do the same on **[GitHub](https://github.com/hajekj/OfflineFindRecovery)**.

Next step is going to be to take the code, turn it into a JavaScript (or compile via WASM) and create a user-friendly application user interface where the user can simply input the beacon keys and it will search for the device and show the signal strength (or distance). It is all going to be free to use and open-source.