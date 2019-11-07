dnl Copyright (c) 2019, AT&T Intellectual Property.  All rights reserved.
dnl
dnl SPDX-License-Identifier: GPL-2.0-only
dnl
# Process this file with autoconf to produce a configure script.

m4_define([PACKAGE_ID], [m4_esyscmd([
	if test -f debian/changelog ; then
	    dpkg-parsechangelog | sed -n 's/^Source: //p' | tr -d \\n
	else
	    echo -n unknown
	fi])])
m4_define([VERSION_ID], [m4_esyscmd([
	if test -f debian/changelog ; then
	    dpkg-parsechangelog | sed -n 's/^Version: //p' | tr -d \\n
	else
	    echo -n 0.0
	fi])])

AC_PREREQ(2.62)
AC_INIT([PACKAGE_ID], [VERSION_ID], [DL-vyatta-help@att.com])

AC_CONFIG_AUX_DIR([config])
AM_INIT_AUTOMAKE([1.11.1 foreign no-dist-gzip dist-bzip2 subdir-objects parallel-tests])
AC_PREFIX_DEFAULT([/opt/vyatta])

AC_ARG_ENABLE([nostrip],
	AC_HELP_STRING([--enable-nostrip],
	[include -nostrip option during packaging]),
	[NOSTRIP=-nostrip], [NOSTRIP=])
AC_SUBST(NOSTRIP)


AC_PROG_CC
AC_PROG_CXX
AM_PROG_AS
AM_PROG_CC_C_O

AC_PATH_PROG([PERL], [perl -v])

AC_CONFIG_FILES(
  [Makefile tests/Makefile])

AC_OUTPUT
