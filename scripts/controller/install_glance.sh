#!/bin/bash
#########################################################################
# File Name: environment.sh
# Author: meetbill
# mail: meetbill@163.com
# Created Time: 2017-07-17 19:05:07
# Install Glance script
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
    if [[ -f /etc/openstack-control-script-config/glance-installed ]]
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
	echo "### 1. Creating Glance database"
	echo "CREATE DATABASE $GLANCE_DBNAME;"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $GLANCE_DBNAME.* TO '$GLANCE_DBUSER'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';"|$MYSQL_COMMAND
	echo "GRANT ALL PRIVILEGES ON $GLANCE_DBNAME.* TO '$GLANCE_DBUSER'@'%' IDENTIFIED BY '$GLANCE_DBPASS';"|$MYSQL_COMMAND
	echo "FLUSH PRIVILEGES;"|$MYSQL_COMMAND
	sync
	sleep 5
	sync
}

create_glance_identity()
{
	source /etc/openstack-control-script-config/$ADMIN_RC_FILE
	echo "### 2. Create Glance user, service and endpoint"
	if [[ -f  /etc/openstack-control-script-config/keystone-extra-idents-glance ]]
	then
		echo ""
		echo "### Glance Identity was Done. Pass!"
		echo ""
	else
		echo "- Glance User"
		openstack user create $GLANCE_USER --domain default \
			--password $GLANCE_PASS
		openstack role add --project service --user $GLANCE_USER admin
		echo "- Glance Service"
		openstack service create --name $GLANCE_SERVICE \
			--description "OpenStack Image" image
		echo "- Glance Endpoints"
		openstack endpoint create --region RegionOne \
	  		image public http://$CONTROLLER_NODES:9292
	  	openstack endpoint create --region RegionOne \
	  		image internal http://$CONTROLLER_NODES:9292
	  	openstack endpoint create --region RegionOne \
	 		image admin http://$CONTROLLER_NODES:9292
	 	date > /etc/openstack-control-script-config/keystone-extra-idents-glance
	 	echo ""
		echo "### Glance Identity is Done"
		echo ""
		sync
		sleep 5
		sync
	fi
}

install_configure_glance()
{
 	echo "### 3. Install Glance and Configure Glance configuration"
	#
	# Install glance package
	# 
 	yum -y install openstack-glance
 	#
 	# Using crudini we proceed to configure glance service
 	#
 	crudini --set /etc/glance/glance-api.conf DEFAULT debug False
 	crudini --set /etc/glance/glance-api.conf glance_store default_store file
	crudini --set /etc/glance/glance-api.conf glance_store stores file,http,cinder
	crudini --set /etc/glance/glance-api.conf DEFAULT show_multiple_locations True
	crudini --set /etc/glance/glance-api.conf DEFAULT show_image_direct_url True
	crudini --set /etc/glance/glance-api.conf glance_store filesystem_store_datadir /var/lib/glance/images/
	crudini --set /etc/glance/glance-api.conf DEFAULT bind_host 0.0.0.0
	crudini --set /etc/glance/glance-api.conf DEFAULT bind_port 9292
	crudini --set /etc/glance/glance-api.conf DEFAULT log_file /var/log/glance/api.log
	crudini --set /etc/glance/glance-api.conf DEFAULT backlog 4096
	crudini --set /etc/glance/glance-api.conf DEFAULT use_syslog False
 	crudini --set /etc/glance/glance-api.conf database connection mysql+pymysql://$GLANCE_DBUSER:$GLANCE_DBPASS@$CONTROLLER_NODES/$GLANCE_DBNAME
 	crudini --set /etc/glance/glance-registry.conf database connection mysql+pymysql://$GLANCE_DBUSER:$GLANCE_DBPASS@$CONTROLLER_NODES/$GLANCE_DBNAME

 	crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_uri http://$CONTROLLER_NODES:5000
	crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_url http://$CONTROLLER_NODES:35357
	crudini --set /etc/glance/glance-api.conf keystone_authtoken auth_type password
	crudini --set /etc/glance/glance-api.conf keystone_authtoken memcached_servers $CONTROLLER_NODES:11211
	crudini --set /etc/glance/glance-api.conf keystone_authtoken project_domain_name default
	crudini --set /etc/glance/glance-api.conf keystone_authtoken user_domain_name default
	crudini --set /etc/glance/glance-api.conf keystone_authtoken project_name service
	crudini --set /etc/glance/glance-api.conf keystone_authtoken username $GLANCE_USER
	crudini --set /etc/glance/glance-api.conf keystone_authtoken password $GLANCE_PASS

	crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_uri http://$CONTROLLER_NODES:5000
	crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_url http://$CONTROLLER_NODES:35357
	crudini --set /etc/glance/glance-registry.conf keystone_authtoken auth_type password
	crudini --set /etc/glance/glance-registry.conf keystone_authtoken memcached_servers $CONTROLLER_NODES:11211
	crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_domain_name default
	crudini --set /etc/glance/glance-registry.conf keystone_authtoken user_domain_name default
	crudini --set /etc/glance/glance-registry.conf keystone_authtoken project_name service
	crudini --set /etc/glance/glance-registry.conf keystone_authtoken username $GLANCE_USER
	crudini --set /etc/glance/glance-registry.conf keystone_authtoken password $GLANCE_PASS

	crudini --set /etc/glance/glance-api.conf paste_deploy flavor keystone
	crudini --set /etc/glance/glance-registry.conf paste_deploy flavor keystone

	sync
	sleep 5
	sync
	
	echo ""
	echo "### 4. Populate the Image service db"
	echo ""
	su -s /bin/sh -c "glance-manage db_sync" glance

	systemctl enable openstack-glance-api.service \
		openstack-glance-registry.service
	systemctl start openstack-glance-api.service \
 		openstack-glance-registry.service
 	echo ""
	echo "### Glance Installed and Configured"
	echo ""

	sync
	sleep 5
	sync
}

verify_glance()
{
	echo ""
	echo "### 5. Verify Glance installation"
	echo ""
	source /etc/openstack-control-script-config/$ADMIN_RC_FILE
	wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
	echo "- Create Image Cirros"
	openstack image create "cirros" \
		--file cirros-0.3.4-x86_64-disk.img \
		--disk-format qcow2 --container-format bare \
		--public
	echo "- Image list"
	openstack image list
	sync
	sleep 5
	sync
}

main()
{
	echo "### INSTALL_GLANCE = $INSTALL_GLANCE"
    env_check
	create_database
	create_glance_identity
	install_configure_glance
	verify_glance
	date > /etc/openstack-control-script-config/glance-installed
}

if [ $# -gt 0  ]; then
    input_type=$1
    case ${input_type} in 
        config)
	        install_configure_glance
            ;;
        check)
	        source /etc/openstack-control-script-config/$ADMIN_RC_FILE
	        openstack image list
            ;;
            *)
            echo "USAGE: $0 check|config" 
            ;;
    esac
else
    main
fi
