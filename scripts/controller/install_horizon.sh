#!/bin/bash
#########################################################################
# File Name: environment.sh
# Author: meetbill
# mail: meetbill@163.com
# Created Time: 2017-07-17 19:05:07
# Install Horizon script
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

    if [[ -f /etc/openstack-control-script-config/horizon-installed ]]
    then
        echo ""
        echo "### This module was already completed. Exiting !"
        echo ""
        exit 0
    fi
}
#}}}
#{{{install_configure_horizon
install_configure_horizon()
{
    echo ""
    echo "### 1. Install and configure Dashboard"
    echo ""
    yum -y install openstack-dashboard
    mv /etc/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings.bak
    cp /etc/openstack-control-script-config/local_settings /etc/openstack-dashboard/local_settings
    
    #
    # Change Time zone
    # 
    
    sed -r -i "s/CUSTOM_TIMEZONE/$TIMEZONE/g" /etc/openstack-dashboard/local_settings
    sed -r -i "s/_CONTROLLER/$CONTROLLER_NODES/g" /etc/openstack-dashboard/local_settings  

    #
    # If you chose networking option 1, disable support for layer-3 networking services:
    # 
    case $NETWORK_OPT in
    provider)
        cat <<eof >> /etc/openstack-dashboard/local_settings
OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': False,
    'enable_quotas': False,
    'enable_ipv6': True,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_lb': False,
    'enable_firewall': False,
    'enable_vpn': False,
    'enable_fip_topology_check': False,
    'default_ipv4_subnet_pool_label': None,
    'default_ipv6_subnet_pool_label': None,
    'profile_support': None,
    'supported_provider_types': ['*'],
    'supported_vnic_types': ['*'],
}
eof
        ;;
    self-service)
        cat <<eof >> /etc/openstack-dashboard/local_settings
OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': True,
    'enable_quotas': True,
    'enable_ipv6': True,
    'enable_distributed_router': True,
    'enable_ha_router': False,
    'enable_lb': True,
    'enable_firewall': True,
    'enable_vpn': True,
    'enable_fip_topology_check': False,
    'default_ipv4_subnet_pool_label': None,
    'default_ipv6_subnet_pool_label': None,
    'profile_support': None,
    'supported_provider_types': ['*'],
    'supported_vnic_types': ['*'],
}
eof
        ;;
    *)
        echo ""
        echo "### ERROR: Wrong network option, config this variable with"
        echo "'self-service' or 'provider'"
        echo ""
        exit 1
        ;; 
    esac
    
    sync
    sleep 5
    sync

    #
    # On Centos, we need to apply some new selinux rules for apache
    #

    echo ""
    echo "### Applying SELINUX rules for apache. This could take some time. Please wait"
    echo ""
    setsebool -P httpd_can_network_connect on


    #echo ""
    #echo "### Applying IPTABLES rules"
    #echo ""

    #iptables -A INPUT -p tcp -m multiport --dports 80,443,11211 -j ACCEPT
    #service iptables save

    echo ""
    echo "### Restart HTTP Serivce"
    echo ""
    systemctl restart httpd.service memcached.service
    sync 
    sleep 5
    sync
}
#}}}
#{{{verify_horizon
verify_horizon()
{
    echo ""
    echo "### 2. Verify Horizon"
    echo "- Now you can access http://<controller-ip>/dashboard"
    echo "- Account: admin/$ADMIN_PASS"
    echo ""
}
#}}}

main()
{
    echo "INSTALL_HORIZON = $INSTALL_HORIZON"
    env_check
    install_configure_horizon
    verify_horizon
    date > /etc/openstack-control-script-config/horizon-installed
}

main
