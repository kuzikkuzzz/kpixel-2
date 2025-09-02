# An Essay about Sessions, Authentication and Authorization

For over a year [we](https://pixelplanet.fun) experience a heightened amount of account hijacking, which culminated in the account of an inactive moderator, who still had moderation rights, getting stolen and abused in August 2025.

We learned a lot in the past five years, so i will use this opportunity to write down our experiences.

## What we are

We are an [Open Source](https://git.pixelplanet.fun) browser game for placing pixels on a canvas, that aims to be as open as possible. We do not want users to require an account to play.
And if they create an account, they don't have to use a social media login, but they can, if they want to. So we offer both classic email / password registration and oauth login for Google, Discord, Reddit, Facebook, etc.  
We do not want to depend on any third-party services that could cause us or our players issues.

Our moderation is mostly limited to laws and a do-no-harm principle (so botting gets banned and using proxies is forbidden). We have no written rules on the website. One could call it a Free Speech website, but i dislike that term, since we do collective punishment for whole countries if a high number of their users misbehave.

By the nature of our game, we are targeted by all kinds of malicious actors. That ranges from SYN flood DDoS attacks strong enough to get our IPs temporary blackholed, to fake abuse report floods to Cloudflare, which got us [locked with false phishing warnings](https://community.cloudflare.com/t/epidemic-of-false-phishing-warnings/799121) and horrid cloudflare *Trust and Safety Team* experiences. And of course we get flooded by proxies and VPN abuse, since one can play without an account.

There is even a whole ecosystem of clones, so other websites who run our software, since it is Open-source. And those initially tried to attack us — the people who created the software they use — because they saw us as their competition.  
A futile endeavor, which eventually died down and they coexist now.

### Accounts are valuable, even when they are not

Our accounts aren't linked to anything valuable. They can barely access more than statistics about their own playtime. Yet, accounts are a valuable resource. Some people sell them and some people try to trick others into installing info stealer malware to grab theirs.

## Handling multiple Authorization methods

Offering both email / password registration and oauth logins creates unique challenges, with solutions that aren't as straight-forward as someone might expect.

### E-Mail addresses aren't special

When someone uses a Google account to log in once, and a Discord account another time, it would be desirable for him to land in the same account. The one common denominator could be the email address.  
Create the account, remember the email address and login based on the email address of the third party provider, correct? **Nope**

There are oauth providers that do not give you access to the users email address. There are providers who allow users to register without an email address, or did so in the past (Reddit). Some providers share unverified email addresses. You can not expect a provider to always offer you a trustworthy address. They might stop doing that at any point. And there are providers who may offer multiple email addresses (Facebook).

An email address, a phone number, a Google profile ID, a Discord user ID, etc. are all **Third Party Identifiers (ThreePIDs)**. They have the purpose to link an account to another account somewhere else, be it the email mailbox or the Discord profile. They should be treated the same. So we have a `ThreePID` table in our database that links a users `uid` to a `provider` enum (email, google, discord,...), a `tpid` varchar, a `verified` boolean and a `normalized_tpid` varchar. An oauth login provider will give us multiple ThreePIDs, usually an email and a profile id, and we check all of them.

A Login Form is different on the application side to implement from an oauth login and we might treat the email address differently (e.g. for notification mails or password forgotten forms), but for the database layout, this doesn't matter.

A password is associated with a user, not with a Third Party Identifier. A user could have no ThreePID and login with username and password alone. Whether or not we allow that, is up to the application code, the database scheme shouldn't limit us.  
And a password should be optional, since a user who uses oauth login won't be happy to get a box to enter a password.

### Verification

Almost every account system has a form of **verification** to prove that the Third Party Identifier (ThreePID) is owned by the user who claims it. Usually the user can be in a state of being **unverified**, if the verification can be done later.  
We consider a user verified when at least one associated ThreePID is `verified`. A Google profile id and its email address are verified after successful oauth login, but the email address is only accepted if Google returns `email_verified` as true. An email address from local registration is not verified, unless the user clicks on a verification link in the email he received. A reddit profile id is not verified (it's a special case).

### Third party identifiers need to be removable

A user needs to be able to change the email address associated with his account, this is obvious. But it is equally important to be able to remove a Google or Discord account (both can be deleted or lost).

And every time we remove a ThreePID, we have to ensure that the user still has a method left to login.
If the user set a password, he could be able to remove all his ThreePIDs, since the name / password login is still possible. If he doesn't have a password set, we have to ensure that at least one ThreePID, that isn't an email address, remains.

The ability to link new social media accounts (like a Discord account that uses a different email address and therefor isn't found and linked when the address is checked), isn't nearly as important as the ability to remove them. In fact, we don't have that ability and in five years i had not a single user requesting this functionality to be added.

### Normalize email addresses

Sending an email to `example+A@gmail.com` or `e.xam.ple@gmail.com` will be received by `example@gmail.com`.  
This is why we have a `normalized_tpid` column in the `ThreePID` table that is generated by:

```
VARCHAR(80) GENERATED ALWAYS AS (CASE WHEN provider != 1 THEN NULL WHEN LOCATE(\'@\', tpid) = 0 THEN NULL ELSE LOWER(CONCAT(REPLACE(SUBSTRING_INDEX(SUBSTRING_INDEX(tpid, \'@\', 1), \'+\', 1), \'.\', \'\'),\'@\',(SUBSTRING_INDEX(tpid, \'@\', -1)))) END) STORED
```

`provider` of `1` is email. There is a unique index on `provider` + `normalized_tpid` and another on `provider` + `tpid`.
This ensure that the user still gets his emails on `example+ppfun@gmail.com`, if he registered with this address, while he will be incapable of creating a different account under `example+whatever@gmail.com` and a Google login for `example@gmail.com` will link to the same account.

### Split Display Name and User Name

Each platform has different requirements for user names. Some don't have user names and use real life name and surname instead.
Since we don't want to bother oauth users with text input boxes on login, we take whatever name we can get and use it as display name. The display name is utf8mb4 and can include emojis. There is also a username with stricter requirements, limited to a subset of ASCII, which will be auto filled as `pp_[userId]` for oauth users and can be changed once later.

The display name is what will be seen everywhere on the platform. The stricter username can be used for searches or to provide emails or matrix or anything else that needs a shorter readable name.
Splitting the display name from the username is very common nowadays, Discord moved to this concept a while ago as well. A different concept is to auto-generate random names for oauth users, which is what Reddit does.

## Sessions

Handling sessions isn't nearly as hard as some developers make it out to be.

### Session Tokens belong in a relational database

Sessions will be associated with users, they need to be able to be filtered and cleared and they can get related to device information (like browser and operating system) and ip location. So they belong inside the database.

I point this out because we used `express-sessions` with `connect-redis` to store it inside the `redis` key-value-store at first. This made it impossible to remove all sessions of a user without iterating over every single session that exists.

### Session Token Length

[OWASP](https://owasp.org/www-community/vulnerabilities/Insufficient_Session-ID_Length) recommends at least 64 bit entropy and [PHP](https://www.drupal.org/node/3469305) uses a 128 bit token (a 32 character hex string). `express-sessions` generates 192 bit tokens and appends a HMAC signature using a provided secret. I decided for a 240 bit token (40 base64url characters) and a `sha264` HMAC.

### Hash Session Tokens

Database leaks (could be from a backup) and [attackers achieving direct database access](https://riskybiznews.substack.com/p/risky-biz-news-kiwifarms-discloses) are common worst-case-scenarios. Every responsible website is hashing passwords to mitigate damage in such a case, but hashing session tokens is less common.  
However, we do not want an attacker to gain access to an account by using a session token from a database leak either, so we hash it. The requirements are different from a password. We want a fast hashing algorithm, since it gets used much more, but want to avoid collisions, so it needs a decent length. `SHA-2` will be sufficient, with 224, 256 or 512bit chosen based on token length. In case of a breach, all sessions should be deleted, which forces users to login again, but doesn't do any other damage. If the hacker manages to crack one hash after weeks, it is irrelevant at that point. The hashing has the purpose to buy us time.

The HMAC signature of the cookie doesn't protect us in a database breach scenario, because its secret will be known to the same server that connects to the database, where the breach possibly happened. I know a case where sessions got hijacked by grabbing the database and the secret.

### Allow to log-out other Sessions

A user should be able to log out any other session he might have open. Even better when the browsers, operating systems and countries of the other sessions are shown. In comparison: The only way in Discord to invalidate a session token is by changing the password.

### Session rejection on IP location changes

Don't automatically reject a session because it uses a different ip subnet than it got originally created with.  
There is an obvious security benefit in doing so, but it is a major annoyance that isn't worth it. Imagine having multiple connections, like fiber and phone tethering, and on every switch you have to login again.

It is much more reasonable to reject the session on browser or operating system change. Or any form of server-side fingerprinting that doesn't involve the exact browser version.

Notifying the user when someone logs in from a different location is annoying as well. Some people clear their cookies regularly, which is a great habit that should not be discouraged by flooding them with login notification mails. A notification on state or country change however, is very good.

### Let the user choose the duration of the Session

Over a decade ago every website had a checkbox on login: `"Keep me logged in"`, which was unchecked by default. For some unknown reason, this is rare now.

### Consider Cross-Site Request Forgery (CSRF)

Be aware that it exists and keep it in mind when designing APIs. There are [many ways to prevent it](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html).

### Be able to mark accounts as compromised

When an account is compromised, we reset the password hash to the text `"hacked"`, delete all sessions of the user, revert the associated email if it got changed recently, and tell the user to use the `I forgot my password` function to reset it the next time he tries to login.

### JWT

[JSON Web Tokens](https://en.wikipedia.org/wiki/JSON_Web_Token) are base64 encoded and HMAC signed JSON tokens that include an expiration time and session information like user id, name, etc.. They get stored on the client (either in localStorage or a cookie). The HMAC uses a secret that is known to all involved servers. They gained popularity because it is great for `"serverless infrastructure"` which provides `"scalability"`.  

If the client delivers all necessary information in a token, the server doesn't have to lookup a database.

A JWT can not be invalidated, it has to expire. Implementing a revocation list to reject specific tokens would defeat the purpose of JWTs, because every single server would have to check against a common database or cache.  
This is why JWTs have to be short-lived, with an expiration time of 5 to 10 minutes. To provide prolonged access, it additionally needs a *refresh token*, which is one-time-use and can request a new JWT, together with a new refresh token.

The refresh token can be treated like a regular session token, stored in a database, with all the recommendations from above applying. This makes it possible to invalidate them. Only the server handling the refresh tokens needs database access, while other servers can rely on the JWT exclusively.

**Whoever controls the Secret controls everything**

If a malicious actor grabs the secret, he can log in as anyone, anywhere, at any time he wants. This is a worse scenario than a database breach with classic sessions and unhashed tokens, since the user can't kick an attacker out by logging out or changing password.

**Don't use JWT for sessions**

[Just](https://gist.github.com/samsch/0d1f3d3b4745d778f78b230cf6061452) [don't](https://www.youtube.com/watch?v=pYeekwv3vC4) [do](http://cryto.net/~joepie91/blog/2016/06/13/stop-using-jwt-for-sessions/) [it!](http://cryto.net/%7Ejoepie91/blog/2016/06/19/stop-using-jwt-for-sessions-part-2-why-your-solution-doesnt-work/)

### Do not store Tokens in local storage

[Local Storage](https://developer.mozilla.org/en-US/docs/Web/API/Window/localStorage) is [vulnerable to cross-site scripting](https://www.rdegges.com/2018/please-stop-using-local-storage/) attacks, a HttpOnly Cookie is not.

### Check what others are doing

It helps to look at what others are doing. For both good and bad examples. Just because something is done by a large corporation, doesn't mean that it is good. Discord stores its token in localStorage and Google allowed (maybe still does?) any active session to remove 2FA from an account without password or verification. [Both](https://www.youtube.com/watch?v=yGXaAWbzl5A) of [those](https://www.google.com/search?channel=entpr&q=steal+someones+discord+token) things got abused for years.

But neither Google, Facebook or Microsoft use JWT for sessions. Some do have HMAC signed data in their cookies, but it is used to prevent spoofing of the specific cookie rather than as a session identifier.

## Two Factor Authentication

Two Factor Authentication (2FA) ads a `"Proof of Possession"` (access to the device calculating your One-Time-Password) to a login that otherwise only requires `"Proof of Knowledge"` (knowing a password).

In theory. In practice a TOTP only proves the knowledge of the secret used to generate the One-Time-Password (OTP). A secret that is <80 bit long and also stored in the same form, unhashed, on the server, since the server verifies the OTP by generating the same OTP with the same secret and comparing.  
This doesn't mean that TOTP is useless. The benefit is the ability of the user to store it on a different device or different location (authenticator application), which is better than relying on a password alone.

A real proof of possession would be a hardware authentication device like a Yubikey. Just not one from Google, they [don't have a good track record](https://www.securityweek.com/researchers-show-googles-titan-security-keys-can-be-cloned/). A text message to a phone number isn't one, because a phone number can be hijacked by social engineering and requesting a new SIM from the mobile provider.

## Is the User allowed to be dumb?

We are a browser game, so a user might not care to use a safe password. Why would we force them to choose a 40 character password with special characters, numbers, and caps for some silly pixel game?

Forcing 2FA would mitigate the risk of a password loss, if a user chooses the same password for a hundred different services and one leaks. But is it a good practice to try to make a bad practices less bad, rather than giving the user the responsibility to not do dumb things and educating them?  
*Disclaimer: This is about enforcing 2FA for this one purpose, not about it in general.*

If and how much someone needs to protect stupidity (and annoy users by doing so), is up to the individual platform. I would feel very different about it, if i would run online banking.

#### An example

Googles Pixel phones include a TPM style chip called Titan M, which runs a large proprietary firmware blob to store encryption keys and rate-limit their access. It has the one specific purpose to make it less bad when the user chooses a <5 digit pin for his device encryption. This is about the encryption of the storage, not the unlocking, so the password entered when booting the phone. It does not provide much benefit to anyone who doesn't choose an insecure pin as password in the first place. But it does increase the attack surface, especially because that binary blob is active even when the OS is off, and it can communicate over fastboot via a special debugging cable. And the firmware can be updated and replaced.

The user puts all his trust into this binary blob. Sure, it can only effectively be abused if you have the keys to sign the firmware or there is [a major exploit](https://blog.quarkslab.com/attacking-titan-m-with-only-one-byte.html). But Google has them and therefor the NSA as well. Google also [has a horrid past](https://en.wikipedia.org/wiki/Titan_Security_Key) when it comes to such chips.

So in their task to protect people who knowingly do dumb things, they made everyone else less secure.

## So how did Accounts get stolen?

The current meta is Info Stealers. Malware that silently grabs credentials, tokens and cookies from browsers. Info stealers are replacing classic encryption ransomware, since you can also take accounts for ransom or monetize them in a different way.  
The current rise of info stealers started with Discord token grabbers. They are everywhere, in [minecraft mods](https://research.checkpoint.com/2025/minecraft-mod-malware-stargazers/), proxy software, pirated video games or [nodejs packages](https://www.cisa.gov/news-events/alerts/2021/10/22/malware-discovered-popular-npm-package-ua-parser-js), they get sold [as a service](https://www.eset.com/blog/en/business-topics/threat-landscape/lumma-stealer-threat/) and are in [fake captchas](https://www.elastic.co/security-labs/eddiestealer).  
Most of the time you hear about a "data leak", it was an info stealer. Fake Elon Musk AI videos on hijacked youtube channels? It was an info stealer.

The grabbed data gets monetized in multiple stages. Juicy session tokens from either cookies or localStorage get used directly for other campaigns. Sessions of large providers don't usually get sold off, because by session hijacking, logins (with or without 2FA) can be bypassed.

Ordinary `name:password:host` data grabbed from built-in browser password managers gets sold on the darknet or over telegram. To prove legitimacy of the data, [they provide free samples](https://t.me/+V-oTBDqBJSRkYTU0). Those free samples are ~10% of the total data and they are selected out of the lesser relevant credentials. A browser game doesn't have much relevance, so our users who installed malware are inside those.

One of our moderators was victim of such malware, but since our moderators do not have access to personal information of users, and we anonymize as much of our data as possible — with juicy information, like linked email and social media accounts, only being accessible with direct database access — the fallout was very mild, with the largest damage being players losing less than a day of progress.  
This moderator also got his Steam account and others stolen, which is a much larger issue for him.

### Would 2FA protect against such Malware?

A bit. The Info Stealers grab session tokens. In the current meta, where those free samples only include credentials, it would render those useless, but the meta might change and by next year they could publish the samples as `name:password:host:token`. There is nothing stopping them from doing this. And there is nothing stopping a current attacker from paying more money to get the whole dump which includes the tokens.

### How about a Password Manager?

A bit more. **KeePassXC** data does not get grabbed by the current most popular info stealers. However, nothing is stopping them from starting to do it in the future. It would be much more effort, since the database is encrypted and they would have to use key loggers to grab the password of the database, which is not trivial. Operating systems can protect the password prompt and stop key logging. Wayland (yikes!) attempts to do so, but malware could infect the wayland compositor itself. The password manager could be sandboxed. SELinux or AppArmor could be used to restrict access to its database. It could be run as a separate user. It could use multiple databases and the most important one, for financial stuff, on a separate flash drive.

### So what then?

While there isn't any flawless solution protecting you from malware that you yourself install, it is obvious what to avoid:

- **Do not save passwords in your browser**
- **Do not stay logged in forever**
- **Do not use the same password for multiple services**

Password managers like KeePassXC or Bitwarden allow you to do all those things in a convenient way. While they aren't perfect — and they are a single point of failure — they are a good start. If you use [a password manager](https://keepassxc.org/) and [its extension](https://addons.mozilla.org/en-US/firefox/addon/keepassxc-browser/) to login on websites, you can delete all cookies on browser close, without it being a huge annoyance.