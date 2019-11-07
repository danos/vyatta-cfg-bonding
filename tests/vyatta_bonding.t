#!/usr/bin/perl -w -I ../lib

# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
# Copyright (c) 2014 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use warnings 'all';

use Test::More 'no_plan';  # or use Test::More 'no_plan';

use IPC::System::Simple;

use_ok('Vyatta::Bonding');

our $current_cmd = sub { diag( explain( \@_ ) ); return 0; };

sub mock_helper {
    $current_cmd->(@_)
};

sub _transmogrify_to_code {
    my ( $val, $orig ) = @_;
    return $val if ref($val) eq 'CODE';

    return sub {
        if ( exists $val->{ $_[0] } ) {
            return $val->{ $_[0] }->(@_);
        }
        else {
            goto &$orig;
        }
    };
}

BEGIN {
    *CORE::GLOBAL::readpipe = _transmogrify_to_code(\&mock_helper,
						    \&CORE::readpipe);
    *CORE::GLOBAL::system = _transmogrify_to_code(\&mock_helper,
						  \&CORE::system);
    *IPC::System::Simple::capture = _transmogrify_to_code(\&mock_helper,
						  \&IPC::System::Simple::capture);
}


our %mock_cmds = ();

sub mock_init {
    $mock_cmds{'index'} = 0;
    $mock_cmds{'text'} = ();
    $mock_cmds{'cmd'} = ();
    return %mock_cmds;
}

sub mock_readpipe {
    my $mock_index = $mock_cmds{'index'}++;
    $mock_cmds{'cmd'}[$mock_index] = "@_";
    my $ret = $mock_cmds{'text'}[$mock_index];
    wantarray ? ( $ret ) : $ret;
}

{
    local $current_cmd = sub {
	return qq({
    "device": "dp0bond0",
    "runner": {
        "active": true,
        "controller": "ipc:///var/run/vyatta/vplaned.pub",
        "name": "lacp",
        "tx_hash": [
            "eth",
            "ipv4",
            "ipv6"
        ]
    }
});
    };

    my @got = get_slaves('dp0bond0');
    is(scalar @got, 0, "empty get_slaves() returns zero");
}

{
    local $current_cmd = sub {
	return qq({
    "device": "dp0bond0",
    "ports": {
       "dp0p5p1": {
            "link_watch": {
                "name": "ethtool"
            }
        },
        "dp0port1": {
            "link_watch": {
                "name": "ethtool"
            }
        }
    },
    "runner": {
        "active": true,
        "controller": "ipc:///var/run/vyatta/vplaned.pub",
        "name": "lacp",
        "tx_hash": [
            "eth",
            "ipv4",
            "ipv6"
        ]
    }
});
    };

    my @got = get_slaves('dp0bond0');
    my @expected = ('dp0p5p1', 'dp0port1');
    is_deeply([sort @got], [sort @expected],
	      "get_slaves() returns the correct slaves");
}

{
    local %mock_cmds = mock_init();
    local $current_cmd = \&mock_readpipe;

    push(@{$mock_cmds{'text'}}, qq(0));
    push(@{$mock_cmds{'text'}}, qq(0));

    ok(start_daemon('dp0bond0', 'lacp', 'layer2',
                    { activity => 'active', key => '0' }));
    is($mock_cmds{'index'}, 3);
    ok($mock_cmds{'cmd'}[2] eq '/usr/bin/teamd --team-dev dp0bond0 --daemon --no-quit-destroy --take-over --config {"link_watch":{"name":"vplane"},"runner":{"controller":"ipc:///var/run/vyatta/vplaned.pub","name":"lacp","tx_hash":["eth"]}}');
}

{
    local $current_cmd = sub {
	return qq({
    "device": "dp0bond0",
    "runner": {
        "active": true,
        "controller": "ipc:///var/run/vyatta/vplaned.pub",
        "name": "lacp",
        "tx_hash": [
            "eth",
            "ipv4",
            "ipv6"
        ]
    }
});
    };

    my %got = get_lacp_details('dp0bond0');
    my %expected = ();
    is_deeply(\%got, \%expected,
	      "get_lacp_details() returns empty hash");

    $current_cmd = sub {
	return qq({
    "device": "dp0bond0",
    "ports": {
       "dp0p5p1": {
            "link_watch": {
                "name": "ethtool"
            },
            "runner": {
                "actor_lacpdu_info": {
                    "port": 7,
                    "state": 113
                }
            }
        },
        "dp0port1": {
            "link_watch": {
                "name": "ethtool"
            },
            "runner": {
                "actor_lacpdu_info": {
                    "port": 8,
                    "state": 61
                }
            }
        }
    },
    "runner": {
        "active": true,
        "controller": "ipc:///var/run/vyatta/vplaned.pub",
        "name": "lacp",
        "tx_hash": [
            "eth",
            "ipv4",
            "ipv6"
        ]
    }
});
    };

    %got = get_lacp_details('dp0bond0');
    %expected = (
        'dp0p5p1' => { 'state' => 113,
                       'port' => 7 },
        'dp0port1' => { 'port' => 8,
                        'state' => 61 }
    );
    is_deeply(\%got, \%expected,
	      "get_lacp_details() returns the lacp details");
}

is (get_lacpdu_info_state(0), "",
    "get_lacpdu_info_state(0) is empty string");
is (get_lacpdu_info_state(113), "*DISTRIBUTING",
    "get_lacpdu_info_state(113) is DISTRIBUTING (defaulted)");
is (get_lacpdu_info_state(61), "DISTRIBUTING",
    "get_lacpdu_info_state(61) is DISTRIBUTING (not defaulted)");
is (get_lacpdu_info_state(29), "COLLECTING",
    "get_lacpdu_info_state(29) is COLLECTING (not defaulted)");

{

    *Vyatta::Bonding::get_default_value = sub {
        return 1;
    };

    sub Config::new {
        my ($class, @leaves) = @_;
        my $self = {};
        bless( $self, $class );

        $self->{leaves} = \@leaves;
        return $self;
    }

    sub Config::listNodes {
        my ($self, $where) = @_;
        return @{$self->{leaves}};
    }

    sub Config::exists {
        return;
    }

    sub Config::isTagNode {
	return;
    }

    sub Config::getNodeType {
        return 'container';
    }

    sub Config::isDefault {
        return;
    }


    #
    # First have_all_default_values test
    # sub-tree does not exist (ipv6, for example)
    #

    my $cfg = Config->new( () );

    is (have_all_default_values($cfg, 'ipv6'), 1,
        "container does not exist or has only default values");


    #
    # Second test -- sub-tree exists and is empty
    # (empty container)
    #

    *Config::exists = sub {
        return 1;
    };

    is (have_all_default_values($cfg, 'ipv6'), 0,
        "container exists and is empty");

    #
    # Third test -- sub-tree exists and is not empty with non-default value
    #

    *Config::getNodeType = sub {
        my ($self, $where) = @_;
        if ( $where eq 'ip' ) {
            return 'container';
        }
        return 'leaf';
    };

    $cfg = Config->new( ( 'rpf-check', 'gratuitous-arp-count' ) );

    is (have_all_default_values($cfg, 'ip'), 0,
        "container exists and has non-default value");

    #
    # Fourth test -- sub-tree exists and is not empty with default values
    #

    *Config::isDefault = sub {
        return 1;
    };

    is (have_all_default_values($cfg, 'ip'), 1,
        "container exists and has default values");
}
