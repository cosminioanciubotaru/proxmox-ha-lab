# Proxmox VE High-Availability Cluster on Google Cloud

Three servers joined into a cluster, sharing their storage, so that any one of them
can die without taking the services down with it. Plus a separate backup server, and
a set of deliberately triggered failures to find out how well it actually works.

I wanted to know what "high availability" actually means once you have to build one,
instead of only reading about it. So I built one, and then broke it on purpose to see
what it really does.

Self-directed project, put together over about two weeks in September 2026 on Google
Cloud's free trial. Everything is documented in [`docs/`](docs/), including the parts
that went wrong.

---

## What this is

An organization that cares about uptime should not run its services on one server, but
on several that are also joined into a cluster that shares configuration and storage, so
that when one machine dies the others carry on and the entire system is not critically
affected.

Building that is the rather clear half. The more interesting half is breaking it on
purpose and measuring what happens, because "it has HA / High Availability" turns out to
mean 4 quite different things depending on what fails and what is running on top.

## Measured results

| Scenario | Mechanism | Downtime |
|---|---|---|
| Node dies, container has to move | Cluster restarts it on another node | about 30 seconds |
| Planned maintenance, VM has to move | Live migration, the VM keeps running | 30 milliseconds |
| Node dies, guest gateway has to move | Shared address claimed by another node | under 1 second, no packets lost |
| Node dies, web service has to survive | Two copies were already running | no failed requests |

How each number was measured, because it matters:

- The 30 seconds is what I saw in the cluster status, not a request loop. Treat it as
  roughly right, not exact.
- The 30 milliseconds is the switchover time Proxmox itself reports in the migration log.
  I did not measure it from outside.
- The gateway and the web service were both measured from outside, with a loop sending
  one request per second. So "no failed requests" means none at one-second sampling. A
  gap shorter than that would not show.

The gap between the first row and the last row is the point of the whole project.

Hypervisor HA restarts a service after a failure. When a machine loses power its memory
goes with it, so starting fresh somewhere else is the only physical option. That is not
a Proxmox weakness: VMware HA and Hyper-V failover clustering restart too. The exception
is VMware Fault Tolerance, which keeps a second copy of the VM running in lockstep and
really does survive a node loss with no downtime, at the cost of running everything twice
and a hard limit on VM size.

Application redundancy means the service never stopped, because a second copy was
already running and simply started receiving the traffic. The request loop during the
test, one line per second:

```
19:01:14  web1
19:01:15  web2
```

pve1 was powered off between those two lines.

Both belong in a real design. HA covers the things that cannot be clustered, redundancy
covers the things that can. Knowing which one you actually have is the difference between
promising thirty seconds and promising zero.

A monitoring container recorded the same node failure independently:

| What it watched | Uptime |
|---|---|
| The shared service address | 100% |
| The individual server that died | 67.98% |
| The second server | 100% |

Those percentages cover the short test window, not a day. web1 was unreachable from
08:48:05 to 08:51:00, just under three minutes, which is how long pve1 stayed off.

Screenshot in [`evidence/23-kuma-recovery.png`](evidence/23-kuma-recovery.png).

---

## The architecture

```
                          admin workstation
                                  |
                        IAP tunnel, authenticated
                       (no machine has a public IP)
                                  |
  ================================|================================
   Google Cloud VPC   10.10.0.0/24   europe-west3 (Frankfurt)

       pve1                pve2                pve3
    2 vCPU / 8 GB       2 vCPU / 8 GB       2 vCPU / 8 GB
    50 GB Ceph disk     50 GB Ceph disk     50 GB Ceph disk
       |                   |                   |
       +---- corosync -----+---- corosync -----+   who is alive, who has quorum
       +---- Ceph ---------+---- Ceph ---------+   3 copies of every block,
                                                   ~47 GB usable

    guests live on 10.20.0.0/24, carried between nodes by VXLAN
       web1 on pve1      web2 on pve3      uptime kuma on pve2
       shared service address 10.20.0.50 floats between web1 and web2

       pbs
    2 vCPU / 4 GB       not a cluster member, storage of its own,
    50 GB backup disk   cluster account can write but not delete
  =================================================================
                                  |
                        Cloud NAT, outbound only
                                  |
                               internet
```

Four rented virtual machines standing in for four physical servers. Three form the
cluster. The fourth holds the backups and is deliberately kept out of it.

Software: Debian 13, Proxmox VE 9.2.20, Ceph 20.2.4, Proxmox Backup Server 4.2.6, all
from the no-subscription repositories.

