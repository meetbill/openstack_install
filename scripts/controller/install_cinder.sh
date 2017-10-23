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

#{{{env_check
env_check()
{
    if [[ -f /etc/openstack-control-script-config/cinder-installed ]]
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
    echo "### 1. Creating Cinder database"
    echo "CREATE DATABASE $CINDER_DBNAME;"|$MYSQL_COMMAND
    echo "GRANT ALL PRIVILEGES ON $CINDER_DBNAME.* TO '$CINDER_DBUSER'@'localhost' IDENTIFIED BY '$CINDER_DBPASS';"|$MYSQL_COMMAND
    echo "GRANT ALL PRIVILEGES ON $CINDER_DBNAME.* TO '$CINDER_DBUSER'@'%' IDENTIFIED BY '$CINDER_DBPASS';"|$MYSQL_COMMAND
    echo "FLUSH PRIVILEGES;"|$MYSQL_COMMAND
    sync
    sleep 5
    sync
}
#}}}
#{{{create_cinder_identity
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
        openstack service create --name $CINDER_SERVICE_V3 \
            --description "Openstack Block Storage" volumev3
        echo "- Cinder Endpoints"
        openstack endpoint create --region RegionOne \
            volumev2 public http://$CONTROLLER_NODES:8776/v2/%\(project_id\)s
        openstack endpoint create --region RegionOne \
            volumev2 internal http://$CONTROLLER_NODES:8776/v2/%\(project_id\)s
        openstack endpoint create --region RegionOne \
            volumev2 admin http://$CONTROLLER_NODES:8776/v2/%\(project_id\)s
        openstack endpoint create --region RegionOne \
            volumev3 public http://$CONTROLLER_NODES:8776/v3/%\(project_id\)s
        openstack endpoint create --region RegionOne \
            volumev3 internal http://$CONTROLLER_NODES:8776/v3/%\(project_id\)s
        openstack endpoint create --region RegionOne \
            volumev3 admin http://$CONTROLLER_NODES:8776/v3/%\(project_id\)s
        date > /etc/openstack-control-script-config/keystone-extra-idents-cinder
        echo ""
        echo "### Cinder Identity is Done"
        echo ""
        sync
        sleep 5
        sync
    fi
}
#}}}
#{{{install_configure_cinder
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
    crudini --set /etc/cinder/cinder.conf DEFAULT transport_url  rabbit://${RABBIT_USER}:${RABBIT_PASS}@${CONTROLLER_NODES}

    #
    # Keystone cinder Configuration
    #
    crudini --set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone
    crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_uri http://$CONTROLLER_NODES:5000
    crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_url http://$CONTROLLER_NODES:35357
    crudini --set /etc/cinder/cinder.conf keystone_authtoken memcached_servers $CONTROLLER_NODES:11211
    crudini --set /etc/cinder/cinder.conf keystone_authtoken auth_type password
    crudini --set /etc/cinder/cinder.conf keystone_authtoken project_domain_name default
    crudini --set /etc/cinder/cinder.conf keystone_authtoken user_domain_name default
    crudini --set /etc/cinder/cinder.conf keystone_authtoken project_name service
    crudini --set /etc/cinder/cinder.conf keystone_authtoken username $CINDER_USER
    crudini --set /etc/cinder/cinder.conf keystone_authtoken password $CINDER_PASS

    crudini --set /etc/cinder/cinder.conf DEFAULT my_ip $CONTROLLER_NODES_IP
    crudini --set /etc/cinder/cinder.conf DEFAULT oslo_concurrency lock_path /var/lib/cinder/tmp

    sync
    sleep 5
    sync
    
    echo ""
    echo "### 4. Populate the Block Storage service db"
    echo ""
    su -s /bin/sh -c "cinder-manage db sync" cinder

    crudini --set /etc/nova/nova.conf cinder os_region_name RegionOne

    systemctl restart openstack-nova-api.service
    systemctl enable openstack-cinder-api.service openstack-cinder-scheduler.service
    systemctl restart openstack-cinder-api.service openstack-cinder-scheduler.service
    echo ""
    echo "### Cinder Installed and Configured"
    echo ""

    sync
    sleep 5
    sync
}
#}}}
#{{{config_backends
config_backends()
{
    echo "### 4. config ceph"

    # ceph
    crudini --set /etc/cinder/cinder.conf DEFAULT enabled_backends ceph
    crudini --set /etc/cinder/cinder.conf DEFAULT glance_api_version 2
    crudini --set /etc/cinder/cinder.conf DEFAULT glance_api_servers http://$CONTROLLER_NODES_IP:9292
    # crudini --set /etc/cinder/cinder.conf DEFAULT verbose true

    # ceph config
    crudini --set /etc/cinder/cinder.conf ceph volume_driver cinder.volume.drivers.rbd.RBDDriver
    crudini --set /etc/cinder/cinder.conf ceph rbd_pool ${RBD_POOL}
    crudini --set /etc/cinder/cinder.conf ceph rbd_ceph_conf /etc/ceph/ceph.conf
    crudini --set /etc/cinder/cinder.conf ceph rbd_flatten_volume_from_snapshot false
    crudini --set /etc/cinder/cinder.conf ceph rbd_max_clone_depth ${RBD_MAX_CLONE_DEPTH}
    crudini --set /etc/cinder/cinder.conf ceph rbd_store_chunk_size  ${RBD_STORE_CHUNK_SIZE}
    crudini --set /etc/cinder/cinder.conf ceph rados_connect_timeout ${RADOS_CONNECT_TIMEOUT}
    crudini --set /etc/cinder/cinder.conf ceph glance_api_version  2
    crudini --set /etc/cinder/cinder.conf ceph rbd_user  ${RBD_USER}
    crudini --set /etc/cinder/cinder.conf ceph rbd_secret_uuid  ${RBD_SECRET_UUID}
    
    systemctl restart openstack-cinder-api.service openstack-cinder-scheduler.service
    echo ""
    echo "### Cinder ceph Configured"
    echo ""
}
#}}}
#{{{verify_cinder
verify_cinder()
{
    echo ""
    echo "### 5. Verify cinder installation"
    echo ""
    source /etc/openstack-control-script-config/$ADMIN_RC_FILE
    echo "- List service components to verify successful launch of each process:"
    openstack volume service list
    sync
    sleep 5
    sync
}
#}}}
main()
{
    echo "### INSTALL_CINDER = $INSTALL_CINDER"
    env_check
    create_database
    create_cinder_identity
    config_backends
    install_configure_cinder
    verify_cinder
    date > /etc/openstack-control-script-config/cinder-installed
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
            config_backends
            ;;
        check)
            verify_cinder
            ;;
        *)
            echo ${usage}
            exit 1
            ;;
    esac                                                                                                                                       
fi
