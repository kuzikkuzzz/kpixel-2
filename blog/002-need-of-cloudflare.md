# On the need of Cloudflare for DDoS protection

According to Cloudflares last quaterly [DDoS threat report](https://blog.cloudflare.com/ddos-threat-report-2025-q3/) **29%** of encountered DDoS attacks in Q3 2025 were HTTP attacks, while in Q2 it was **56%**, Q1 **18%**, Q4 2024 **51%**.

The relation between HTTP and L3/L4 differs between quaters a lot. Same with the total amount.

Furthermore:

> 70% of HTTP DDoS attacks originated from botnets already known to Cloudflare

> most attacks, 71% of HTTP DDoS and 89% of network-layer, end in under 10 minutes

Compared with previous reports, like [Q2 2025](https://blog.cloudflare.com/ddos-threat-report-for-2025-q2/) or [Q1 2025](https://blog.cloudflare.com/ddos-threat-report-for-2025-q1/) we see that those two stats stay consistent. 

In Q2 report we have:

> In 2025 Q2, 94% of L3/4 DDoS attacks didn’t exceed 500 Mbps

A statistic we do not have in Q3 report anymore, but which is similar in Q1 with:

> 99% of Layer 3/4 DDoS attacks were under 1 Gbps and 1 Mpps

This data looks consistent as well, even thought the hyper-vulemetric attacks within the top 1% fluctuate a lot, with new highscores each quater.

## What do we get out of those numbers?

### **HTTP** DDoS attacks are underrepresented

The statistics state what Cloudflare sees, not what Cloudflare doesn't see.

A **HTTP** DDoS attack can be as simple as proxies or a VPS spaming requests at expensive API endpoints. That those attacks are limited to the (possibly residential) network speed and proxy badwidth, is barely relevant. This is the typical DDoS attack a website owner has to deal with. They get mitigated by fixing application code, adding JavaScript challenges and captchas or rate limiting and blocking in the **WAF**.

The **WAF** is nginx-as-a-service. Cloudflare offers a convenient interface for it, but can't do anything noteworthy that isn't possible in nginx. JavaScript challenges, like hashcash, can be found elsewhere as well.
Is Cloudlare interpreting every batch of rate-limit hits as an intercepted DDoS? I doubt that.

Out of personal experience (an experience many will share) **HTTP** DDoS attacks are well over 90%. This includes AI scraper spam, which is something cloudflare pretends to be able to block, but still gets through and causes problems (and then doesn't make it into the quaterly reports).

### Most attacks are below the targets available bandwidth

**94%** of **L3/4** attacks are below 500 Mbps and **99%** below 1 Gbps. They are simple to detect, so the size relations are plausible, even if many attacks might not be witnessed by Cloudflare.
**HTTP** attacks are usually smaller than **L3/4**, because they can succeed with less bandwidth.

**If it is below the limits of your hardware, you can mitigate it yourself with software**

### The larger the attack, the shorter the duration

**90%** of **L3/4** ends in less than 10min. According to cloudflares interpretion, the goal is to punch the service offline and cause a larger outage, as manual intervention may be needed to get it online again.
An alternative interpretion is that the DDoS stops if it doesn't succeed within a given timeframe, and cloudflare mitigates them.

In any way, based on the nature of these attacks, they want to hit as hard as possible, and it makes sense to run them as short as possible, given how easy they are to spot and how they affect the devices used by the attacker.
Meanwhile a low-bandwidth **HTTP** attack could run for days.

### You may be able to protect yourself

While Cloudflare ends their quaterly reports with a statement about how important it is to be behind a middleman for DDoS mitigation, the reality is:

- you should be able to mitigate **HTTP** attacks (nginx ratelimiting, fail2ban, etc.)
- you can mitigate >90% of **L3/4** attacks
- the remaining attacks may be a downtime of 30min once per month, if even that
- cloudflare doesn't do much against AI scrapers, so you have to care about your **HTTP** traffic yourself already anyway
- cloudflares captcha is worse than OpenSource solutions (e.g. Anubis or a simple self-made WASM challenge)
- some countries ban cloudflare

It is dependent on what kind of service you have, but the thought that everything needs to be behind Cloudflare, is demonstrably wrong.
