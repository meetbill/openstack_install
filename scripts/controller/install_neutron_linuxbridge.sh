#!/bin/bash
#########################################################################
# File Name: environment.sh
# Author: meetbill
# mail: meetbill@163.com
# Created Time: 2017-07-17 19:05:07
# Install neutron linuxbridge script
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

env_check()
{
    if [[ -f /etc/openstack-control-script-config/neutron-linuxbridge-installed ]]
    then
        echo ""
        echo "### This module was already completed. Exiting !"
        echo ""
        exit 0
    fi
}
create_database()
{
	MYSQL_COMMAND="mysql --port=$MYSQLDB_PORT --password=$MYSQLDB_PASSWORD --user=$MYSQLDB_ADMIN"
	echo "### 1. Creating neutron database"
	echo "CREATE DATABASE $NEUTRON_DBNAME;"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NEUTRON_DBNAME.* TO '$NEUTRON_DBUSER'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NEUTRON_DBNAME.* TO '$NEUTRON_DBUSER'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';"|$MYSQL_COMMAND
	echo "FLUSH PRIVILEGES;"|$MYSQL_COMMAND
	sync
	sleep 5
	sync
}

create_neutron_identity()
{
	source /etc/openstack-control-script-config/$ADMIN_RC_FILE
	echo "### 2. Create neutron user, service and endpoint"
	if [[ -f  /etc/openstack-control-script-config/keystone-extra-idents-neutron ]]
	then
		echo ""
		echo "### Neutron Identity was Done. Pass!"
		echo ""
	else
		echo "- Neutron User"
		openstack user create $NEUTRON_USER --domain default \
			--password $NEUTRON_PASS
		openstack role add --project service --user $NEUTRON_USER admin
		echo "- Neutron Service"
		openstack service create --name $NEUTRON_SERVICE \
			--description "OpenStack Network" network
		echo "- Neutron Endpoints"
		openstack endpoint create --region RegionOne \
			network public http://$CONTROLLER_NODES:9696
		openstack endpoint create --region RegionOne \
			network internal http://$CONTROLLER_NODES:9696
		openstack endpoint create --region RegionOne \
			network admin http://$CONTROLLER_NODES:9696
	 	date > /etc/openstack-control-script-config/keystone-extra-idents-neutron
	 	echo ""
		echo "### Neutron Identity is Done"
		echo ""
		sync
		sleep 5
		sync
	fi
}

install_configure_neutron()
{
	echo ""
	echo "### 3. Install Neutron Packages and Configure Neutron configs"
	echo ""
	yum install -y openstack-neutron \
		openstack-neutron-linuxbridge \
		openstack-neutron-ml2 \
		python-neutron \
		python-neutronclient \
		ebtables

	crudini --set /etc/neutron/neutron.conf DEFAULT core_plugin ml2
	crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
	crudini --set /etc/neutron/neutron.conf DEFAULT rpc_backend rabbit
	crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes True
	crudini --set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes True
	
	crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp

	#
	# Database configuration
	# 
	
	crudini --set /etc/neutron/neutron.conf database connection mysql+pymysql://$NEUTRON_DBUSER:$NEUTRON_DBPASS@$CONTROLLER_NODES/$NEUTRON_DBNAME

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
	# Olso Messaging Rabbit
	#

	crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_host $CONTROLLER_NODES
	crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_userid openstack
	crudini --set /etc/neutron/neutron.conf oslo_messaging_rabbit rabbit_password $RABBIT_PASS

	#
	# Neutron Nova
	#
	
	crudini --set /etc/nova/nova.conf neutron url http://$CONTROLLER_NODES:9696
	crudini --set /etc/nova/nova.conf neutron auth_url http://$CONTROLLER_NODES:35357
	crudini --set /etc/nova/nova.conf neutron auth_type password
	crudini --set /etc/nova/nova.conf neutron project_domain_name default
	crudini --set /etc/nova/nova.conf neutron user_domain_name default
	crudini --set /etc/nova/nova.conf neutron region_name RegionOne
	crudini --set /etc/nova/nova.conf neutron project_name service
	crudini --set /etc/nova/nova.conf neutron username $NEUTRON_USER
	crudini --set /etc/nova/nova.conf neutron password $NEUTRON_PASS
	crudini --set /etc/nova/nova.conf neutron service_metadata_proxy True
	crudini --set /etc/nova/nova.conf neutron metadata_proxy_shared_secret $METADATA_SECRET

	#
	# ml2 configuration
	
	crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
	crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks $FLAT_NETWORKS
	crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup enable_ipset True

	#
	# linuxbridge configuration
	# 
	
	crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings ${BRIDGE_MAPPINGS}
	crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group True
	crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

	#
	# dhcp agent configuration
	#

	crudini --set /etc/neutron/dhcp_agent.ini DEFAULT interface_driver neutron.agent.linux.interface.BridgeInterfaceDriver
	crudini --set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
	crudini --set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata True

	case $NETWORK_OPT in
	provider)

		#
		# ml2 configuration
		#

		crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers "flat,vlan"
		crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types ""
		crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers linuxbridge

		#
		# linuxbridge configuration
		# 
		
		crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan False

		;;
	self-service)

		crudini --set /etc/neutron/neutron.conf DEFAULT service_plugins router
		crudini --set /etc/neutron/neutron.conf DEFAULT allow_overlapping_ips True
		crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers "flat,vlan,vxlan"

		#
		# ml2 configuration
		# 
		
		crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types vxlan
		crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 path_mtu 1500
		crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 mechanism_drivers "linuxbridge,l2population"
		crudini --set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vxlan vni_ranges $VNI_RANGES

		#
		# linuxbridge configuration
		# 

		crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan True
		crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan l2_population True
		crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan local_ip ${CONTROLLER_NODES_IP}

		#
		# l3 agent configuration
		#
		
		crudini --set /etc/neutron/l3_agent.ini DEFAULT  interface_driver neutron.agent.linux.interface.BridgeInterfaceDriver
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

	echo ""
	echo "### 4. Populate Neutron database."
	echo ""
	ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
	su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
 		--config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

	systemctl restart openstack-nova-api.service

	systemctl enable neutron-server.service \
		neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  		neutron-metadata-agent.service
	systemctl start neutron-server.service \
  		neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  		neutron-metadata-agent.service
  	if [[ $NETWORK_OPT == "self-service" ]]
	then
		systemctl enable neutron-l3-agent.service
		systemctl restart neutron-l3-agent.service
	fi
}

verify_neutron()
{
	echo ""
	echo "### 5. Verify Neutron installation"
	echo ""
	source /etc/openstack-control-script-config/$ADMIN_RC_FILE
	echo "- Network agent list"
	neutron agent-list
	echo "- List loaded extension"
	neutron ext-list
	sync
	sleep 5
	sync
}

main()
{
	echo "### INSTALL_NEUTRON = $INSTALL_NEUTRON"
    env_check
	create_database
	create_neutron_identity
	install_configure_neutron
	verify_neutron
	date > /etc/openstack-control-script-config/neutron-linuxbridge-installed
}

if [ $# -gt 0  ]; then
    input_type=$1
    case ${input_type} in 
        config)
	        install_configure_neutron
            ;;
        check)
	        source /etc/openstack-control-script-config/$ADMIN_RC_FILE
	        verify_neutron
            ;;
            *)
            echo "USAGE: $0 check|config" 
            ;;
    esac
else
    main
fi
