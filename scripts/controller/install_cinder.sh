#!/bin/bash
#########################################################################
# File Name: environment.sh
# Author: meetbill
# mail: meetbill@163.com
# Created Time: 2017-07-17 19:05:07
# Install Glance script
# Install Cinder script
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

if [[ -f /etc/openstack-control-script-config/cinder-installed ]]
then
    echo ""
    echo "### This module was already completed. Exiting !"
    echo ""
    exit 0
fi

create_database()
{
    MYSQL_COMMAND="mysql --port=$MYSQLDB_PORT --password=$MYSQLDB_PASSWORD --user=$MYSQLDB_ADMIN "
    echo "### 1. Creating Cinder database"
    echo "CREATE DATABASE $CINDER_DBNAME;"|$MYSQL_COMMAND
    echo "GRANT ALL PRIVILEGES ON $CINDER_DBNAME.* TO '$CINDER_DBUSER'@'localhost' IDENTIFIED BY '$CINDER_DBPASS';"|$MYSQL_COMMAND
    echo "GRANT ALL PRIVILEGES ON $CINDER_DBNAME.* TO '$CINDER_DBUSER'@'%' IDENTIFIED BY '$CINDER_DBPASS';"|$MYSQL_COMMAND
    echo "FLUSH PRIVILEGES;"|$MYSQL_COMMAND
    sync
    sleep 5
    sync
}

create_cinder_identity()
{
    source /etc/openstack-control-script-config/$ADMIN_RC_FILE
    echo "### 2. Create Cinder user, service and endpoint"
    if [[ -f  /etc/openstack-control-script-config/keystone-extra-idents-cinder ]]
    then
        echo ""
        echo "### Cinder Identity was Done. Pass!"
        echo ""
    else
        echo "- Cinder User"
        openstack user create $CINDER_USER --domain default \
            --password $CINDER_PASS
        openstack role add --project service --user $CINDER_USER admin
        echo "- Cinder Service"
        openstack service create --name $CINDER_SERVICE \
            --description "OpenStack Block Storage" volume
        openstack service create --name $CINDER_SERVICE_V2 \
            --description "Openstack Block Storage" volumev2
        echo "- Cinder Endpoints"
        openstack endpoint create --region RegionOne \
            volume public http://$CONTROLLER_NODES:8776/v1/%\(tenant_id\)s
        openstack endpoint create --region RegionOne \
            volume internal http://$CONTROLLER_NODES:8776/v1/%\(tenant_id\)s
        openstack endpoint create --region RegionOne \
            volume admin http://$CONTROLLER_NODES:8776/v1/%\(tenant_id\)s
        openstack endpoint create --region RegionOne \
            volumev2 public http://$CONTROLLER_NODES:8776/v2/%\(tenant_id\)s
        openstack endpoint create --region RegionOne \
            volumev2 internal http://$CONTROLLER_NODES:8776/v2/%\(tenant_id\)s
        openstack endpoint create --region RegionOne \
            volumev2 admin http://$CONTROLLER_NODES:8776/v2/%\(tenant_id\)s
        date > /etc/openstack-control-script-config/keystone-extra-idents-cinder
        echo ""
        echo "### Cinder Identity is Done"
        echo ""
        sync
        sleep 5
        sync
    fi
}

install_configure_cinder()
{
    echo "### 3. Install Cinder and Configure Cinder configuration"
    #
    # Install cinder package
    # 
    yum -y install openstack-cinder targetcli
    #
    # Using crudini we proceed to configure cinder service
    #
    crudini --set /etc/cinder/cinder.conf database connection mysql+pymysql://$CINDER_DBUSER:$CINDER_DBPASS@$CONTROLLER_NODES/$CINDER_DBNAME
    crudini --set /etc/cinder/cinder.conf DEFAULT rpc_backend rabbit
    crudini --set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone
    crudini --set /etc/cinder/cinder.conf DEFAULT my_ip $CONTROLLER_NODES_IP
    crudini --set /etc/cinder/cinder.conf DEFAULT oslo_concurrency lock_path /var/lib/cinder/tmp
    crudini --set /etc/cinder/cinder.conf DEFAULT enabled_backends synology
    crudini --set /etc/cinder/cinder.conf DEFAULT glance_api_version 2
    crudini --set /etc/cinder/cinder.conf DEFAULT allowed_direct_url_schemes cinder
    crudini --set /etc/cinder/cinder.conf DEFAULT glance_api_servers http://$CONTROLLER_NODES_IP:9292
    crudini --set /etc/cinder/cinder.conf DEFAULT verbose true


    #
    # Rabbit Configuration
    # 
    crudini --set /etc/cinder/cinder.conf oslo_messaging_rabbit rabbit_host $CONTROLLER_NODES
    crudini --set /etc/cinder/cinder.conf oslo_messaging_rabbit rabbit_userid $RABBIT_USER
    crudini --set /etc/cinder/cinder.conf oslo_messaging_rabbit rabbit_password $RABBIT_PASS

    #
    # Keystone cinder Configuration
    #

    crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_uri http://$CONTROLLER_NODES:5000
    crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_url http://$CONTROLLER_NODES:35357
    crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_type password
    crudini --set /etc/cinder/cinder.conf keystone_authtoken project_domain_name default
    crudini --set /etc/cinder/cinder.conf keystone_authtoken user_domain_name default
    crudini --set /etc/cinder/cinder.conf keystone_authtoken project_name service
    crudini --set /etc/cinder/cinder.conf keystone_authtoken username $CINDER_USER
    crudini --set /etc/cinder/cinder.conf keystone_authtoken password $CINDER_PASS
    crudini --set /etc/cinder/cinder.conf keystone_authtoken memcached_servers $CONTROLLER_NODES:11211

    crudini --set /etc/nova/nova.conf cinder os_region_name RegionOne

    sync
    sleep 5
    sync
    
    echo ""
    echo "### 4. Populate the Block Storage service db"
    echo ""
    su -s /bin/sh -c "cinder-manage db sync" cinder

    systemctl restart openstack-nova-api.service
    systemctl enable openstack-cinder-api.service openstack-cinder-scheduler.service
    systemctl start openstack-cinder-api.service openstack-cinder-scheduler.service
    echo ""
    echo "### Cinder Installed and Configured"
    echo ""

    sync
    sleep 5
    sync
}

verify_cinder()
{
    echo ""
    echo "### 5. Verify cinder installation"
    echo ""
    source /etc/openstack-control-script-config/$ADMIN_RC_FILE
    echo "- List service components to verify successful launch of each process:"
    cinder service-list
    sync
    sleep 5
    sync
}

main()
{
    echo "### INSTALL_CINDER = $INSTALL_CINDER"
    create_database
    create_cinder_identity
    install_configure_cinder
    verify_cinder
    date > /etc/openstack-control-script-config/cinder-installed
}

main

if [ $# -gt 0  ]; then
    if [[ $1 == "config" ]]
    then
        echo "xxxxxxxxxxxxxxx"
    fi
else
    echo "没有参数"
fi
