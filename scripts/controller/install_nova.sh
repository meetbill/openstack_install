#!/bin/bash
#########################################################################
# File Name: install_nova.sh
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

#{{{env_check
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
#}}}
#{{{create_database
create_database()
{
	MYSQL_COMMAND="mysql --port=$MYSQLDB_PORT --password=$MYSQLDB_PASSWORD --user=$MYSQLDB_ADMIN "
	echo "### 1. Creating Nova database"
	echo "CREATE DATABASE $NOVA_DBNAME;"|$MYSQL_COMMAND
	echo "CREATE DATABASE $NOVAAPI_DBNAME;"|$MYSQL_COMMAND
	echo "CREATE DATABASE $NOVACELL_DBNAME;"|$MYSQL_COMMAND
	echo "### 2. Grant proper access to the databases"
	echo "GRANT ALL PRIVILEGES ON $NOVAAPI_DBNAME.* TO '$NOVA_DBUSER'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NOVAAPI_DBNAME.* TO '$NOVA_DBUSER'@'%' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NOVA_DBNAME.* TO '$NOVA_DBUSER'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NOVA_DBNAME.* TO '$NOVA_DBUSER'@'%' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NOVACELL_DBNAME.* TO '$NOVA_DBUSER'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $NOVACELL_DBNAME.* TO '$NOVA_DBUSER'@'%' IDENTIFIED BY '$NOVA_DBPASS';"|$MYSQL_COMMAND
	echo "FLUSH PRIVILEGES;"|$MYSQL_COMMAND
	sync
	sleep 5
	sync
}
#}}}
#{{{create_nova_identity
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
			compute public http://$CONTROLLER_NODES:8774/v2.1
		openstack endpoint create --region RegionOne \
			compute internal http://$CONTROLLER_NODES:8774/v2.1
		openstack endpoint create --region RegionOne \
			compute admin http://$CONTROLLER_NODES:8774/v2.1
	 	echo ""
		echo "### Nova Identity is Done"
		echo ""
		echo "- Placement User"
        openstack user create ${PLACEMENT_USER} --domain default \
            --password ${PLACEMENT_PASS}
		openstack role add --project service --user ${PLACEMENT_USER} admin
		echo "- Placement Service"
        openstack service create --name ${PLACEMENT_SERVICE} --description "Placement API" placement
		echo "- Placement Endpoints"
        openstack endpoint create --region RegionOne placement public http://${CONTROLLER_NODES}:8778
        openstack endpoint create --region RegionOne placement internal http://${CONTROLLER_NODES}:8778
        openstack endpoint create --region RegionOne placement admin http://${CONTROLLER_NODES}:8778
	 	echo ""
		echo "### Placement Identity is Done"
		echo ""

	 	date > /etc/openstack-control-script-config/keystone-extra-idents-nova
        
	fi
}
#}}}
#{{{install_configure_nova
install_configure_nova()
{
	echo ""
	echo "### 3. Install Nova Packages and Configure Nova configs"
	echo ""
	yum -y install openstack-nova-api openstack-nova-conductor \
		openstack-nova-console openstack-nova-novncproxy \
		openstack-nova-scheduler openstack-nova-placement-api
	#
	# Using crudini we proceed to configure nova service
	#
	
	#
	# Keystone NOVA Configuration
	#

    #
    # 2 /etc/nova/nova.conf
    #
	
    crudini --set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
	
    #
	# Database Configuration
	# 
	crudini --set /etc/nova/nova.conf api_database connection mysql+pymysql://$NOVA_DBUSER:$NOVA_DBPASS@$CONTROLLER_NODES/$NOVAAPI_DBNAME
	crudini --set /etc/nova/nova.conf database connection mysql+pymysql://$NOVA_DBUSER:$NOVA_DBPASS@$CONTROLLER_NODES/$NOVA_DBNAME

	#
	# Rabbit Configuration
	# 
    crudini --set /etc/nova/nova.conf DEFAULT transport_url  rabbit://${RABBIT_USER}:${RABBIT_PASS}@${CONTROLLER_NODES}

    #
    # keystone Configuration
    #
	crudini --set /etc/nova/nova.conf api auth_strategy keystone
	crudini --set /etc/nova/nova.conf keystone_authtoken auth_uri http://$CONTROLLER_NODES:5000
	crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://$CONTROLLER_NODES:35357
	crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers $CONTROLLER_NODES:11211
	crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
	crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name default
	crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name default
	crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
	crudini --set /etc/nova/nova.conf keystone_authtoken username $NOVA_USER
	crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_PASS

	#
    # manamge IP
    #
    
    crudini --set /etc/nova/nova.conf DEFAULT my_ip $CONTROLLER_NODES_IP

    #
    # enable support for the Networking service
    #
	crudini --set /etc/nova/nova.conf DEFAULT use_neutron True
    #********************************************************************have a change
	crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver


    #
    # vnc
    #
	crudini --set /etc/nova/nova.conf vnc enabled true
	crudini --set /etc/nova/nova.conf vnc vncserver_listen $my_ip
	crudini --set /etc/nova/nova.conf vnc vncserver_proxyclient_address $my_ip
    
    #
    # glance
    #
	crudini --set /etc/nova/nova.conf glance api_servers http://${CONTROLLER_NODES}:9292
	
    crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp

    #
    # Placement
    #
    crudini --set /etc/nova/nova.conf placement os_region_name RegionOne
    crudini --set /etc/nova/nova.conf placement project_domain_name Default
    crudini --set /etc/nova/nova.conf placement project_name service
    crudini --set /etc/nova/nova.conf placement auth_type password
    crudini --set /etc/nova/nova.conf placement user_domain_name Default
    crudini --set /etc/nova/nova.conf placement auth_url http://$CONTROLLER_NODES:35357
    crudini --set /etc/nova/nova.conf placement username ${PLACEMENT_USER}
    crudini --set /etc/nova/nova.conf placement password ${PLACEMENT_PASS}
    
    if [[ -f /etc/openstack-control-script-config/httpd/00-nova-placement-api.conf ]] 
    then
        cp /etc/openstack-control-script-config/httpd/00-nova-placement-api.conf  /etc/httpd/conf.d/00-nova-placement-api.conf
        chmod +x /etc/httpd/conf.d/00-nova-placement-api.conf
        systemctl restart httpd
    else
        echo "not found the 00-nova-placement-api.conf file"
    fi

	sync
	sleep 5
	sync

	echo ""
	echo "### 4. Populate the Compute databases"
	echo ""

	su -s /bin/sh -c "nova-manage api_db sync" $NOVA_DBUSER
    su -s /bin/sh -c "nova-manage cell_v2 map_cell0" ${NOVA_USER}
    su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" ${NOVA_USER}
    su -s /bin/sh -c "nova-manage db sync" ${NOVA_USER}

    
    echo "- verify nova cell0 and cell1"
    nova-manage cell_v2 list_cells

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
#}}}
#{{{verify_nova
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
    openstack catalog list
    openstack image list
    nova-status upgrade check

}
#}}}
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

usage="$0 install/config/check"
if [ $# == 0 ];then
    echo ${usage}
else
    case $1 in
        install)
            main
            ;;
        config)
	        install_configure_nova
            ;;
        check)
	        verify_nova
            ;;
        *)
            echo ${usage}
            exit 1
            ;;
    esac                                                                                                                                       
fi

