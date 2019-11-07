#The Link Aggregation Control Plane

A number of components are involved in generating and handling control
(netlink) messages related to LAG/bonding interfaces.

* kernel - net/core
* kernel - team modules
* teamd - libteam
* teamd - vplane link watcher
* vplaned - vyatta controller
* dataplane

The Linux kernel is treated as two pieces here because there are two
distinct types of netlink messages related to team interfaces:
NETLINK_ROUTE and team-specific NETLINK_GENERIC.

##How LAG/bonding/team interfaces differ

LAG interfaces in the vRouter are somewhat different from what we usually
refer to as "dataplane" interfaces in that they are not created by the
dataplane in response to hardware discovered by DPDK.
Instead, the dataplane creates a DPDK bonding "port" in response to an
RTM_NEWLINK netlink message.

One side effect of this is LAG interfaces have no shadows in the
dataplane.
The kernel has already created a logical ethernet device that can,
for example, have addresses assigned.
Slave interfaces in that aggregation must be "dataplane" interfaces,
which already have shadows and this is still how slow-path traffic is
sent to/from the kernel for that particular aggregation.

LAG interfaces differ from other logical interfaces (l2tp tunnels,
for example) because the DPDK has a bonding Poll Mode Driver (PMD).
As a result, LAG interfaces can be treated much like any of the discovered
hardware interfaces and packet filtering, QoS, etc. can identify
these interfaces by a DPDK port number and require very little (or no)
modification to work.

##Control Flow

The large number of components involved makes the processing of netlink
messages for LAG interfaces less than straightforward.

![Fig. 1](control-flow-fig1.svg)

### Master interface creation

Starting teamd will send an RTM_NEWLINK message to the kernel with the
IFLA_INFO_KIND attribute set to "team".
This will trigger the creation of a new interface by the team kernel module.
When complete, the kernel will respond by multicasting the RTM_NEWLINK
message which the controller receives and forwards to the dataplane for
processing.

Teamd will follow this with additional messages sent to the kernel that
set the master's MAC address and some team genetlink options list
messages (TEAM_ATTR_LIST_OPTION) to set the LAG mode, hash function, etc.
All of these are, if successful, echoed by the kernel as multicast
messages which the controller also receives and forwards to the dataplane.

### Slave interface addition/removal

In the vRouter these events are triggered with the "ip link set
... [no]master" commands which generate the appropriate RTM_NEWLINK
messages.

After the team kernel module notifies the team daemon that one or more
slaves have been added by sending a team genetlink message containing
a port list (TEAM_ATTR_LIST_PORT).
The dataplane also receives these messages from the controller and
these port lists, instead of the RTM_{NEW,DEL}LINK messages, trigger slave
addition/removal in the bonding driver.
Although the controller has no way to enforce a particular message
ordering of a mixture of RTM_{NEW,DEL}LINK and team genetlink messages (they
arrive on different sockets), the order of team genetlink messages on
their own is preserved.
This is the reason that port lists are used to add slaves; when using
port lists for this a slave is guaranteed to be added before any options,
such as "enabled", are applied to it AND it is guaranteed that no options
will be applied after the slave is removed.
No options are inadvertantly discarded for lack of a target slave device.

### Slave Interface Link State Change

When a change in link state occurs, the slave interface raises an
interrupt which is signaled to the dataplane through an eventfd.
There are _two_ watchers of these events in the dataplane.

1. The dataplane application always looks for link state change (LSC) events
and sends a LINKUP or LINKDOWN message to the vyatta controller, vplaned,
when such a change is noticed.
vplaned, in turn, updates the kernel using the ethtool API.
The team kernel module registers to receive such notifications from the ethtool
subsystem.

    * When the team kernel module detects a link change (speed, carrier or duplex) it
    sends an updated port list genetlink message.
    Teamd updates it's internal interface information with the contents of the portlist.
    * The kernel also reacts to link state changes received this way by sending an
    updated RTM_NEWLINK message with the appropriate flags set.
    Teamd has a link watcher that connects to the vyatta controller and
    subscribes to the "link" topic.
    As a result, the RTM_NEWLINK messages are forwarded to teamd and it uses the
    IFF_RUNNING flag to determine if carrier is present.
    * A change to the link state noticed by teamd's vplane link watcher
    will cause it to issue a team attribute list genetlink message with an
    updated "enabled" option.
    When the lacp runner is used, the enabled flag is also gated by the MUX
    state machine.
    The controller sees the kernel's response to this attribute list message
    and forwards it to the dataplane which sets the DPDK bonding driver's MUX
    s.m. flags (distributing and collecting) based on the value.

1. The DPDK bonding driver also registers a callback for LSC notifications.
Link state determines which slave interfaces are active, and therefor
which interfaces are used for transmit.
This means that the bonding driver _does not wait for the RTM_NEWLINK
notification without IFF_RUNNING_ to stop using a down interface.

