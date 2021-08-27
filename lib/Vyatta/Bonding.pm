# Copyright (c) 2019-2021, AT&T Intellectual Property. All rights reserved.
# Copyright (c) 2014 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: LGPL-2.1-only

package Vyatta::Bonding;

use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::Configd;
use Vyatta::Interface;
use JSON qw(decode_json to_json);
use IPC::System::Simple qw(capture EXIT_ANY);
use Data::Dumper;
use vci;

use strict;
use warnings;

our(@EXPORT, @ISA);

BEGIN {
    require Exporter;
    @ISA = qw(Exporter);
    @EXPORT = qw(get_bonding_modes kill_daemon start_daemon get_members
                 set_primary set_priority add_member remove_member if_down if_up
                 get_lacp_details get_lacpdu_info_state get_mode get_selected
                 have_all_default_values reset_mac get_configured_members);
}

my $TEAMD_BIN = "/usr/bin/teamd";


sub is_hardware_qos_bond_enabled {
    my $feature_marker =
       "/run/vyatta-platform/features/vyatta-interfaces-bonding-v1/hardware-qos-bond";

    return -e $feature_marker;
}

my %BONDING_MODES = (
    "active-backup"         => "activebackup",
    "802.3ad"               => "lacp",
    "lacp"                  => "lacp",
    "balanced"              => "loadbalance",
);

sub get_bonding_modes {
    return keys %BONDING_MODES;
}

my %HASH_POLICIES = (
    "layer2"                => [ "eth" ],
    "layer2+3"              => [ "eth", "ip" ],
    "layer3+4"              => [ "ip", "udp" ],
);


sub generate_notification {
    my $config = Vyatta::Configd::Client->new();
    die "Unable to connect to the Vyatta Configuration Daemon"
        unless defined($config);

    my $phys_tree = $config->tree_get_hash( "interfaces dataplane",
            { 'database' => $Vyatta::Configd::Client::AUTO });

    my $bonding_tree = $config->tree_get_hash( "interfaces bonding",
            { 'database' => $Vyatta::Configd::Client::AUTO });
    my @bond_groups;

    # Following loop will construct bond groups and corresponding
    # bond members

    foreach my $bond_intf ( @{ $bonding_tree->{'bonding'} } ) {
        my $bondgroup = $bond_intf->{'tagnode'};
        my @members = ();

        foreach my $dataplane_intf ( @{ $phys_tree->{'dataplane'} } ) {
            if ($dataplane_intf->{'bond-group'}) {
                if ($bondgroup eq $dataplane_intf->{'bond-group'})  {
                    push @members, $dataplane_intf->{'tagnode'};
                }
            }
        }
        if (scalar(@members)) {
            push @bond_groups,
                 {'bond-group' => $bondgroup,
                     'bond-members' => \@members};
        }

    }

    # Generate notifications
    my $client = vci::Client->new();

    $client->emit("vyatta-interfaces-bonding-v1", "bond-membership-update",
            {'bond-groups' => \@bond_groups});


}

sub is_bond_intf {
    my ( $name ) = @_;

    if ($name =~ /bond\d+/) {
        return 1;
    }
    return 0;
}

sub kill_daemon {
    my ( $intf ) = @_;

    my @cmd = ("$TEAMD_BIN", "--team-dev", "$intf", "--check");
    system(@cmd)
	and return;

    @cmd = ("$TEAMD_BIN", "--team-dev", "$intf", "--kill");
    system(@cmd)
	and die "$intf: Cannot stop daemon: $!\n";
}

