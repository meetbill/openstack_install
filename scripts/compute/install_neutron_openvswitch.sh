#!/bin/bash
#########################################################################
# File Name: environment.sh
# Author: meetbill
# mail: meetbill@163.com
# Created Time: 2017-07-17 19:05:07
# Install neutron openvswitch script
#########################################################################

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

if [[ -f /etc/openstack-control-script-config/main-config.rc ]]
then
	source /etc/openstack-control-script-config/main-config.rc
else
	echo "### Can't access my config file. Aborting !"
	echo ""
	exit 0
fi

if [[ -f /etc/openstack-control-script-config/neutron-openvswitch-$1-installed ]]
then
	echo ""
	echo "### This module was already completed. Exiting !"
	echo ""
	exit 0
fi

install_configure_neutron()
{
	echo ""
	echo "### 1. Install Neutron Packages and Configure Neutron configs"
	echo ""
	yum install -y openstack-neutron-openvswitch ebtables ipset

	cat << EOF >> /etc/sysctl.conf
net.ipv4.ip_nonlocal_bind = 1
net.ipv4.tcp_keepalive_time = 6
net.ipv4.tcp_keepalive_intvl = 3
net.ipv4.tcp_keepalive_probes = 6
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.netfilter.nf_conntrack_max = 4000000
EOF
sysctl -p

	crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
	crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
	crudini --set /etc/neutron/neutron.conf DEFAULT rpc_backend rabbit

	crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp

	#
	# Neutron Keystone Config
	#
	crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_uri http://$CONTROLLER_NODES:5000
	crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://$CONTROLLER_NODES:35357
	crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
	crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers $CONTROLLER_NODES:11211
	crudini --set /etc/neutron/neutron.conf keystone_authtoken project_domain_name default
	crudini --set /etc/neutron/neutron.conf keystone_authtoken user_domain_name default
	crudini --set /etc/neutron/neutron.conf keystone_authtoken project_name service
	crudini --set /etc/neutron/neutron.conf keystone_authtoken username $NEUTRON_USER
	crudini --set /etc/neutron/neutron.conf keystone_authtoken password $NEUTRON_PASS

	crudini --del /etc/neutron/neutron.conf keystone_authtoken identity_uri
	crudini --del /etc/neutron/neutron.conf keystone_authtoken admin_tenant_name
	crudini --del /etc/neutron/neutron.conf keystone_authtoken admin_user
	crudini --del /etc/neutron/neutron.conf keystone_authtoken admin_password

	#
	# Olso Messaging Rabbit
	#

	crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_host $CONTROLLER_NODES
	crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_userid openstack
	crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_password $RABBIT_PASS

	#
	# Nova
	#

	crudini --set /etc/neutron/neutron.conf nova auth_url http://$CONTROLLER_NODES:35357
	crudini --set /etc/neutron/neutron.conf nova auth_type password
	crudini --set /etc/neutron/neutron.conf nova project_domain_name default
	crudini --set /etc/neutron/neutron.conf nova user_domain_name default
	crudini --set /etc/neutron/neutron.conf nova region_name RegionOne
	crudini --set /etc/neutron/neutron.conf nova project_name service
	crudini --set /etc/neutron/neutron.conf nova username $NOVA_USER
	crudini --set /etc/neutron/neutron.conf nova password $NOVA_PASS


	#
	# openvswitch agent configuration
	#

	crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings $BRIDGE_MAPPINGS
	# crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup firewall_driver iptables_hybrid
	crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

	#
	# metadata agent configuration
	#
	
	crudini --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_ip $CONTROLLER_NODES
	crudini --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret $METADATA_SECRET

	case $NETWORK_OPT in
	provider)
		;;
	self-service)
		#
		# openvswitch agent configuration
		#

		crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip $OVERLAY_INTERFACE_IP_ADDRESS
		crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent tunnel_types vxlan,gre
		crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent l2_population True
		crudini --set /etc/neutron/plugins/ml2/openvswitch_agent.ini agent arp_responder True

		#
		# l3 agent configuration
		#
		
		crudini --set /etc/neutron/l3_agent.ini DEFAULT  interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
		crudini --set /etc/neutron/l3_agent.ini DEFAULT  external_network_bridge
		;;
	*)
		echo ""
        echo "### ERROR: Wrong network option, config this variable with"
        echo "'self-service' or 'provider'"
        echo ""
        exit 1
		;;
	esac

	ovs-vsctl add-br $PROVIDER_BRIDGE
	ovs-vsctl add-port $PROVIDER_BRIDGE $PROVIDER_INTERFACE

	systemctl enable neutron-openvswitch-agent.service neutron-metadata-agent.service
	systemctl start neutron-openvswitch-agent.service neutron-metadata-agent.service
	if [[ $NETWORK_OPT == "self-service" ]]
	then
		systemctl enable neutron-l3-agent.service
		systemctl start neutron-l3-agent.service
	fi

		cat << EOF >> /etc/sysconfig/network-scripts/ifcfg-$PROVIDER_INTERFACE
OVS_BRIDGE=$PROVIDER_BRIDGE
TYPE="OVSPort"
DEVICETYPE="ovs"
EOF

	cat << EOF > /etc/sysconfig/network-scripts/ifcfg-$PROVIDER_BRIDGE 
DEVICE="$PROVIDER_BRIDGE"
BOOTPROTO="none"
ONBOOT="yes"
TYPE="OVSBridge"
DEVICETYPE="ovs"
EOF

  	sync
  	sleep 5
  	sync
}

verify_neutron()
{
	echo ""
	echo "### 2. Verify Neutron installation"
	echo ""
	source /etc/openstack-control-script-config/$ADMIN_RC_FILE
	echo "- Network agent list"
	openstack network agent list
	echo "- List loaded extension"
	neutron ext-list
	sync
	sleep 5
	sync
}

main()
{
	echo "### INSTALL_NEUTRON = $INSTALL_NEUTRON"
	install_configure_neutron
	verify_neutron
	date > /etc/openstack-control-script-config/neutron-openvswitch-$1-installed
}

main $1
