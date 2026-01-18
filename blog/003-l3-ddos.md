# On L3/L4 DDoS attacks and BPF XDP mitigation

Layer 3 and Layer 4 DDoS attacks rely on high volumes of traffic to consume bandwidth and overwhelm the target.

However, as we can see in Cloudflares DDoS reports, >90% of those attacks do not actually have a higher bandwidth than a usual server (1 Gbps).
This does not mean that >90% of L3/L4 attacks fail, it means that the bottleneck of the target is the software.

Here i want to write about two prominent examples.

## SYN flood

A SYN flood tries to overwhelm the target by spaming TCP SYN packets, without actually establishing a connection.
It fills up the connection tracking table and once that one is full, other connections get dropped and the service is rendered unusable.

You can spot stuch an attack on the **nf_conntrack_count** being close to **nf_conntrack_max**

```bash
# sysctl net.netfilter.nf_conntrack_max
net.netfilter.nf_conntrack_max = 262144
# sysctl net.netfilter.nf_conntrack_count
net.netfilter.nf_conntrack_count = 262143
```

**nf_conntrack_max** can be adjusted in `/etc/sysctl.conf`, which will take effect after reboot or by executing `sysctl -p`

## UDP flood

A UDP flood tries to overwhelm the target with UDP packets on random high ports. The attacker knows that the target may filter those packets, but hopes that the volume is high enough to cause problems anyway.

Usually the bottleneck is not the hardware itself, but the RX ring buffer in which the NIC stores references to the packets. Once the ring buffer is filled up, other packets get dropped.

You can spot this on a high amount of dropped RX packets **AND** overruns:

```bash
# ifconfig eth0
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet [censored]  netmask 255.255.255.248  broadcast [censored]
        inet6 [censored]  prefixlen 64  scopeid 0x0<global>
        inet6 [censored]  prefixlen 64  scopeid 0x20<link>
        ether [censored]  txqueuelen 1000  (Ethernet)
        RX packets 84330013  bytes 108570546096 (108.5 GB)
        RX errors 0  dropped 83164  overruns 82721  frame 0
        TX packets 654577  bytes 495491060 (495.4 MB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
        device memory [censored]
```

you can check the size of the ring buffers with ethtool

```bash
root@host:~# ethtool -g eth0
Ring parameters for eth0:
Pre-set maximums:
RX:                     4096
RX Mini:                n/a
RX Jumbo:               n/a
TX:                     4096
TX push buff len:       n/a
Current hardware settings:
RX:                     256
RX Mini:                n/a
RX Jumbo:               n/a
TX:                     256
RX Buf Len:             n/a
CQE Size:               n/a
TX Push:                off
RX Push:                off
TX push buff len:       n/a
TCP data split:         n/a
```

and increase it

```bash
ethtool -G eth0 rx 4096 tx 2084
```

## Mitigating with BPF

SYN and UDP floods are abnormal traffic and can be spot easily. That's why those attacks are usually of high volume, but small duration.

**iptables** and **nftables** can be used to block and rate limit packets. PREROUTING rules in the RAW table are run before conntrack and are able to rate limit and filter SYN floods. But we could go even earlier into chain with BPF.

A **BPF** program using **XDP** is hooked into the network driver and executes right after the packet entered memory. It has limited functionality, because the connection isn't tracked yet, but it is 10 to 100 times faster than iptables rules (depending on the rules we talk about). SYN floods can be mitigated, because**nf_conntrack** can not overflow if the packets do not reach it. UDP floods will need 10 times more effort to overrun the RX ring buffer, if the packets are dropped 10 times faster.

**BPF XDP** can not fully replace iptables / nftables / etc., it is an addition. All rules that need conntrack (state ESTABLISHED) need to be later in the chain.

### Writing a BPF programs

Here a list of multiple articles explaining the process:

- https://www.srodi.com/posts/ddos-mitication-with-ebpf-xdp/
- https://medium.com/@phylake/bottom-up-ebpf-d7ca9cbe8321
- https://apipark.com/techblog/en/inspecting-incoming-tcp-packets-with-ebpf-a-comprehensive-guide/