The two lines the whole thing rests on:

```
Quorate:   Yes                          (pvecm status, 3 of 3 nodes voting)
health:    HEALTH_OK                    (ceph -s, 3 osds: 3 up, 3 in)
```

Full output in [`docs/06-cluster.txt`](docs/06-cluster.txt) and
[`docs/07-ceph.txt`](docs/07-ceph.txt).

---

## The decisions, and my reasoning

These are the choices that I had to take during the project. Each one had an alternative
I rejected for a reason I can state.

### Cloud instead of hardware

Doing this properly needs three physical servers. To be honest, I neither found them
affordable, nor enjoyed the idea of investing in something that was more of a plaything
or test than actually really needed. Renting three virtual ones is the affordable
substitute, and almost everything transfers: clustering, shared storage, failover and
backups behave the same way.

What it costs is an extra layer of virtualization. Proxmox is a hypervisor, and here it
runs inside a virtual machine, which only works if nested virtualization is explicitly
enabled on the instance. It also created a networking problem that real hardware would
not have, which is what the VXLAN section below is about.

Google Cloud rather than Azure: Azure's trial caps at 4 vCPUs for 30 days. Google gives
8 concurrent vCPUs for 90 days, which is exactly enough for this architecture and not a
single vCPU more.

### Sized backwards from the quota

8 vCPUs is the hard limit, so the design starts from there and works back: three nodes
at 2 vCPU each, plus 2 for the backup server. There is no room for a fifth machine.
That is why I checked capacity before building anything instead of discovering it
halfway through.

### No machine has a public address

None of the four machines can be reached from the internet. Administration goes through
an authenticated tunnel: Google checks who you are first, then forwards the connection
to a machine that has no address of its own to attack.

The obvious alternative is giving each machine a public IP. It costs about the same, but
a public address gets found by automated scanners within minutes of booting. With no
address there is nothing to find.

Outbound access still works, because package downloads need it. It goes through a gateway
that rewrites private addresses to one shared public one, and that only functions in one
direction: an unsolicited inbound packet matches no existing connection and is dropped.
That is structural, not a firewall rule somebody could misconfigure later.

### A custom network instead of the default one

Google creates a default network in every new project. It has subnets in 42 regions and
allows SSH from the entire internet, because it is built so that a beginner's first VM
just works.

The network here has one subnet, in one region, and three firewall rules that I wrote one
at a time, starting from deny-all.

### Ceph for shared storage, not periodic replication

The three nodes pool one 50 GB disk each. Every block is stored three times, once per
machine, so any single machine can vanish without losing data.

This matters a lot because it is what lets a guest run on any node. Moving a container
from one node to another took 5 seconds, since nothing had to be copied: the destination
could already read the disk. On local storage the same move means shipping the entire
disk across the network first.

The alternative I rejected is ZFS replication, which copies snapshots between nodes every
few minutes. It is simpler and lighter, and it would have worked, but a failure loses
everything written since the last sync. Ceph does not acknowledge a write until more than
one copy exists.

Ceph's price for that is storage: three copies means 150 GB of raw disk gives about 47 GB
of usable space, and it wants more RAM and more moving parts than ZFS replication does.
In this lab that was an acceptable trade, because the guests are small and the point was
the behaviour, not the capacity.

There is also a deliberate safety behaviour that kinda convinced me: if two of the three
machines are lost, Ceph stops accepting writes rather than carrying on with a single copy
and no redundancy. Data stays readable, and writes resume by themselves when a second
machine comes back. Refusing to write is the safer failure. Pretty good design, I'd say.

### VXLAN for guest networking

This was the most challenging constraint in the project for me, and it exists purely
because of the cloud.

An ordinary office network is switched: machines share a wire, and the switch learns about
whatever new device gets plugged in. Google's network is routed. Each machine sits alone
on its own address, and the router only accepts addresses Google itself handed out. A
container with its own address is simply dropped, because as far as Google is concerned
that address does not exist.

The fix wraps guest traffic inside ordinary node-to-node packets. Google sees pve1 talking
to pve2, which it allows. The receiving node unwraps the packet and hands it to the guest.
It rebuilds a switched network on top of a routed one, and the guests never know.

I did not build that by hand. Proxmox has this built in, as SDN: a VXLAN zone and a
virtual network inside it, configured from the web interface and applied to all nodes at
once. The work was understanding why it was needed and what it does, not writing it.

