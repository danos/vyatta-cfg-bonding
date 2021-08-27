# Copyright (c) 2021, AT&T Intellectual Property. All rights reserved.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only

package Vyatta::Interface;

sub new {
	my $self = {};
	bless $self;
	return $self;
}

sub up {
	my $self = shift;

	return 0;
}

1;
