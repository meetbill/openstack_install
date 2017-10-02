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

#{{{env_check
env_check()
{
    if [[ -f /etc/openstack-control-script-config/neutron-linuxbridge-compute-installed ]]
    then
        echo ""
        echo "### This module was already completed. Exiting !"
        echo ""
        exit 0
    fi
}
#}}}
#{{{interface_check
interface_check()
{
    if [[ -z ${PROVIDER_INTERFACE} ]]
    then
        echo "### Can't find the PROVIDER_INTERFACE variable"
        echo ""
        exit 0
    else
        check_if=$(ip a | grep ${PROVIDER_INTERFACE}| wc -l)
        if [[ "w${check_if}" == "w0" ]]
        then
            echo "### Can't find the PROVIDER_INTERFACE ${PROVIDER_INTERFACE}"
            echo ""
            exit 0
        fi
    fi
}
#}}}
#{{{install_configure_neutron
install_configure_neutron()
{
    echo ""
    echo "### 1. Install Neutron Packages and Configure Neutron configs"
    echo ""
    yum install -y openstack-neutron-linuxbridge ebtables ipset

    IP=`grep ${HOSTNAME} /etc/hosts | awk '{print $1}'`

    #
    # Olso Messaging Rabbit
    #
    crudini --set /etc/neutron/neutron.conf DEFAULT transport_url  rabbit://${RABBIT_USER}:${RABBIT_PASS}@${CONTROLLER_NODES}
    
    #
    # Neutron Keystone Config
    #
    
    crudini --set /etc/neutron/neutron.conf DEFAULT auth_strategy keystone
    crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_uri http://$CONTROLLER_NODES:5000
    crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_url http://$CONTROLLER_NODES:35357
    crudini --set /etc/neutron/neutron.conf keystone_authtoken memcached_servers $CONTROLLER_NODES:11211
    crudini --set /etc/neutron/neutron.conf keystone_authtoken auth_type password
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
    # configure the lock path
    #
    crudini --set /etc/neutron/neutron.conf oslo_concurrency lock_path /var/lib/neutron/tmp


    #
    # linuxbridge configuration
    # 
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini linux_bridge physical_interface_mappings ${BRIDGE_MAPPINGS}
    #...
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup enable_security_group true
    crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

    case $NETWORK_OPT in
    provider)

        #
        # linuxbridge configuration
        # 
        
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan False

        ;;
    self-service)

        #
        # linuxbridge configuration
        # 
        
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan enable_vxlan true
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan l2_population true
        crudini --set /etc/neutron/plugins/ml2/linuxbridge_agent.ini vxlan local_ip $IP
        ;;
    *)
        echo ""
        echo "### ERROR: Wrong network option, config this variable with"
        echo "'self-service' or 'provider'"
        echo ""
        exit 1
        ;; 
    esac

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


    systemctl enable neutron-linuxbridge-agent.service
    systemctl restart neutron-linuxbridge-agent.service

    sync
    sleep 5
    sync
}
#}}}
#{{{verify_neutron
verify_neutron()
{
    echo ""
    echo "### 2. Verify Neutron installation"
    echo ""
    source /etc/openstack-control-script-config/$ADMIN_RC_FILE
    echo "- List loaded extension"
    openstack extension list --network
    echo "- Network agent list"
    openstack network agent list
    sync
    sleep 5
    sync
}
#}}}
main()
{
    echo "### INSTALL_NEUTRON = $INSTALL_NEUTRON"
    env_check
    interface_check
    install_configure_neutron
    verify_neutron
    date > /etc/openstack-control-script-config/neutron-linuxbridge-compute-installed
}


HOSTNAME=`hostname`
if [[ -z $COMPUTE_NODES ]] || [[ $COMPUTE_NODES != *$HOSTNAME* ]]
then
    echo ""
    echo "### WRONG CONFIG - $HOSTNAME NOT IN $COMPUTE_NODES"
    echo ""
    exit 0
fi

usage="$0 install/config/check"
if [ $# == 0 ];then
    echo ${usage}
else
    case $1 in
        install)
            main
            ;;
        config)
            interface_check
            install_configure_neutron
            ;;
        check)
            verify_neutron
            ;;
        *)
            echo ${usage}
            exit 1
            ;;
    esac                                                                                                                                       
fi