sub start_daemon {
    my ( $intf, $mode, $hash, $lacp_options ) = @_;

    my $val = $BONDING_MODES{$mode};
    die "$intf: Unknown bonding mode: $mode\n" unless defined($val);

    my $policy = $HASH_POLICIES{$hash};
    die "$intf: Unknown hash policy: $hash\n" unless defined($policy);

    kill_daemon($intf);

    die "$intf: not a bonded interface\n"
      if !is_bond_intf($intf);

    my %teamd_config = ();
    $teamd_config{'runner'}{'name'} = "$val";
    $teamd_config{'runner'}{'tx_hash'} = $policy
        if (("$val" eq 'lacp') || ("$val" eq 'balanced'));
    $teamd_config{'runner'}{'active'} = JSON::false
        if ( $val eq 'lacp' and $lacp_options->{activity} eq 'passive' );
    if ($val eq 'lacp' and $lacp_options->{rate}) {
        if ($lacp_options->{rate} eq 'fast') {
            $teamd_config{'runner'}{'fast_rate'} = JSON::true;
        } else {
            $teamd_config{'runner'}{'fast_rate'} = JSON::false;
        }
    }
    $teamd_config{'runner'}{'lacp_key'} = int($lacp_options->{key})
        if ( $val eq 'lacp' and $lacp_options->{key});
    $teamd_config{'runner'}{'min_ports'} = int($lacp_options->{minlinks})
        if ( $val eq 'lacp' and $lacp_options->{minlinks});
    $teamd_config{'runner'}{'hwaddr_policy'} = 'only_active'
        if ( $val eq 'activebackup' );
    $teamd_config{'link_watch'}{'name'} = 'ethtool';

    my $json = JSON->new();
    $json->canonical();
    my $teamd_config = $json->encode(\%teamd_config);
    my @cmd = ("$TEAMD_BIN", "--team-dev", "$intf", "--daemon",
	    "--no-quit-destroy", "--take-over",
	    "--config", "$teamd_config");
    system(@cmd) and die "$intf: Cannot set mode $val: $!\n";
    1;
}

sub get_configured_members {
    my ( $intf ) = @_;

    my @members = ();
    my $config = Vyatta::Configd::Client->new();
    my $dp_intfs = $config->tree_get_hash( "interfaces dataplane",
            { 'database' => $Vyatta::Configd::Client::AUTO });
    foreach my $dp_intf ( @{ $dp_intfs->{'dataplane'} } ) {
        if ($dp_intf->{'bond-group'}) {
            if ($intf eq $dp_intf->{'bond-group'})  {
                push @members, $dp_intf->{'tagnode'};
            }
        }
    }
    return @members;
}

sub get_members {
    my ( $intf ) = @_;

    my $json =
      capture( EXIT_ANY, "teamdctl $intf config dump actual 2>/dev/null" );
    die "$intf: Cannot get members $!\n" if ( $? != 0 );

    my $decoded = decode_json($json);
    my $ports = $decoded->{'ports'};
    my @ports = ();
    push(@ports, keys %{ $ports }) if defined $ports;
    return @ports;
}

sub get_mode {
    my ( $intf ) = @_;

    my $json =
      capture( EXIT_ANY, "teamdctl $intf config dump actual 2>/dev/null" );
    die "$intf: Cannot get configuration: $!\n" if ( $? != 0 );

    my $decoded = decode_json($json);
    my $runner = $decoded->{'runner'};
    die "$intf: Cannot get mode" if ! defined $runner;
    return $runner->{'name'};
}

sub get_selected {
    my ( $intf ) = @_;

    my $json = capture( EXIT_ANY, "teamdctl $intf state dump 2>/dev/null" );
    die "$intf: Cannot get state: $!\n" if ( $? != 0 );

    my $decoded = decode_json($json);
    my $active_port = $decoded->{'runner'}->{'active_port'};
    my $ports = $decoded->{'ports'};
    my @ports = ();

    push (@ports, $active_port)
        if ( defined ( $active_port ) );
    foreach my $p ( keys %{ $ports } ) {
        push (@ports, $p) if ($ports->{$p}->{'runner'}->{'selected'});
    }
    if ( get_mode($intf) eq 'loadbalance' ) {
        foreach my $p ( keys %{ $ports } ) {
            push (@ports, $p) if ($ports->{$p}->{'link_watches'}->{'up'});
        }
    }
    return @ports;
}

sub get_lacp_details {
    my ( $intf ) = @_;

    my $json = capture( EXIT_ANY, "teamdctl $intf state dump 2>/dev/null" );
    die "$intf: Cannot get state: $!\n" if ( $? != 0 );

    my %lacpdu_infos = ();
    my $decoded = decode_json($json);
    my $ports = $decoded->{'ports'};
    if ($ports) {
        %lacpdu_infos = map {
            my $h = ${$ports}{$_}->{'runner'}->{'actor_lacpdu_info'};
            $h ? ($_, $h) : ()
        } keys %{ $ports };
    }
    return %lacpdu_infos;
}

