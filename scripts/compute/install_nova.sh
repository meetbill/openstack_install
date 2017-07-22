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
    echo "###  ERROR:Can't access my config file. Aborting !"
    echo ""
    exit 0
fi

if [[ -f /etc/openstack-control-script-config/nova-compute-installed ]]
then
    echo ""
    echo "### This module was already completed. Exiting !"
    echo ""
    exit 0
fi

install_configure_nova()
{
    echo ""
    echo "### 1. Install and Configuration Nova Compute"
    echo ""
    yum -y install openstack-nova-compute

    IP=`grep $1 /etc/hosts | awk '{print $1}'`

    #
    # Using crudini we proceed to configure nova service
    #
    
    #
    # Keystone NOVA Configuration
    #

    crudini --set /etc/nova/nova.conf keystone_authtoken auth_uri http://$CONTROLLER_NODES:5000
    crudini --set /etc/nova/nova.conf keystone_authtoken auth_url http://$CONTROLLER_NODES:35357
    crudini --set /etc/nova/nova.conf keystone_authtoken auth_type password
    crudini --set /etc/nova/nova.conf keystone_authtoken project_domain_name default
    crudini --set /etc/nova/nova.conf keystone_authtoken user_domain_name default
    crudini --set /etc/nova/nova.conf keystone_authtoken project_name service
    crudini --set /etc/nova/nova.conf keystone_authtoken username $NOVA_USER
    crudini --set /etc/nova/nova.conf keystone_authtoken password $NOVA_PASS
    crudini --set /etc/nova/nova.conf keystone_authtoken memcached_servers $CONTROLLER_NODES:11211

    crudini --set /etc/nova/nova.conf DEFAULT auth_strategy keystone
    crudini --set /etc/nova/nova.conf DEFAULT rpc_backend rabbit
    crudini --set /etc/nova/nova.conf DEFAULT use_neutron True
    crudini --set /etc/nova/nova.conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
    crudini --set /etc/nova/nova.conf DEFAULT my_ip $IP

    #
    # Rabbit Configuration
    # 
    crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_host $CONTROLLER_NODES
    crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_userid $RABBIT_USER
    crudini --set /etc/nova/nova.conf oslo_messaging_rabbit rabbit_password $RABBIT_PASS

    #
    # VNC Configuration
    # 
    crudini --set /etc/nova/nova.conf vnc enabled True
    crudini --set /etc/nova/nova.conf vnc vncserver_listen 0.0.0.0
    crudini --set /etc/nova/nova.conf vnc vncserver_proxyclient_address '$my_ip'
    crudini --set /etc/nova/nova.conf vnc novncproxy_base_url  http://controller:6080/vnc_auto.html

    crudini --set /etc/nova/nova.conf glance api_servers http://$CONTROLLER_NODES:9292
    crudini --set /etc/nova/nova.conf oslo_concurrency lock_path /var/lib/nova/tmp

    #
    # Libvirt Configuration
    # 
    kvm_possible=`egrep -c '(vmx|svm)' /proc/cpuinfo`
    if [[ $kvm_possible == "0" ]]
    then
        echo ""
        echo "### WARNING !. This server does not support KVM"
        echo "### We will have to use QEMU instead of KVM"
        echo "### Performance will be poor"
        echo ""
        source /etc/openstack-control-script-config/$ADMIN_RC_FILE
        crudini --set /etc/nova/nova.conf libvirt virt_type qemu
        setsebool -P virt_use_execmem on
        ln -s -f /usr/libexec/qemu-kvm /usr/bin/qemu-system-x86_64
        service libvirtd restart
    else
        crudini --set /etc/nova/nova.conf libvirt virt_type $VIRT_TYPE
    fi

    crudini --set /etc/nova/nova.conf DEFAULT ram_allocation_ratio $RAM_ALLOCATION_RATIO
    crudini --set /etc/nova/nova.conf DEFAULT cpu_allocation_ratio $CPU_ALLOCATION_RATIO
    crudini --set /etc/nova/nova.conf DEFAULT disk_allocation_ratio $DISK_ALLOCATION_RATIO

    systemctl enable libvirtd.service openstack-nova-compute.service
    systemctl restart libvirtd.service openstack-nova-compute.service
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
    echo ""
    echo "### INSTALL NOVA IN COMPUTE NODE $1"
    echo ""

    install_configure_nova $1
    verify_nova
    date > /etc/openstack-control-script-config/nova-$1-installed
}

main $1
