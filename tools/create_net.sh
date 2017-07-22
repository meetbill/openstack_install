#!/bin/bash
. /etc/openstack-control-script-config/admin-openrc
neutron net-create --shared --provider:physical_network provider --provider:network_type flat provider
START_IP_ADDRESS=192.168.1.31
END_IP_ADDRESS=192.168.1.40
DNS_RESOLVER=8.8.8.8
PROVIDER_NETWORK_GATEWAY=192.168.1.1
PROVIDER_NETWORK_CIDR=192.168.1.0/24
neutron subnet-create --name provider --allocation-pool start=$START_IP_ADDRESS,end=$END_IP_ADDRESS --dns-nameserver $DNS_RESOLVER --gateway $PROVIDER_NETWORK_GATEWAY provider $PROVIDER_NETWORK_CIDR



. /etc/openstack-control-script-config/demo-openrc
neutron net-create selfservice
DNS_RESOLVER=8.8.8.8
SELFSERVICE_NETWORK_GATEWAY=192.168.5.1
SELFSERVICE_NETWORK_CIDR=192.168.5.0/24
neutron subnet-create --name selfservice --dns-nameserver $DNS_RESOLVER --gateway $SELFSERVICE_NETWORK_GATEWAY selfservice $SELFSERVICE_NETWORK_CIDR


. /etc/openstack-control-script-config/admin-openrc
neutron net-update provider --router:external
. /etc/openstack-control-script-config/demo-openrc
neutron router-create router
neutron router-interface-add router selfservice
neutron router-gateway-set router provider

. /etc/openstack-control-script-config/demo-openrc
ssh-keygen -q -N ""
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
openstack keypair list

# 添加规则到 default 安全组
# 允许 ICMP (ping)
openstack security group rule create --proto icmp default
# 允许安全 shell (SSH) 的访问：
openstack security group rule create --proto tcp --dst-port 22 default