And here a program that rate limits TCP SYN and UDP and closes ports for both (so **DO NOT** blindly run it, everything is hardcoded), it is a reference for how to rate limit and check ports:

```c
#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/ipv6.h>
#include <linux/udp.h>
#include <linux/in.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

/*
 * rate limit structs
 */

struct rate_limit_entry {
  __u64 last_update;
  __u8 blocked;
};

struct {
  __uint(type, BPF_MAP_TYPE_LRU_HASH);
  __uint(max_entries, 16384);
  __type(key, __u32);  // v4 address
  __type(value, struct rate_limit_entry);
} rate_limit_v4 SEC(".maps");

struct {
  __uint(type, BPF_MAP_TYPE_LRU_HASH);
  __uint(max_entries, 16384);
  __type(key, __u64);  // first 64 bit of v6 address
  __type(value, struct rate_limit_entry);
} rate_limit_v6 SEC(".maps");

/*
 * tick rate limiter, return boolean if blocked
 */
static __always_inline int tick_rate_limit(struct rate_limit_entry *rate_limiter, __u8 pps) {
  if (!rate_limiter) {
    return 0;
  }

  __u64 current_time = bpf_ktime_get_ns();

  if (rate_limiter->blocked) {
    if (rate_limiter->last_update < current_time) {
      rate_limiter->last_update = current_time;
      rate_limiter->blocked = 0;
      return 0;
    }
    return 1;
  }

  if (rate_limiter->last_update < current_time) {
    rate_limiter->last_update = current_time + 1000000000 / pps;
    return 0;
  }

  rate_limiter->last_update += 1000000000 / pps;

  if (rate_limiter->last_update > current_time + 1000000000) {
    // block for an hour after this packet
    rate_limiter->last_update = current_time + 1000000000ULL * 3600;
    rate_limiter->blocked = 1;
    return 2;
  }
  return 0;
}

/*
 * Check if incomming TCP packet is allowed
 * Note: We only filer SYN packets here, ESTABLISHED and RELATED needs to be
 * additionally filtered with iptables
 */
static __always_inline int is_tcp_allowed(struct tcphdr *tcph, struct rate_limit_entry *rate_limiter) {
  // Only act on SYN packets
  if (!(tcph->syn && !tcph->ack)) {
    return 1;
  }

  if (tick_rate_limit(rate_limiter, 150)) {
    return 0;
  }

  __u16 dest_port = bpf_ntohs(tcph->dest);

  switch (dest_port) {
    case 443: // https
    case 80: // http
    case 22: // ssh
      return 1;
    default:
      return 0;
  }
}

/*
 * Check if incomming UDP packet is allowed,
 * Note: This includes responses to outgoing requests we sent (DNS)
 */
static __always_inline int is_udp_allowed(struct udphdr *udph, struct rate_limit_entry *rate_limiter) {
  if (tick_rate_limit(rate_limiter, 200)) {
    return 0;
  }

  __u16 dest_port = bpf_ntohs(udph->dest);

  if (dest_port >= 65400 && dest_port <= 65535) {
    return 1;
  }

  __u16 src_port = bpf_ntohs(udph->source);

  if (
    // DNS responses
    (src_port == 53 && dest_port >= 1024)
    // DHCP responses
    || (src_port == 67 && dest_port == 68)
    // NTP responses
    || (src_port == 123 && dest_port == 123)
  ) {
    return 1;
  }

  return 0;
}


SEC("prog")
int xdp_firewall_filter(struct xdp_md *ctx) {
  // allow all otbound
  if (ctx->rx_queue_index == 0xFFFFFFFF || ctx->ingress_ifindex == 0) {
    return XDP_PASS;
  }

  void *data_end = (void *)(long)ctx->data_end;
  void *data = (void *)(long)ctx->data;
  struct ethhdr *eth = data;
  // bound check
  if ((void *)eth + sizeof(*eth) > data_end) {
    return XDP_PASS;
  }

  // IPv4 handling
  if (eth->h_proto == bpf_htons(ETH_P_IP)) {
    struct iphdr *iph = data + sizeof(*eth);
    // bound check
    if ((void *)iph + sizeof(*iph) > data_end) {
      return XDP_PASS;
    }

    __u32 addr = bpf_ntohl(iph->saddr);
    struct rate_limit_entry *rate_limiter = bpf_map_lookup_elem(&rate_limit_v4, &addr);
    if (!rate_limiter) {
      struct rate_limit_entry new_entry;
      __builtin_memset(&new_entry, 0, sizeof(new_entry));
      bpf_map_update_elem(&rate_limit_v4, &addr, &new_entry, BPF_ANY);
      rate_limiter = bpf_map_lookup_elem(&rate_limit_v4, &addr);
    }

    // TCP
    if (iph->protocol == IPPROTO_TCP) {
      // fragments in tcp don't need attention
      if (iph->frag_off & bpf_htons(0x1FFF)) {
        return XDP_PASS;
      }

      struct tcphdr *tcph = (void *)iph + (iph->ihl * 4);
      // bound check
      if ((void *)tcph + sizeof(*tcph) > data_end) {
        return XDP_PASS;
      }

      if (is_tcp_allowed(tcph, rate_limiter)) {
        return XDP_PASS;
      }
      return XDP_DROP;
    }
    // UDP
    else if (iph->protocol == IPPROTO_UDP) {
      // fragments in udp need ratelimit
      if (iph->frag_off & bpf_htons(0x1FFF)) {
        if (tick_rate_limit(rate_limiter, 50)) {
          return XDP_DROP;
        }
        return XDP_PASS;
      }

      struct udphdr *udph = (void *)iph + (iph->ihl * 4);
      // bound check
      if ((void *)udph + sizeof(*udph) > data_end) {
        return XDP_PASS;
      }

      if (is_udp_allowed(udph, rate_limiter)) {
        return XDP_PASS;
      }
      return XDP_DROP;
    }
  }
  
  // IPv6 handling
  else if (eth->h_proto == bpf_htons(ETH_P_IPV6)) {
    struct ipv6hdr *ip6h = data + sizeof(*eth);
    // bound check
    if ((void *)ip6h + sizeof(*ip6h) > data_end) {
      return XDP_PASS;
    }

    __u64 addrv6 = ((__u64)bpf_ntohl(ip6h->saddr.in6_u.u6_addr32[0]) << 32) |
    bpf_ntohl(ip6h->saddr.in6_u.u6_addr32[1]);
    struct rate_limit_entry *rate_limiter = bpf_map_lookup_elem(&rate_limit_v6, &addrv6);
    if (!rate_limiter) {
      struct rate_limit_entry new_entry;
      __builtin_memset(&new_entry, 0, sizeof(new_entry));
      bpf_map_update_elem(&rate_limit_v6, &addrv6, &new_entry, BPF_ANY);
      rate_limiter = bpf_map_lookup_elem(&rate_limit_v6, &addrv6);
    }
    
    // TCP
    if (ip6h->nexthdr == IPPROTO_TCP) {
      struct tcphdr *tcph = data + sizeof(*eth) + sizeof(*ip6h);
      // bound check
      if ((void *)tcph + sizeof(*tcph) > data_end) {
        return XDP_PASS;
      }
      
      if (is_tcp_allowed(tcph, rate_limiter)) {
        return XDP_PASS;
      }
      return XDP_DROP;
    }
    // UDP
    else if (ip6h->nexthdr == IPPROTO_UDP) {
      struct udphdr *udph = data + sizeof(*eth) + sizeof(*ip6h);
      // bound check
      if ((void *)udph + sizeof(*udph) > data_end) {
        return XDP_PASS;
      }
      
      if (is_udp_allowed(udph, rate_limiter)) {
        return XDP_PASS;
      }
      return XDP_DROP;
    }
    // fragments
    else if (ip6h->nexthdr == IPPROTO_FRAGMENT) {
      if (tick_rate_limit(rate_limiter, 50)) {
        return XDP_DROP;
      }
      return XDP_PASS;
    }
  }

  return XDP_PASS;
}


char _license[] SEC("license") = "GPL";

```

