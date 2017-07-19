#!/bin/bash
#########################################################################
# File Name: environment.sh
# Author: meetbill
# mail: meetbill@163.com
# Created Time: 2017-07-17 19:05:07
# Install nova script
#########################################################################

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

if [[ -f /etc/openstack-control-script-config/main-config.rc ]]
then
	source /etc/openstack-control-script-config/main-config.rc
else
	echo "### ERROR: Can't access my config file. Aborting !"
	echo ""
	exit 0
fi

env_check()
{
    if [[ -f /etc/openstack-control-script-config/nova-installed ]]
    then
        echo ""
        echo "### This module was already completed. Exiting !"
        echo ""
        exit 0
    fi
}

create_database()
{
	MYSQL_COMMAND="mysql --port=$MYSQLDB_PORT --password=$MYSQLDB_PASSWORD --user=$MYSQLDB_ADMIN "
	echo "### 1. Creating Nova database"
	echo "CREATE DATABASE $NOVA_DBNAME;"|$MYSQL_COMMAND
	echo "CREATE DATABASE $NOVAAPI_DBNAME;"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NOVAAPI_DBNAME.* TO '$NOVA_DBUSER'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NOVA_DBNAME.* TO '$NOVA_DBUSER'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NOVA_DBNAME.* TO '$NOVA_DBUSER'@'%' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NOVAAPI_DBNAME.* TO '$NOVA_DBUSER'@'%' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "FLUSH PRIVILEGES;"|$MYSQL_COMMAND
	sync
	sleep 5
	sync
}

create_nova_identity()
{
	source /etc/openstack-control-script-config/$ADMIN_RC_FILE
	echo "### 2. Create Nova user, service and endpoint"
	if [[ -f /etc/openstack-control-script-config/keystone-extra-idents-nova ]]
	then
		echo ""
		echo "### Nova Identity was Done. Pass!"
		echo ""
	else
		echo "- Nova User"
		openstack user create $NOVA_USER --domain default \
			--password $NOVA_PASS
		openstack role add --project service --user $NOVA_USER admin
		echo "- Nova Service"
		openstack service create --name $NOVA_SERVICE \
			--description "OpenStack Compute" compute
		echo "- Nova Endpoints"
		openstack endpoint create --region RegionOne \
			compute public http://$CONTROLLER_NODES:8774/v2.1/%\(tenant_id\)s
		openstack endpoint create --region RegionOne \
			compute internal http://$CONTROLLER_NODES:8774/v2.1/%\(tenant_id\)s
		openstack endpoint create --region RegionOne \
			compute admin http://$CONTROLLER_NODES:8774/v2.1/%\(tenant_id\)s
	 	date > /etc/openstack-control-script-config/keystone-extra-idents-nova
	 	echo ""
		echo "### Nova Identity is Done"
		echo ""
	fi
}

install_configure_nova()
{
	echo ""
	echo "### 3. Install Nova Packages and Configure Nova configs"
	echo ""
	yum -y install openstack-nova-api openstack-nova-conductor \
		openstack-nova-console openstack-nova-novncproxy \
		openstack-nova-scheduler
	#
	# Using crudini we proceed to configure nova service
	#
	
	#
	# Keystone NOVA Configuration
	#

	crudini --set /etc/nova/nova.conf keystone_authtoken auth_uri http://$CONTROLLER_NODES:5000
	crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://$CONTROLLER_NODES:35357
	crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers $CONTROLLER_NODES:11211
	crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
	crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name default
	crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name default
	crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
	crudini --set /etc/nova/nova.conf keystone_authtoken username $NOVA_USER
	crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_PASS

	crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
	crudini --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
	crudini --set /etc/nova/nova.conf DEFAULT rpc_backend rabbit
	crudini --set /etc/nova/nova.conf DEFAULT use_neutron True
	crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
	crudini --set /etc/nova/nova.conf DEFAULT my_ip $CONTROLLER_NODES_IP


	#
	# Database Configuration
	# 
	crudini --set /etc/nova/nova.conf api_database connection mysql+pymysql://$NOVA_DBUSER:$NOVA_DBPASS@$CONTROLLER_NODES/$NOVAAPI_DBNAME
	crudini --set /etc/nova/nova.conf database connection mysql+pymysql://$NOVA_DBUSER:$NOVA_DBPASS@$CONTROLLER_NODES/$NOVA_DBNAME

	#
	# Rabbit Configuration
	# 
	crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_host $CONTROLLER_NODES
	crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_userid $RABBIT_USER
	crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_password $RABBIT_PASS


	sync
	sleep 5
	sync

	echo ""
	echo "### 4. Populate the Compute databases"
	echo ""

	su -s /bin/sh -c "nova-manage api_db sync" $NOVA_DBUSER
	su -s /bin/sh -c "nova-manage db sync" $NOVA_DBUSER

	sync
	sleep 5
	sync
	systemctl enable openstack-nova-api.service \
  		openstack-nova-consoleauth.service openstack-nova-scheduler.service \
  		openstack-nova-conductor.service openstack-nova-novncproxy.service
	systemctl start openstack-nova-api.service \
		openstack-nova-consoleauth.service openstack-nova-scheduler.service \
		openstack-nova-conductor.service openstack-nova-novncproxy.service
	echo ""
	echo "### Nova Installed and Configured"
	echo ""
	sync
	sleep 5
	sync
}

verify_nova()
{
	echo ""
	echo "### 5. Verify Nova Installation"
	echo ""
	source /etc/openstack-control-script-config/$ADMIN_RC_FILE
	echo ""
	echo "- List service components to verify successful launch and registration of each process"
	echo ""
	openstack compute service list
}

main()
{
	echo "### INSTALL_NOVA = $INSTALL_NOVA"
    env_check
	create_database
	create_nova_identity
	install_configure_nova
	verify_nova
	date > /etc/openstack-control-script-config/nova-installed
}

if [ $# -gt 0  ]; then
    input_type=$1
    case ${input_type} in 
        config)
	        install_configure_nova
            ;;
        check)
	        verify_nova
            ;;
            *)
            echo "USAGE: $0 check|config" 
            ;;
    esac
else
    main
fi
