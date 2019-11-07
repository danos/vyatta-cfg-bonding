This package has the Vyatta configuration and operational templates and scripts for interface link aggregation.

LACP over Open vSwitch
======================

Example topology:

    +---------+      +------+      +---------+
    |         +------+ovsbr0+------+         |
    |         |      +------+      |         |
    |  DUT1   |                    |  DUT 2  |
    |         |      +------+      |         |
    |         +------+ovsbr1+------+         |
    +---------+      +------+      +---------+

By default the bridge is not forwarding LACP traffic. This can be enabled with
the following command:

    ovs-vsctl set bridge bond1-ovsbr0 other-config:forward-bpdu=true


For more information about Open vSwitch with libvirt see [INSTALL.Libvirt].

[INSTALL.Libvirt]: http://docs.openvswitch.org/en/latest/howto/libvirt "How to Use Open vSwitch with Libvirt"


Debugging LACP
==============

Daemon Output
-------------

The teamd output is logged via syslog if not started in foreground. The
messages are written to `/var/log/messages` if the
`/etc/rsyslog.d/vyatta-teamd.conf` exists with following content:

    # let teamd's debug output go into global too
    if $programname startswith 'teamd' then :omfile:$global

After creation the rsyslog service needs to be restarted.

To increase the debug level for team interface dp0bond0 after teamd
has started:

    sudo teamdctl dp0bond0 state item set setup.debug_level 1

Wireshark
---------

To capture the LACP traffic on the slave interfaces either use tshark on
the vRouter itself or wireshark on the (virtual) host interfaces:

    # tshark -i dp0s7 -V ether dst 01:80:c2:00:00:02