I will not explain the code at this point, but comment on the rate limiting logic:

```
struct rate_limit_entry {
  __u64 last_update;
  __u8 blocked;
};

struct {
  __uint(type, BPF_MAP_TYPE_LRU_HASH);
  __uint(max_entries, 16384);
  __type(key, __u32);  // v4 address
  __type(value, struct rate_limit_entry);
} rate_limit_v4 SEC(".maps");

struct {
  __uint(type, BPF_MAP_TYPE_LRU_HASH);
  __uint(max_entries, 16384);
  __type(key, __u64);  // first 64 bit of v6 address
  __type(value, struct rate_limit_entry);
} rate_limit_v6 SEC(".maps");
```

There are two maps for rate limiting, one for IPv4 and one for IPv6, the only difference is the key, the v4 one has a u32 key, storing the whole IPv4 address, while the v6 one has a u64 key, storing the upper half of the IPv6 address. We only want the upper half, because \64 is the prefix usually handed out by ISPs.
Rate limiting itself only happens via a timestamp in nanoseconds and a *blocked* boolean. The timestamp starts at the current time and gets incremented by the time allowed between packets whenever a packet comes in. If packets come in faster than the rate we allow, it keeps moving into the future until it hits a certain threshold (1s here), once hit, the blocked boolean gets set to 1 and the timestamp moves 1 hour into the future. Packets will then get dropped until the timestamp is below the current time again (so 1 hour of temporary block), at which point blocked gets set to 0 again.

