# Glyph

Glyph turns a message into gibberish that only someone with the same secret word
can turn back.

You type `Meet me at seven`, Glyph gives you something like
`GLY1000067lLuzPErTS98sNE1gHKPvilgl6ia…`, and you send that through WhatsApp,
Messenger, email, a text — anything. Your friend pastes it into their Glyph,
types the same secret word, and reads your message.

Nobody in between can read it. Not WhatsApp, not your phone company, not
whoever runs the wifi. They see the gibberish and nothing else.

**Glyph has no accounts, no sign-up, and never connects to the internet.**
Everything happens on your own phone or in your own browser. There is no server
anywhere holding your messages, because there is no server at all.

---

## Get Glyph

### On Android

1. Open the **[latest release](https://github.com/Arishh420/glyph/releases/latest)**
   and download `glyph-1.0.0.apk` onto your phone (about 50 MB).
2. Open it. Android will say something like *"For your security, your phone
   isn't allowed to install unknown apps from this source."*
3. Tap **Settings** in that message, turn on **Allow from this source**, then
   press back.
4. Tap **Install**.

**That warning is normal and expected.** It appears for every app that does not
come from the Google Play Store. Putting an app on the Play Store costs money and
requires handing over identity documents, which is a lot to ask for something you
share with a few friends. The warning is Android telling you it cannot vouch for
where the file came from — so only install it if you trust whoever sent you the
link.

If you want to be certain the file you downloaded is the one that was published,
run this on a computer and check the answer matches:

```
shasum -a 256 glyph-1.0.0.apk
145a6a7b317e4e7d642853d3413cb3e0f80a4bc8a201bccf005448991f6c592b
```

The certificate the app is signed with has SHA-256 fingerprint
`a7a30aa6024572baabd366673893d192fc65a8e6e4baa4d6624a23c5fb94a316`. Every future
version must show that same fingerprint. If one ever does not, it did not come
from the same person, and Android will refuse to install it over this one.

### On iPhone

**Use the web version: https://arishh420.github.io/glyph/**

There is no iPhone app and no file to install. Apple only allows apps through
the App Store, which needs a paid developer account, so the website is the
iPhone version. It works exactly the same way.

In Safari you can tap the **Share** button and then **Add to Home Screen**, and
it will get an icon and open like a normal app.

### On a computer

Open **https://arishh420.github.io/glyph/** in any browser.

---

## How to use it

**First, agree on a secret word with your friend.** Say it out loud in person,
or send it a completely different way from how you send the messages. If you
text someone the secret word and then text them the gibberish, anyone reading
those texts has both halves and the whole thing was pointless.

Then:

1. **Type the secret word** in the top box. Both of you type the exact same one.
2. **Type your message** in the bottom box.
3. **Press Encrypt.** The gibberish appears in the middle box.
4. **Press the copy button**, then paste it into whatever app you normally use.

To read a message someone sent you, paste their gibberish into the bottom box
instead. Glyph notices it is a Glyph message and the button changes to
**Decrypt**. Press it and your friend's message appears in the middle box.

There is no encrypt/decrypt switch to get wrong. Glyph works out which one you
meant from what you paste in.

---

## Things worth knowing

### Choose a secret word of 12 characters or more

This is the single most important thing on this page.

A short secret word can be guessed. Someone with a normal computer can try every
short word and phrase there is, very fast, and one of them will be yours. Glyph
deliberately makes guessing slower, but that only multiplies however much
protection your word already gave you — and multiplying something tiny still
leaves something tiny.

**Length is what protects your messages.** `sunflower-canoe-bridge` is enormously
stronger than `cat123`, and it is easier to remember. Four or five words strung
together is ideal. Glyph accepts as few as 4 characters, because sometimes you
genuinely do not care who reads something, but do not use a short one for
anything that matters.

There is a dice button that invents a strong random word for you, if you would
rather not think of one.

### Both of you need the same secret word

There is no "send a friend request" step. The secret word is the whole system.
If your words differ by even one letter — or one is capitalised differently —
the message will not open.

### The same message looks different every time

Encrypt `hello` twice and you get two completely different-looking results. This
is deliberate and correct. If the same message always produced the same
gibberish, anyone watching could learn to recognise your common phrases without
ever breaking anything. Both versions decrypt back to `hello` perfectly.

### You cannot encrypt something twice

Glyph decides what to do by looking at what you paste in. If it already looks
like a Glyph message, Glyph will always try to *decrypt* it. So you cannot take
some gibberish and encrypt it a second time for extra safety. There is no need
to anyway — once is enough.

### In the browser, your secret word is not saved

The Android app remembers your secret word between uses, kept in the private,
encrypted storage Android provides for exactly this.

The website deliberately does not remember it. **Refresh the page and you will
have to type it again.** This is on purpose: anything a web page saves in your
browser can be read by other things running in that browser, and a secret word
is not something to leave lying around. It is a small annoyance in exchange for
the secret word never being written down anywhere.

### The installed Android app is the safer of the two

Worth being straight about, because it affects which one you should choose.

When you install the Android app, the code is fixed on your phone at that moment.
It cannot change unless you deliberately install a new version.

A website is different. Every single time you open it, your browser downloads the
code afresh from the internet. Today it does what this page describes. Whoever
controls that web address could, in principle, put different code there tomorrow
— code that quietly keeps a copy of your messages — and you would have no way to
notice.

That is not a claim anyone has done this. It is just how websites work, and it is
true of every website you have ever used. **If you are on Android, prefer the
installed app.** The website exists because iPhone users have no other option.

### What the messages mean when something goes wrong

| What you see | What it means |
|---|---|
| *"This doesn't look like a Glyph message."* | What you pasted is not a Glyph message at all. Usually ordinary text, or only part of a message got copied. |
| *"This message is incomplete or was damaged in transit."* | It is a Glyph message, but a piece is missing or something mangled it. Ask for it to be sent again. |
| *"Wrong key, or the message was changed after it was encrypted."* | The commonest one. Nearly always the two secret words do not match. Check spelling and capital letters. |
| *"This message was made by a newer version of Glyph."* | The sender has a newer Glyph than you. Update yours. |

Glyph never shows you a half-decrypted mess. Either it worked, or it tells you
plainly that it did not.

---

## Please read this part

**Glyph is a casual tool for private conversations between friends. It is not a
security product.**

It was written by one person, for fun, and **nobody independent has ever checked
it**. Real security tools get examined for years by specialists who are paid to
find mistakes. That has not happened here and is not going to.

It is good enough to keep your group chat out of the hands of the messaging app,
an advertiser, or a curious housemate. **Do not use it for anything where
somebody being able to read your message would genuinely hurt you** — not for
anything legal, medical, financial, or anything involving your safety. For those,
use Signal, which is free, is audited, and is built by people who do this
properly.

---

## For the curious

The exact cryptography — the cipher, the key stretching, the message format, and
the reasoning behind each choice — is written up in **[TECHNICAL.md](TECHNICAL.md)**.

Licensed under the [MIT licence](LICENSE).