sub lacpdu_info_state2strs {
    my ($state) = @_;
    my @states_str = (
        "ACTIVITY",
        "TIMEOUT",
        "AGGREGATION",
        "SYNCHRONIZATION",
        "COLLECTING",
        "DISTRIBUTING",
        "DEFAULTED",
        "EXPIRED"
    );

    return map { $state & (1<<$_) ? $states_str[$_] : () } 0 .. $#states_str;
}

sub get_lacpdu_info_state {
    my ($state) = @_;

    return "N/A"
      if !defined($state);

    # mask DEFAULTED from array of states and print "*" instead
    my $defaulted = ($state & 0x40) ? "*" : "";
    $state &= ~0x40;

    my @str = ( "", lacpdu_info_state2strs($state) );
    return $defaulted . $str[-1];
}

sub set_primary {
    my ( $intf, $port ) = @_;
    system("teamdctl $intf state item set runner.active_port $port")
	and die "$intf: Cannot set active port $port: $!\n";
}

sub set_priority {
    my ( $intf, $port, $priority ) = @_;
    $priority //= 0;
    system("teamnl -p $port $intf setoption priority $priority")
        and die "$intf: Cannot update configuration of port $port: $!\n";
}

sub add_member {
    my ( $intf, $member ) = @_;

    my $memberif = new Vyatta::Interface($member);
    my $isup = $memberif->up();

    # Interface must be down to add to a bond group.
    if_down($member) if ( $isup );
    system("ip link set dev $member master $intf")
	and die "$intf: Cannot add $member: $!\n";
    # Restore the previous state.
    if_up($member) if ( $isup );

    if (is_hardware_qos_bond_enabled()) {
       # Generating notification for the application interested
       generate_notification();
    }
}

sub remove_member {
    my ( $intf, $member ) = @_;
    system("ip link set dev $member nomaster")
	and die "$intf: Cannot remove $member: $!\n";
    if (is_hardware_qos_bond_enabled()) {
        # Generating notification for the application interested
        generate_notification();
    }
}

sub if_down {
    my $intf = shift;
    system "ip link set dev $intf down"
      and die "$intf: Cannot set device down: $!\n";
}

sub if_up {
    my $intf = shift;
    system "ip link set dev $intf up"
      and die "$intf: Cannot set device up: $!\n";
}

sub get_default_value {
    my ( $cfg, $path ) = @_;

    return $cfg->{_cstore}->cfgPathDefault($cfg->get_path_comps($path), undef);
}

# Check leaf nodes in a config tree for default values.
sub have_all_default_values {
    my ( $cfg, $where ) = @_;

    # Assume an empty container has presence.  getNodeType() will return
    # a type even if the node doesn't exist,  so check first.
    if ( $cfg->exists($where) and
         $cfg->getNodeType($where) eq 'container' ) {
        return 0
          if ( scalar $cfg->listNodes($where) == 0 );
    } elsif ( $cfg->exists($where) and
              $cfg->getNodeType($where) eq 'leaf' ) {
        return 0
          if ( !$cfg->isDefault($where) or
             !defined(get_default_value($cfg, $where)));

        return 1;
    }

    foreach my $node ( $cfg->listNodes($where) ) {
        my $path = $where . " " . $node;

	# ignore tag nodes for now
        next
          if $cfg->isTagNode($path);

        return 0
          if ( !have_all_default_values($cfg, $path));
    }
    return 1;
}

sub reset_mac {
    my $intf = shift;
    die "$intf: not a bonded interface\n"
      if !is_bond_intf($intf);

    my @members = get_configured_members($intf);

    if (@members) {
        my $member = shift @members;
        my $json = capture('ethtool', '-P', $member);
        die "$intf: Cannot get $member mac: $!\n" if ( $? != 0 );
        my $member_mac = (split ' ', capture('ethtool', '-P', $member))[2];

        system("ip link set dev $intf address $member_mac")
        and die "$intf: Cannot reset $intf mac: $!";
    }
}

1;