The alternative was telling Google's router about the guest addresses using custom routes.
Legitimate, free, and considerably simpler to set up. I rejected it because a route points
at one specific node, while HA and live migration move guests between nodes constantly, so
every failover would mean rewriting routes. The VXLAN approach also works identically on
real hardware, where Google's custom routes do not exist at all.

The catch it creates: the wrapping adds 50 bytes to every packet, so guests have to send
slightly smaller ones. Getting that wrong produces one of the most misleading failures in
networking, which is covered further down, and it cost me the single longest debugging
session of the whole build.

### The two shared addresses

Both the guest network's gateway and the web service sit behind shared addresses that any
node can hold. One holds it, the others watch, and if the holder goes quiet another claims
it in about a second. Nothing that uses the address has to be reconfigured.

Both are set not to take the address back when the failed machine returns. Reclaiming it
would cause a second interruption for no benefit at all. The cluster is configured the
same way for guests: once they have moved, they stay moved until somebody decides
otherwise.

### Backups on a separate machine, with restricted permissions

The backup server is not a cluster member and shares none of its storage.

The obvious objection is that Ceph already keeps three copies, so why bother. Well,
because replication is not backup. Deleting a container leads to the deletion being
faithfully replicated to all three copies within a second, therefore a bad configuration
change replicates just as fast, or worse, ransomware encrypts all three. Replication keeps
copies synced, which means it keeps mistakes and other unwanted events synced too. A
backup is well, a backup, always good to have a good, working, tested one.

The cluster connects to the backup server with an account that can create and read backups
but not delete them. If the cluster is compromised, the attacker can write new backups.
They cannot destroy the old ones.

### Daily administration through a named account

Day-to-day work goes through a named account with an administrator role rather than root.
A handful of operations genuinely need root and are done deliberately from the command
line when they come up.

---

## The backup test

The configured backups have to actually also be able to restore, not just exist there.

1. I wrote a marker file inside a running container: `restore test marker 2026-09-26`
2. Backed up the container
3. Removed it from cluster management, stopped it, and permanently destroyed it
4. Confirmed the destruction: its disk image was gone from Ceph, and the only remaining
   copy of that container existed on the backup server
5. Restored it: 658 MiB in 7.7 seconds
6. Read the marker file back, intact

The marker is what makes it a test rather than a demonstration. Without it, a "successful
restore" could just be a fresh container built from a template.

Deduplication, measured: a second backup of an unchanged container transferred 0 bytes and
the backup disk did not grow at all. The server already held every chunk of that data and
recorded a reference instead. The three container backups add up to about 2.3 GB of data
and take 837 MB on the backup server, because all three are the same Debian base. That is
the thing that makes daily backups affordable rather than a storage problem.

Verification involves therefore a scheduled job that re-reads every stored chunk and checks
it against its hash, which catches silent corruption while there is still time to do
something about it.

---

## Things that went wrong

These are in the repository on purpose.

### The MTU bug, and why it took so long to see

Symptom: from inside one container, ping worked, DNS worked, TCP connections opened, and
every actual download hung forever.

Cause: a container's network connection has two ends, one inside the container and one on
the node. Proxmox set the correct packet size on the node's end but never wrote it into
the container's own configuration, so the container kept using the standard size. Add the
50 bytes of VXLAN wrapping and full-size packets no longer fit through Google's network,
so they were silently dropped.

Small packets always fit. That is why everything looked healthy: ping is small, DNS is
small, and opening a TCP connection is small. Only the moment real data started flowing
did anything break.

Worse, it had been happening on every container since the beginning without anybody
noticing, because TCP responds to loss by retransmitting smaller and eventually getting
through. Transfers finished, they were just slow. An earlier container downloading at
174 kB/s had been blamed on something else entirely.

Fixed inside each container's own network configuration, and verified across a reboot.

### An hour lost to a hidden error message

The same container appeared unable to reach anything at all. I tested and discarded
several plausible theories along the way: that DNS was broken (it resolved names fine),
that the guest firewall was blocking outbound traffic (the firewall directory was empty),
that the container could not reach its gateway (ping to the gateway and to the other
containers worked), and that it was the MTU again (it was set wrong, but fixing it changed
nothing here).

The actual cause was that the diagnostic command itself was not installed, because a much
earlier step had failed. The error message saying exactly that was being thrown away by
`2>/dev/null` in every single test command I ran.

Lesson recorded in the docs: do not suppress error output while diagnosing a failure. The
hidden message was the answer the whole time.

### A storage quota that was checked, but the wrong one

I verified disk capacity before building. The build still failed partway through, because
SSD-backed disks and standard disks count against two separate quotas and I had only
looked at one. Fixed by moving the backup server to standard disks, which turned out to be
the better choice anyway: backups are sequential writes where latency does not matter.