The rate_limit_v4 and rate_limit_v6 maps can be checked with bpftool, to list the currently blocked IPs:

```bash
#!/bin/bash
set -e

echo "Blocked IPv4 Addresses:"
bpftool map dump name rate_limit_v4 -j 2>/dev/null | \
    jq -r '.[] | select(.formatted.value.blocked != 0) | 
           .formatted.key' 2>/dev/null | \
    while read -r key; do
        printf "%d.%d.%d.%d\n" \
            $(( (key >> 24) & 0xFF )) \
            $(( (key >> 16) & 0xFF )) \
            $(( (key >> 8) & 0xFF )) \
            $(( key & 0xFF ))
    done

echo -e "\nBlocked IPv6 Prefixes:"
bpftool map dump name rate_limit_v6 -j 2>/dev/null | \
    jq -r '.[] | select(.formatted.value.blocked != 0) | 
           .formatted.key' 2>/dev/null | \
    while read -r key; do
        printf "%04x:%04x:%04x:%04x::/64\n" \
            $(( (key >> 48) & 0xFFFF )) \
            $(( (key >> 32) & 0xFFFF )) \
            $(( (key >> 16) & 0xFFFF )) \
            $(( key & 0xFFFF ))
    done
```

## Other L3/L4 attack scenarios

**Ping floods**, **IP Fragmentation** and **DNS floods** can be limited with minor adjustments as well. A BPF XDP program will execute before the kernel stitches fragments together.

In example, to rate limit ICMP echos of a ping flood:

```c
    else if (iph->protocol == IPPROTO_ICMP) {
      // don't care about fragments
      if (iph->frag_off & bpf_htons(0x1FFF)) {
        return XDP_PASS;
      }
      // get the type
      void *icmp_ptr = data + sizeof(*eth) + (iph->ihl * 4);
      if (icmp_ptr + 1 > data_end) {
        return XDP_PASS;
      }
      __u8 icmp_type = *(__u8 *)icmp_ptr;

      if (icmp_type == ICMP_ECHO || icmp_type == ICMP_ECHOREPLY) {
        if (tick_rate_limit(rate_limiter, 30)) {
          return XDP_DROP;
        }
      }
    }
```

## Conclusion

Before looking for companies and anti-DDoS services, it is worthwhile to first exhaust your own options. Custom BPF programs, written for your specific scenario, are worth the effort.
