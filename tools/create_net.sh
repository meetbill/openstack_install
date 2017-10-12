#!/bin/bash
if [[ ! -f /etc/openstack-control-script-config/main-config.rc  ]] 
then
    echo "not config file"
    exit 1
fi

. /etc/openstack-control-script-config/main-config.rc

#########################################################################################

START_IP_ADDRESS=192.168.1.31
END_IP_ADDRESS=192.168.1.40
DNS_RESOLVER=8.8.8.8
PROVIDER_NETWORK_GATEWAY=192.168.1.1
PROVIDER_NETWORK_CIDR=192.168.1.0/24

#########################################################################################

#{{{create_virtualnetworks_provider
create_virtualnetworks_provider()
{
    echo "### ${FUNCNAME}"
    . /etc/openstack-control-script-config/admin-openrc
    network_check=$(openstack network list | grep provider | wc -l)
    if [[ "w${network_check}" == "w0" ]]
    then
        openstack network create --share --external \
            --provider-physical-network provider \
            --provider-network-type flat provider
    else
        echo "the network provider is added"
    fi

    network_subnet_check=$(openstack subnet list | grep provider | wc -l)
    if [[ "w${network_subnet_check}" == "w0" ]]
    then
        openstack subnet create --network provider \
            --allocation-pool start=${START_IP_ADDRESS},end=${END_IP_ADDRESS} \
            --dns-nameserver ${DNS_RESOLVER} --gateway ${PROVIDER_NETWORK_GATEWAY} \
            --subnet-range ${PROVIDER_NETWORK_CIDR} provider
    else
        echo "the network provider subnet is added"
    fi
}
#}}}
#{{{create_virtualnetworks_selfservice
create_virtualnetworks_selfservice()
{

    echo "### ${FUNCNAME}"
    . /etc/openstack-control-script-config/admin-openrc
    network_check=$(openstack network list | grep provider | wc -l)
    if [[ "w${network_check}" == "w0" ]]
    then
        openstack network create --share --external \
            --provider-physical-network provider \
            --provider-network-type flat provider
    else
        echo "the network provider is added"
    fi

    network_subnet_check=$(openstack subnet list | grep provider | wc -l)
    if [[ "w${network_subnet_check}" == "w0" ]]
    then
        openstack subnet create --network provider \
            --allocation-pool start=${START_IP_ADDRESS},end=${END_IP_ADDRESS} \
            --dns-nameserver ${DNS_RESOLVER} --gateway ${PROVIDER_NETWORK_GATEWAY} \
            --subnet-range ${PROVIDER_NETWORK_CIDR} provider
    else
        echo "the network provider subnet is added"
    fi

    . /etc/openstack-control-script-config/demo-openrc
    network_check=$(openstack network list | grep selfservice | wc -l)
    if [[ "w${network_check}" == "w0" ]]
    then
        openstack network create selfservice
        DNS_RESOLVER=8.8.8.8
        SELFSERVICE_NETWORK_GATEWAY=192.168.5.1
        SELFSERVICE_NETWORK_CIDR=192.168.5.0/24
        openstack subnet create --network selfservice \
            --dns-nameserver ${DNS_RESOLVER} --gateway ${SELFSERVICE_NETWORK_GATEWAY} \
            --subnet-range ${SELFSERVICE_NETWORK_CIDR} selfservice
        . /etc/openstack-control-script-config/admin-openrc
        #neutron net-update provider --router:external
        . /etc/openstack-control-script-config/demo-openrc
        neutron router-create router
        neutron router-interface-add router selfservice
        neutron router-gateway-set router provider
    else
        echo "the network selfservice is added"
    fi
}
#}}}
#{{{create_flavor
create_flavor()
{
    echo "### ${FUNCNAME}"

    . /etc/openstack-control-script-config/admin-openrc
    flavor_check=$( openstack flavor list |grep "m1.nano" | wc -l)
    if [[ "w${flavor_check}" == "w0" ]]
    then
        openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 m1.nano
    fi
}
#}}}
#{{{generate_key_pair
generate_key_pair()
{
    echo "### ${FUNCNAME}"
    . /etc/openstack-control-script-config/demo-openrc
    key_check=$(openstack keypair list | grep mykey | wc -l)
    if [[ "w${key_check}" == "w0"  ]]
    then
    ssh-keygen -q -N ""
    openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
    fi
    openstack keypair list
}
#}}}
#{{{add_securitygroup_rules
add_securitygroup_rules()
{
    echo "### ${FUNCNAME}"
    . /etc/openstack-control-script-config/demo-openrc
    # 添加规则到 default 安全组
    security_check=$(openstack security group rule list | grep icmp | wc -l)
    if [[ "w${security_check}" == "w0"  ]]
    then
        # 允许 ICMP (ping)
        openstack security group rule create --proto icmp default
    fi
    security_check=$(openstack security group rule list | grep tcp | wc -l)
    if [[ "w${security_check}" == "w0"  ]]
    then
        # 允许安全 shell (SSH) 的访问：
        openstack security group rule create --proto tcp --dst-port 22 default
    fi
}
#}}}

main_provider()
{
    create_virtualnetworks_provider
    create_flavor
    generate_key_pair
    add_securitygroup_rules
}
main_selfservice()
{
    create_virtualnetworks_selfservice
    create_flavor
    generate_key_pair
    add_securitygroup_rules
}
usage="$0 provider/selfservice"
if [ $# == 0 ];then
    echo ${usage}
else
    case $1 in
        provider)
            main_provider
            ;;
        selfservice)
            main_selfservice
            ;;
        *)
            echo ${usage}
            exit 1
            ;;
    esac                                                                                                                                       
fi