### A staged rollout that was not staged

The guest network configuration is applied cluster-wide, but the command is run from a
single node. I ran it on pve1 first, expecting only pve1 to be reconfigured so I could
check the result before letting the other two follow. It reconfigured the network on all
three nodes at once.

Nothing broke, and I checked pve2 and pve3 before continuing. But I had assumed something
that did not exist, which could have been quite critical in a more realistic scenario.

### Others

- The Proxmox installer adds a repository that requires a paid subscription. Every
  `apt update` then fails with a 401 authentication error until that repository is
  disabled. The error blames authentication, not the missing license, so it reads like a
  broken login, which is not. The same thing happened again later on the backup server,
  under a different file name.
- Creating a Linux user on a node does not create a login for the Proxmox web interface.
  Proxmox keeps its own user database and only maps an account onto the Linux one if you
  tell it to. The password was correct and the login still failed with "authentication
  failure", which gives no hint that the account simply does not exist where it is being
  looked for.
- Disk names like `/dev/sda` and `/dev/sdb` are assigned in the order the kernel finds the
  disks, and that order is not always the same. Two machines created with the same command had
  their boot disk and data disk reversed, and one machine swapped them between reboots.
  Installing the bootloader to the wrong disk would have left the machine unbootable, so
  every disk operation in this project re-checks with `lsblk` immediately beforehand,
  in the same session.
- Rebooting a node triggered no failover at all, and that was correct. The cluster waits
  before declaring a node dead, because moving every guest for the sake of a 40-second
  reboot would cause more disruption than the reboot itself. Failover only starts once the
  node stays down. Watching nothing happen was the expected result, and it took a minute
  to be sure of that rather than assume something was broken.

---

## Repository layout

| Path | Contents |
|---|---|
| [`docs/`](docs/) | One document per phase: what was built, why, and what broke |
| [`evidence/`](evidence/) | Screenshots and captured command output |
| [`LAB_LOG.md`](LAB_LOG.md) | Running log kept throughout the build |
| [`scripts/`](scripts/) | Helper scripts |

The commit history runs across the whole build rather than arriving as one upload, so the
order the work happened in is visible.

---

## Limitations, and what a real deployment would do differently

This is a lab, and below is what separates it from something a real business would
actually need and use.

### It runs on a cloud, not on hardware

Proxmox is a hypervisor, and here it runs inside a virtual machine rather than on a
physical server. Nested virtualization makes that work, but it is a layer that would not
exist on real hardware, and it costs performance on anything CPU-bound.

The whole VXLAN requirement exists for the same reason: Google's network is routed rather
than switched, so guests cannot simply have addresses on the local network. On real
hardware with a real switch, none of the VXLAN or MTU work would be needed. Instead each
node gets a plain Linux bridge attached to its physical network card, the guests connect
to that bridge, and the switch learns their addresses by itself as soon as they send their
first packet. Guests take addresses from the same range as everything else on the LAN. If
you want them separated from the rest of the network you use VLANs, configured on the
switch. So the work does not disappear, it moves from the hypervisor to the network
hardware, where it is a well-trodden path and somebody else's job in most companies.

The bigger gap is in how the failures behave. Here a node "fails" because I told Google's
API to shut the instance down, which is clean and instant. Real hardware fails in messier
ways: a disk that gets slower for weeks before it dies, a network card that drops one
packet in a thousand, a power supply that browns out under load, a node that is alive
enough to answer heartbeats but too sick to serve anything. Those half-failures are harder
for a cluster to handle than a clean death, and I have not tested any of them.

Related: real clusters fence a misbehaving node by physically cutting its power through a
management card such as iDRAC or iLO, or through a switched power strip. This lab relies
on the software watchdog instead, which is what you use when no such hardware exists. It
works, but it is the fallback, not the real thing.

### Everything shares one network

Ceph replication traffic, corosync heartbeats and normal guest traffic all travel over the
same single network interface on each node, because that is all a cloud instance of this
size gives you.

That is not just untidy, it is a genuine failure mode. When a disk fails, Ceph starts
rebuilding the missing copies and that rebuild can saturate the link. Corosync heartbeats
are tiny but extremely time-sensitive. If they start arriving late, the cluster concludes
that a perfectly healthy node is dead and fences it, which means one failed disk turns
into a cluster incident. This is well known enough that corosync explicitly supports
multiple independent rings for exactly this reason.


