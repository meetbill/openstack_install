#!/bin/bash
#########################################################################
# File Name: environment.sh
# Author: meetbill
# mail: meetbill@163.com
# Created Time: 2017-07-17 19:05:07
# Environments config
#########################################################################

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

if [[ -f /etc/openstack-control-script-config/main-config.rc ]]
then
	source /etc/openstack-control-script-config/main-config.rc
else
	echo " ERROR:Can't access my config file. Aborting !"
	echo ""
	exit 0
fi

if [[ -f /etc/openstack-control-script-config/environment-compute-installed ]]
then
	echo "This module was installed. Exiting"
	exit 0
fi
#{{{configure_name_resolution
configure_name_resolution()
{
	echo "### 1. Hostname config"
	if ! grep -q "$CONTROLLER_NODES_IP 	$CONTROLLER_NODES"  /etc/hosts;
	then
		echo "$CONTROLLER_NODES_IP 	$CONTROLLER_NODES" >> /etc/hosts
	fi
	#
	# String to array
	# 
	
	temp_array_1=($COMPUTE_NODES)
	temp_array_2=($COMPUTE_NODES_IP)

	len_1=${#temp_array_1[@]}
	len_2=${#temp_array_2[@]}

	#
	# Check config
	# 
	
	if [[ $len_1 != $len_2 ]]
	then
		echo ""
		echo "### ERROR: Wrong config COMPUTE_NODES and COMPUTE_NODES_IP"
		echo "### Same size"
		echo ""
		exit 1
	fi

	#
	# Append to /etc/hosts, skip if existed
	for i in ${!temp_array_1[@]};
	do
		if ! grep -q "${temp_array_2[$i]} 	${temp_array_1[$i]}"  /etc/hosts;
		then
			echo "${temp_array_2[$i]} 	${temp_array_1[$i]}" >> /etc/hosts
		fi
	done
	echo "### Configure name resolution is Done!"
}
#}}}
#{{{install_configure_ntp
install_configure_ntp()
{
	echo "### 2. Install ntp-chrony"
	yum install chrony wget -y
	if [[ $? -eq 0 ]]
	then
		sed -i '/server/d' /etc/chrony.conf
		echo "server $CONTROLLER_NODES iburst" >> /etc/chrony.conf
		systemctl enable chronyd.service
		systemctl start chronyd.service
		chronyc sources
	else
		clear
		echo '### Error: install chrony'
	fi
}
#}}}
#{{{install_openstack_packages
install_openstack_packages()
{

	echo "### 3. Enable the OpenStack repository¶"
	if [[ $USE_PRIVATE_REPOS == "no" ]]
	then
		yum -y install centos-release-openstack-ocata
	fi
	yum -y install python-openstackclient openstack-selinux crudini
}
#}}}
main(){
	configure_name_resolution
	install_configure_ntp
	install_openstack_packages
	date > /etc/openstack-control-script-config/environment-compute-installed

    # Create OpenStack client environment scripts
cat > $ADMIN_RC_FILE <<eof
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://$CONTROLLER_NODES:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
eof
	chmod +x $ADMIN_RC_FILE
cat > $DEMO_RC_FILE <<eof
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=demo
export OS_USERNAME=demo
export OS_PASSWORD=$DEMO_PASS
export OS_AUTH_URL=http://$CONTROLLER_NODES:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
eof
	chmod +x $DEMO_RC_FILE

	unset OS_TOKEN OS_URL OS_IDENTITY_API_VERSION
	if [[ -f /etc/openstack-control-script-config/$ADMIN_RC_FILE ]]
	then
		rm /etc/openstack-control-script-config/$ADMIN_RC_FILE
	fi

	if [[ -f /etc/openstack-control-script-config/$DEMO_RC_FILE ]]
	then
		rm /etc/openstack-control-script-config/$DEMO_RC_FILE
	fi

	cp $ADMIN_RC_FILE /etc/openstack-control-script-config/
	cp $DEMO_RC_FILE /etc/openstack-control-script-config/
}

main
