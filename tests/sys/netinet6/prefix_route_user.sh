#!/usr/bin/env atf-sh
#-
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2020 Alexander V. Chernikov
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $FreeBSD
#

. $(atf_get_srcdir)/../common/vnet.subr

atf_test_case "prefix_route_user" "cleanup"
prefix_route_user_head() {

	atf_set descr 'Test prefix route addition from userland'
	atf_set require.user root
}

prefix_route_user_body() {

	ids=65529
	id=`printf "%x" ${ids}`
	if [ $$ -gt 65535 ]; then
		xl=`printf "%x" $(($$ - 65535))`
		yl="1"
	else
		xl=`printf "%x" $$`
		yl=""
	fi

	vnet_init

	ip6a="2001:db8:6666:0000:${yl}:${id}:1:${xl}"
	ip6b="2001:db8:6666:0000:${yl}:${id}:2:${xl}"

	net6="2001:db8:6667::/64"
	dst_addr6=`echo ${net6} | awk -F/ '{printf"%s4242", $1}'`

	epair=$(vnet_mkepair)
	ifconfig ${epair}a up
	ifconfig ${epair}a inet6 ${ip6a}/64

	jname="v6t-${id}-${yl}-${xl}"
	vnet_mkjail ${jname} ${epair}b
	jexec ${jname} ifconfig ${epair}b up
	jexec ${jname} ifconfig ${epair}b inet6 ${ip6b}/64

	# setup interface prefix
	jexec ${jname} route add -6 -net ${net6} -iface ${epair}b

	# wait for DAD to complete
	while [ `jexec ${jname} ifconfig ${epair}b inet6 | grep -c tentative` -ne "0" ] ; do
		sleep 0.2
	done

	# run ping6 to initiate ND entry creation
	atf_check -s exit:2 -o ignore jexec ${jname} ping6 -c1 -X1 ${dst_addr6}

	# Verify entry got created
	count=`jexec ${jname} ndp -an | grep ${epair}b | grep -c ${dst_addr6}`
	atf_check_equal "1" "${count}"
}

prefix_route_user_cleanup() {

	vnet_cleanup
}

atf_init_test_cases()
{

	atf_add_test_case "prefix_route_user"
}

# end