A production build separates them: a dedicated network for Ceph replication (usually 10 Gb
or better, often two bonded links), at least one dedicated corosync ring on its own
interface with a second ring as backup, and a separate network for guest traffic. Three to
five interfaces per node rather than one. It never bit me here because the lab is small and
mostly idle. Under real load it would.

### No real certificates

The web interfaces use the self-signed certificate Proxmox generates during installation,
so the browser shows a warning and you click through it every time.

Two problems with that. The small one is that it makes certificate warnings to be ignored,
which is never the case, or advisable, in real life. The large one is the obvious one
that a self-signed certificate cannot tell you whether you are actually talking to your
server and anyone able to intercept the connection can present their own self-signed
certificate and it will look just as legitimate as the real one. So yeah, not great at all.

The well-known, obvious theory says: "a real deployment goes one of two ways. Either an
internal certificate authority issues certificates for the internal hostnames and the CA
root is distributed to every admin machine, or it uses Let's Encrypt through Proxmox's
built-in ACME client with a DNS-01 challenge, which is the variant that works for hosts
with no public address. Proxmox then renews them automatically. Either way the warning
disappears, and a warning appearing again becomes information rather than background
noise."

### Monitoring

Uptime Kuma runs in a container on the cluster it is watching. It produced good evidence
during the failover test, but only because that failure was partial. If the cluster went
down completely, the monitoring would go down with it and report nothing.

It is also only up/down monitoring. It can answer "is it responding right now" and nothing
else. It cannot tell you that Ceph write latency has been creeping upwards for three weeks,
or that a disk's error counter has started climbing, or that memory usage crosses 90% every
night at the same time. Those are the signals that let you fix something before it becomes
an outage.

A realistic setup puts the monitoring outside the failure domain, on a separate host or a
hosted service, and collects metrics rather than just availability: node_exporter and the
Ceph exporter feeding Prometheus, dashboards in Grafana, and enough retention to compare
this month against last month. Uptime Kuma is then still useful, as the external check that
confirms the service answers from outside.

### Alerts that reach nobody

Proxmox and the backup server are configured to send notification mail, but there is no
mail relay, so the messages go to the local machine and sit there. Functionally, nobody is
told anything.

For backups specifically this is the dangerous one. A backup job that silently stops running
is worse than having no backups at all, because you believe you are covered and behave
accordingly. The whole point of the verify job is to catch corruption early, and a verify
job whose failures nobody reads has no point.

A real deployment configures an SMTP relay or a webhook to somewhere people actually look,
and defines what is worth waking somebody up for: Ceph health not OK, a node leaving the
quorum, a backup job failing or not running at all, a verify job finding a bad chunk, a
datastore crossing a fill threshold. Then it splits those between "email someone tomorrow"
and "phone someone now", with an on-call rotation and an escalation path behind it. And
then, the step that gets skipped most often, it tests the alerts by deliberately breaking
something and checking that the message actually arrives.

### Smaller ones, stated plainly

- Four failover types were measured. Each was measured once. These are single results, not
  statistics, and a proper characterisation would run each one repeatedly and report the
  spread.
- The cluster tolerates one node failing, not two. With two gone there is no quorum and
  Ceph stops accepting writes. That is the correct behaviour for three nodes, but it means
  the honest claim is "survives one failure", not "highly available" in the abstract.
- 8 GB of RAM per node is modest for Ceph, which asks for about 4 GB per OSD by default
  before anything else runs. It is fine at this scale and would not be at a larger one.
- The backups live on one machine in the same region as the cluster. A region-wide problem
  takes the cluster and the backups together. The common rule of thumb is three copies, two
  kinds of media, one of them off site, and this setup satisfies none of the three.
- The guests are small and idle, so Ceph was never put under real load. Recovery timings
  measured on an idle cluster are optimistic.
- Security stops at the basics: no public addresses, deny-all firewall, a named admin
  account, restricted backup permissions. No two-factor authentication, no centralised
  identity, no audit log shipping, no host hardening beyond the defaults.

---

## Running cost

Built entirely inside Google Cloud's free trial, at no cost. The billed total across the
build was €40.60, covered in full by trial credit, leaving €218 of the original €257.

That figure is low because every machine was shut down at the end of each working session.
Left running around the clock, four instances of this size cost roughly €9 a day, which
would have swallowed the whole trial credit in about a month and ended the project early.
Compute is billed per second while an instance runs and that charge stops when it stops,
while the disks keep costing a small amount whether the machines are on or off, which is
why the total is not zero.

Budget alerts were configured before the first resource was created rather than after the
first surprise.
