#!/bin/sh
#
# @jedipunkz @kanetann 24th Aug 2012
# 
# Overview
# --------
# OpenStack All In One Instrallation Script. These compornents of OpenStack will be
# installed on 1 node. nova, glance, keystone, swift.
#
# Precondition
# ------------
# * Ubuntu Server 12.04 LTS amd64
# * Intel-VT or AMD-V machine
# * 1 NIC or more NICs
#
# +--+--+--+
# |VM|VM|VM|  192.168.4.32/27
# +--+--+--+..
# +----------+ +--------+
# |          | | br100  | 192.168.4.33/27 -> floating range : 10.200.8.32/27
# |          | +--------+
# |          | | eth0:0 | 192.168.3.1
# |   Host   | +--------+
# |          |
# |          | +--------+
# |          | |  eth0  | ${HOST_IP}
# +----------+ +--------+
# |
# +----------+
# |   CPE    |
# +----------+

set -ex

# -----------------------------------------------------------------
# Environment Parameter
# -----------------------------------------------------------------
HOST_IP='10.200.8.15'
HOST_MASK='255.255.255.0'
HOST_NETWROK='10.200.8.0'
HOST_BROADCAST='10.200.8.255'
GATEWAY='10.200.8.1'
MYSQL_PASS='secret'
FIXED_RANGE='192.168.4.1/27'
FLOATING_RANGE='10.200.8.32/27'
FLAT_NETWORK_DHCP_START='192.168.4.33'
ISCSI_IP_PREFIX='192.168.4'

# -----------------------------------------------------------------
# Setup shell environment
# -----------------------------------------------------------------
shell_env() {
    echo 'export SERVICE_ENDPOINT="http://localhost:35357/v2.0"' >> ~/.zshrc
    echo 'export SERVICE_TOKEN=admin' >> ~/.zshrc
    export SERVICE_ENDPOINT="http://localhost:35357/v2.0"
    export SERVICE_TOKEN=admin

    echo 'export SERVICE_TOKEN=admin' >> ~/.zshrc
    echo 'export OS_TENANT_NAME=admin' >> ~/.zshrc
    echo 'export OS_USERNAME=admin' >> ~/.zshrc
    echo 'export OS_PASSWORD=admin' >> ~/.zshrc
    echo 'export OS_AUTH_URL="http://localhost:5000/v2.0/"' >> ~/.zshrc
    echo 'export SERVICE_ENDPOINT=http://localhost:35357/v2.0' >> ~/.zshrc
    export SERVICE_TOKEN=admin
    export OS_TENANT_NAME=admin
    export OS_USERNAME=admin
    export OS_PASSWORD=admin
    export OS_AUTH_URL="http://localhost:5000/v2.0/"
    export SERVICE_ENDPOINT=http://localhost:35357/v2.0
}
# -----------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------
network_setup() {
    sudo apt-get update
    sudo apt-get -y install bridge-utils

    # Network Configuration
    cat <<EOF >/etc/network/interfaces
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet static
    address ${HOST_IP} 
    netmask ${HOST_MASK}
    network ${HOST_NETWORK}
    broadcast ${HOST_BROADCAST}
    gateway ${GATEWAY}
    # dns-* options are implemented by the resolvconf package, if installed
    dns-nameservers 8.8.8.8
    dns-search example.jp

auto eth0:0
iface eth0:0 inet static
    address 192.168.3.1
    netmask 255.255.255.0
    network 192.168.3.0
    broadcast 192.168.3.255
EOF
    sudo /etc/init.d/networking restart 

    # NTP Server
    sudo apt-get -y install ntp

cat <<EOF >/etc/ntp.conf
server ntp.ubuntu.com
server 127.127.1.0
fudge 127.127.1.0 stratum 10
EOF

    sudo service ntp restart
}

# -----------------------------------------------------------------
# Database
# -----------------------------------------------------------------
database_setup() {
    echo mysql-server-5.5 mysql-server/root_password password ${MYSQL_PASS} | debconf-set-selections
    echo mysql-server-5.5 mysql-server/root_password_again password ${MYSQL_PASS} | debconf-set-selections
    sudo apt-get -y install mysql-server python-mysqldb
    #sudo sed -i -e 's/bind-address       = 127.0.0.1/bind-address       = 0.0.0.0/' /etc/mysql/my.cnf
    sudo sed -i -e 's/127.0.0.1/0.0.0.0/' /etc/mysql/my.cnf
    sudo restart mysql

    # Creating Databases
    sudo mysql -uroot -p${MYSQL_PASS} -e 'CREATE DATABASE nova;'
    sudo mysql -uroot -p${MYSQL_PASS} -e 'CREATE USER novadbadmin;'
    sudo mysql -uroot -p${MYSQL_PASS} -e "GRANT ALL PRIVILEGES ON nova.* TO 'novadbadmin'@'%';"
    sudo mysql -uroot -p${MYSQL_PASS} -e "SET PASSWORD FOR 'novadbadmin'@'%' = PASSWORD('novasecret');"

    sudo mysql -uroot -p${MYSQL_PASS} -e 'CREATE DATABASE glance;'
    sudo mysql -uroot -p${MYSQL_PASS} -e 'CREATE USER glancedbadmin;'
    sudo mysql -uroot -p${MYSQL_PASS} -e "GRANT ALL PRIVILEGES ON glance.* TO 'glancedbadmin'@'%';"
    sudo mysql -uroot -p${MYSQL_PASS} -e "SET PASSWORD FOR 'glancedbadmin'@'%' = PASSWORD('glancesecret');"

    sudo mysql -uroot -p${MYSQL_PASS} -e 'CREATE DATABASE keystone;'
    sudo mysql -uroot -p${MYSQL_PASS} -e 'CREATE USER keystonedbadmin;'
    sudo mysql -uroot -p${MYSQL_PASS} -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystonedbadmin'@'%';"
    sudo mysql -uroot -p${MYSQL_PASS} -e "SET PASSWORD FOR 'keystonedbadmin'@'%' = PASSWORD('keystonesecret');"
}

# -----------------------------------------------------------------
# Keystone 
# -----------------------------------------------------------------
keystone_setup() {
    sudo apt-get -y install keystone python-keystone python-keystoneclient
    sudo sed -i -e 's/admin_token = ADMIN/admin_token = admin/' /etc/keystone/keystone.conf
    sudo sed -i -e "s#sqlite:////var/lib/keystone/keystone.db#mysql://keystonedbadmin:keystonesecret@${HOST_IP}/keystone#" /etc/keystone/keystone.conf

    sudo service keystone restart
    sudo keystone-manage db_sync

    # Creating Tenants
    keystone tenant-create --name admin
    keystone tenant-create --name service

    # Creating Users
    keystone user-create --name admin --pass admin --email admin@openstack02.cpi.ad.jp
    keystone user-create --name nova --pass nova --email admin@openstack02.cpi.ad.jp
    keystone user-create --name glance --pass glance --email admin@openstack02.cpi.ad.jp
    keystone user-create --name swift --pass swift --email admin@openstack02.cpi.ad.jp

    # Creating Roles
    keystone role-create --name admin
    keystone role-create --name Member

    # Listing Tenants, Users and Roles
    keystone tenant-list
    keystone user-list
    keystone role-list

    # Adding Roles to Users in Tenants
    USER_LIST_ID_ADMIN=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'admin'" --skip-column-name --silent`
    ROLE_LIST_ID_ADMIN=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from role where name = 'admin'" --skip-column-name --silent`
    TENANT_LIST_ID_ADMIN=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from tenant where name = 'admin'" --skip-column-name --silent`

    USER_LIST_ID_NOVA=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'nova'" --skip-column-name --silent`
    TENANT_LIST_ID_SERVICE=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from tenant where name = 'service'" --skip-column-name --silent`

    USER_LIST_ID_GLANCE=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'glance'" --skip-column-name --silent`
    USER_LIST_ID_SWIFT=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'swift'" --skip-column-name --silent`

    ROLE_LIST_ID_MEMBER=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from role where name = 'Member'" --skip-column-name --silent`

    # To add a role of 'admin' to the user 'admin' of the tenant 'admin'.
    keystone user-role-add --user $USER_LIST_ID_ADMIN --role $ROLE_LIST_ID_ADMIN --tenant_id $TENANT_LIST_ID_ADMIN

    # The following commands will add a role of 'admin' to the users 'nova', 'glance' and 'swift' of the tenant 'service'.
    keystone user-role-add --user $USER_LIST_ID_NOVA --role $ROLE_LIST_ID_ADMIN --tenant_id $TENANT_LIST_ID_SERVICE
    keystone user-role-add --user $USER_LIST_ID_GLANCE --role $ROLE_LIST_ID_ADMIN --tenant_id $TENANT_LIST_ID_SERVICE
    keystone user-role-add --user $USER_LIST_ID_SWIFT --role $ROLE_LIST_ID_ADMIN --tenant_id $TENANT_LIST_ID_SERVICE

    # The 'Member' role is used by Horizon and Swift. So add the 'Member' role accordingly.
    keystone user-role-add --user $USER_LIST_ID_ADMIN --role $ROLE_LIST_ID_MEMBER --tenant_id $TENANT_LIST_ID_ADMIN

    # Creating Services
    keystone service-create --name nova --type compute --description 'OpenStack Compute Service'
    keystone service-create --name volume --type volume --description 'OpenStack Volume Service'
    keystone service-create --name glance --type image --description 'OpenStack Image Service'
    keystone service-create --name swift --type object-store --description 'OpenStack Storage Service'
    keystone service-create --name keystone --type identity --description 'OpenStack Identity Service'
    keystone service-create --name ec2 --type ec2 --description 'EC2 Service'

    keystone service-list

    # swift, ec2, glance, volume, keystone, nova
    SERVICE_LIST_ID_OBJECT_STORE=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='object-store'" --skip-column-name --silent`
    SERVICE_LIST_ID_EC2=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='ec2'" --skip-column-name --silent`
    SERVICE_LIST_ID_IMAGE=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='image'" --skip-column-name --silent`
    SERVICE_LIST_ID_VOLUME=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='volume'" --skip-column-name --silent`
    SERVICE_LIST_ID_IDENTITY=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='identity'" --skip-column-name --silent`
    SERVICE_LIST_ID_COMPUTE=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='compute'" --skip-column-name --silent`

    # Creating Endpoints
    keystone endpoint-create --region myregion --service_id $SERVICE_LIST_ID_COMPUTE --publicurl "http://${HOST_IP}:8774/v2/\$(tenant_id)s" --adminurl "http://${HOST_IP}:8774/v2/\$(tenant_id)s" --internalurl "http://${HOST_IP}:8774/v2/\$(tenant_id)s"
    keystone endpoint-create --region myregion --service_id $SERVICE_LIST_ID_VOLUME --publicurl "http://${HOST_IP}:8776/v1/\$(tenant_id)s" --adminurl "http://${HOST_IP}:8776/v1/\$(tenant_id)s" --internalurl "http://${HOST_IP}:8776/v1/\$(tenant_id)s"
    keystone endpoint-create --region myregion --service_id $SERVICE_LIST_ID_IMAGE --publicurl "http://${HOST_IP}:9292/v1" --adminurl "http://${HOST_IP}:9292/v1" --internalurl "http://${HOST_IP}:9292/v1"
    keystone endpoint-create --region myregion --service_id $SERVICE_LIST_ID_OBJECT_STORE --publicurl "http://${HOST_IP}:8080/v1/AUTH_\$(tenant_id)s" --adminurl "http://${HOST_IP}:8080/v1" --internalurl "http://${HOST_IP}:8080/v1/AUTH_\$(tenant_id)s"
    keystone endpoint-create --region myregion --service_id $SERVICE_LIST_ID_IDENTITY --publicurl "http://${HOST_IP}:5000/v2.0" --adminurl "http://${HOST_IP}:35357/v2.0" --internalurl "http://${HOST_IP}:5000/v2.0"
    keystone endpoint-create --region myregion --service_id $SERVICE_LIST_ID_EC2 --publicurl "http://${HOST_IP}:8773/services/Cloud" --adminurl "http://${HOST_IP}:8773/services/Admin" --internalurl "http://${HOST_IP}:8773/services/Cloud"
}

# -----------------------------------------------------------------
# Glance
# -----------------------------------------------------------------
glance_setup() {
    sudo apt-get -y install glance glance-api glance-client glance-common glance-registry python-glance

    # Glance Configuration
    sudo sed -i -e 's/%SERVICE_TENANT_NAME%/service/' /etc/glance/glance-api-paste.ini
    sudo sed -i -e 's/%SERVICE_USER%/glance/' /etc/glance/glance-api-paste.ini
    sudo sed -i -e 's/%SERVICE_PASSWORD%/glance/' /etc/glance/glance-api-paste.ini

    sudo sed -i -e 's/%SERVICE_TENANT_NAME%/service/' /etc/glance/glance-registry-paste.ini
    sudo sed -i -e 's/%SERVICE_USER%/glance/' /etc/glance/glance-registry-paste.ini
    sudo sed -i -e 's/%SERVICE_PASSWORD%/glance/' /etc/glance/glance-registry-paste.ini

    sudo sed -i -e "s#sqlite:////var/lib/glance/glance.sqlite#mysql://glancedbadmin:glancesecret@${HOST_IP}/glance#" /etc/glance/glance-registry.conf
    sudo cat <<EOF >>/etc/glance/glance-registry.conf
[paste_deploy]
flavor = keystone
EOF

    sudo sed -i -e "s#sqlite:////var/lib/glance/glance.sqlite#mysql://glancedbadmin:glancesecret@${HOST_IP}/glance#" /etc/glance/glance-registry.conf
    sudo cat <<EOF >>/etc/glance/glance-api.conf
[paste_deploy]
flavor = keystone
EOF

    sudo glance-manage version_control 0
    sudo glance-manage db_sync

    mysql -uroot -p${MYSQL_PASS} -e "GRANT ALL PRIVILEGES ON glance.* TO 'glancedbadmin'@'localhost';"
    mysql -uroot -p${MYSQL_PASS} -e "SET PASSWORD FOR 'glancedbadmin'@'localhost' = PASSWORD('glancesecret');"

    sudo glance-manage db_sync

    sudo restart glance-api
    sudo restart glance-registry

    #glance index
}

# -----------------------------------------------------------------
# Nova
# -----------------------------------------------------------------
nova_setup() {
    sudo apt-get -y  install nova-api nova-cert nova-compute nova-compute-kvm nova-doc nova-network nova-objectstore nova-scheduler nova-volume rabbitmq-server novnc nova-consoleauth

    # Nova Configuration
    sudo cp /etc/nova/nova.conf  /etc/nova/nova.conf.org
    cat << EOF > /etc/nova/nova.conf
--dhcpbridge_flagfile=/etc/nova/nova.conf
--dhcpbridge=/usr/bin/nova-dhcpbridge
--logdir=/var/log/nova
--state_path=/var/lib/nova
--lock_path=/run/lock/nova
--allow_admin_api=true
--use_deprecated_auth=false
--auth_strategy=keystone
--scheduler_driver=nova.scheduler.simple.SimpleScheduler
--s3_host=${HOST_IP}
--ec2_host=${HOST_IP}
--rabbit_host=${HOST_IP}
--cc_host=${HOST_IP}
--nova_url=http://1${HOST_IP}:8774/v1.1/
--routing_source_ip=${HOST_IP}
--glance_api_servers=${HOST_IP}:9292
--image_service=nova.image.glance.GlanceImageService
--iscsi_ip_prefix=${ISCSI_IP_PREFIX}
--sql_connection=mysql://novadbadmin:novasecret@${HOST_IP}/nova
--ec2_url=http://${HOST_IP}:8773/services/Cloud
--keystone_ec2_url=http://${HOST_IP}:5000/v2.0/ec2tokens
--api_paste_config=/etc/nova/api-paste.ini
--libvirt_type=kvm
--libvirt_use_virtio_for_bridges=true
--start_guests_on_host_boot=true
--resume_guests_state_on_host_boot=true
# vnc specific configuration
--novnc_enabled=true
--novncproxy_base_url=http://${HOST_IP}:6080/vnc_auto.html
--vncserver_proxyclient_address=${HOST_IP}
--vncserver_listen=${HOST_IP}
# network specific settings
--network_manager=nova.network.manager.FlatDHCPManager
--public_interface=eth0
--flat_interface=eth0:0
--flat_network_bridge=br100
--fixed_range=${FIXED_RANGE}
--floating_range=${FLOATING_RANGE}
--network_size=32
--flat_network_dhcp_start=${FLAT_NETWORK_DHCP_START}
--flat_injected=False
--force_dhcp_release
--iscsi_helper=tgtadm
--connection_type=libvirt
--root_helper=sudo nova-rootwrap
--verbose
EOF

    sudo pvcreate /dev/sda6
    sudo vgcreate nova-volumes /dev/sda6
    sudo chown -R nova:nova /etc/nova
    sudo chmod 644 /etc/nova/nova.conf

    sudo sed -i -e 's/%SERVICE_TENANT_NAME%/service/' /etc/nova/api-paste.ini
    sudo sed -i -e 's/%SERVICE_USER%/nova/' /etc/nova/api-paste.ini
    sudo sed -i -e 's/%SERVICE_PASSWORD%/nova/' /etc/nova/api-paste.ini

    sudo nova-manage db sync

    sudo nova-manage network create private --fixed_range_v4=192.168.4.32/27 --num_networks=1 --bridge=br100 --bridge_interface=eth0:0 --network_size=32

    sudo restart libvirt-bin;sudo restart nova-network; sudo restart nova-compute; sudo restart nova-api; sudo restart nova-objectstore; sudo restart nova-scheduler; sudo service nova-volume restart; sudo restart nova-consoleauth;

    sudo nova-manage service list
}

# -----------------------------------------------------------------
# Horizon
# -----------------------------------------------------------------
horizon_setup() {
    sudo apt-get -y install openstack-dashboard
    sudo service apache2 restart
}

# -----------------------------------------------------------------
# Swift
# -----------------------------------------------------------------
swift_setup() {
    sudo apt-get -y install swift swift-proxy swift-account swift-container swift-object
    sudo apt-get -y install xfsprogs curl python-pastedeploy

    sudo fdisk -l
    sudo mkfs.xfs -i size=1024 /dev/sda7 -f

    sudo mkdir /mnt/swift_backend

    sudo cat <<EOF >>/etc/fstab
/dev/sda7 /mnt/swift_backend xfs noatime,nodiratime,nobarrier,logbufs=8 0 0
EOF

    sudo mount /mnt/swift_backend
    cd /mnt/swift_backend
    sudo mkdir node1 node2 node3 node4

    sudo chown swift.swift /mnt/swift_backend/*

    for i in {1..4}; do sudo ln -s /mnt/swift_backend/node$i /srv/node$i; done;

    sudo mkdir -p /etc/swift/account-server /etc/swift/container-server /etc/swift/object-server /srv/node1/device /srv/node2/device /srv/node3/device /srv/node4/device
    sudo mkdir /run/swift
    sudo chown -L -R swift.swift /etc/swift /srv/node[1-4]/ /run/swift
    sudo cat <<EOF >/etc/rc.local
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

sudo mkdir /run/swift
sudo chown swift.swift /run/swift

exit 0
EOF

    # Configure Rsync
    sudo sed -i -e 's/RSYNC_ENABLE=false/RSYNC_ENABLE=true/' /etc/default/rsync

    sudo service rsync restart

    # Configure Swift Components
    SWIFT_HASH_PATH_SUFFIX=`od -t x8 -N 8 -A n < /dev/random`
    sudo cat << EOF > /etc/swift/swift.conf
[swift-hash]
swift_hash_path_suffix = ${SWIFT_HASH_PATH_SUFFIX}
EOF

    sudo cat <<EOF >/etc/swift/paste.deploy
[DEFAULT]
name1 = globalvalue
name2 = globalvalue
name3 = globalvalue
set name4 = globalvalue
[pipeline:main]
pipeline = myapp
[app:myapp]
use = egg:mypkg#myapp
name2 = localvalue
set name3 = localvalue
set name5 = localvalue
name6 = localvalue
EOF

    # Configure Swift Proxy Server
    sudo cat <<EOF >/etc/swift/proxy-server.conf
[DEFAULT]
bind_port = 8080
user = swift
swift_dir = /etc/swift

[pipeline:main]
# Order of execution of modules defined below
pipeline = catch_errors healthcheck cache authtoken keystone proxy-server

[app:proxy-server]
use = egg:swift#proxy
allow_account_management = true
account_autocreate = true
set log_name = swift-proxy
set log_facility = LOG_LOCAL0
set log_level = INFO
set access_log_name = swift-proxy
set access_log_facility = SYSLOG
set access_log_level = INFO
set log_headers = True
account_autocreate = True

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:catch_errors]
use = egg:swift#catch_errors

[filter:cache]
use = egg:swift#memcache
set log_name = cache

[filter:authtoken]
paste.filter_factory = keystone.middleware.auth_token:filter_factory
auth_protocol = http
auth_host = 127.0.0.1
auth_port = 35357
auth_token = admin
service_protocol = http
service_host = 127.0.0.1
service_port = 5000
admin_token = admin
admin_tenant_name = service
admin_user = swift
admin_password = swift
delay_auth_decision = 0

[filter:keystone]
paste.filter_factory = keystone.middleware.swift_auth:filter_factory
operator_roles = admin, swiftoperator
is_admin = true
EOF

    # Configure Swift Account Server
    sudo cat <<EOF >/etc/swift/account-server.conf
[DEFAULT]
bind_ip = 0.0.0.0
workers = 2

[pipeline:main]
pipeline = account-server

[app:account-server]
use = egg:swift#account

[account-replicator]

[account-auditor]

[account-reaper]
EOF

    sudo cat <<EOF >/etc/swift/account-server/1.conf
[DEFAULT]
devices = /srv/node1
mount_check = false
bind_port = 6012
user = swift
log_facility = LOG_LOCAL2

[pipeline:main]
pipeline = account-server

[app:account-server]
use = egg:swift#account

[account-replicator]
vm_test_mode = no

[account-auditor]

[account-reaper]
EOF

    sudo cp /etc/swift/account-server/1.conf /etc/swift/account-server/2.conf
    sudo cp /etc/swift/account-server/1.conf /etc/swift/account-server/3.conf
    sudo cp /etc/swift/account-server/1.conf /etc/swift/account-server/4.conf

    sudo sed -i 's/6012/6022/g;s/LOCAL2/LOCAL3/g;s/node1/node2/g' /etc/swift/account-server/2.conf
    sudo sed -i 's/6012/6032/g;s/LOCAL2/LOCAL4/g;s/node1/node3/g' /etc/swift/account-server/3.conf
    sudo sed -i 's/6012/6042/g;s/LOCAL2/LOCAL5/g;s/node1/node4/g' /etc/swift/account-server/4.conf

    # Configure Swift Container Server
    # sudo vi /etc/swift/container-server.conf
    sudo cat <<EOF >/etc/swift/container-server.conf
[DEFAULT]
bind_ip = 0.0.0.0
workers = 2

[pipeline:main]
pipeline = container-server

[app:container-server]
use = egg:swift#container

[container-replicator]

[container-updater]

[container-auditor]

[container-sync]
EOF

    sudo cat <<EOF >/etc/swift/container-server/1.conf
[DEFAULT]
devices = /srv/node1
mount_check = false
bind_port = 6011
user = swift
log_facility = LOG_LOCAL2

[pipeline:main]
pipeline = container-server

[app:container-server]
use = egg:swift#container

[container-replicator]
vm_test_mode = no

[container-updater]

[container-auditor]

[container-sync]
EOF

    sudo cp /etc/swift/container-server/1.conf /etc/swift/container-server/2.conf
    sudo cp /etc/swift/container-server/1.conf /etc/swift/container-server/3.conf
    sudo cp /etc/swift/container-server/1.conf /etc/swift/container-server/4.conf
    sudo sed -i 's/6011/6021/g;s/LOCAL2/LOCAL3/g;s/node1/node2/g' /etc/swift/container-server/2.conf
    sudo sed -i 's/6011/6031/g;s/LOCAL2/LOCAL4/g;s/node1/node3/g' /etc/swift/container-server/3.conf
    sudo sed -i 's/6011/6041/g;s/LOCAL2/LOCAL5/g;s/node1/node4/g' /etc/swift/container-server/4.conf

    # Configure Swift Object Server
    sudo cat <<EOF >/etc/swift/object-server.conf
[DEFAULT]
bind_ip = 0.0.0.0
workers = 2

[pipeline:main]
pipeline = object-server

[app:object-server]
use = egg:swift#object

[object-replicator]

[object-updater]

[object-auditor]
EOF

    sudo cat <<EOF >/etc/swift/object-server/1.conf
[DEFAULT]
devices = /srv/node1
mount_check = false
bind_port = 6010
user = swift
log_facility = LOG_LOCAL2

[pipeline:main]
pipeline = object-server

[app:object-server]
use = egg:swift#object

[object-replicator]
vm_test_mode = no

[object-updater]

[object-auditor]
EOF

    sudo cp /etc/swift/object-server/1.conf  /etc/swift/object-server/2.conf
    sudo cp /etc/swift/object-server/1.conf  /etc/swift/object-server/3.conf
    sudo cp /etc/swift/object-server/1.conf  /etc/swift/object-server/4.conf
    sudo sed -i 's/6010/6020/g;s/LOCAL2/LOCAL3/g;s/node1/node2/g' /etc/swift/object-server/2.conf
    sudo sed -i 's/6010/6030/g;s/LOCAL2/LOCAL4/g;s/node1/node3/g' /etc/swift/object-server/3.conf
    sudo sed -i 's/6010/6040/g;s/LOCAL2/LOCAL5/g;s/node1/node4/g' /etc/swift/object-server/4.conf

    # Configure Swift Rings
    cd /etc/swift
    sudo swift-ring-builder object.builder create 18 3 1
    sudo swift-ring-builder container.builder create 18 3 1
    sudo swift-ring-builder account.builder create 18 3 1
    sudo swift-ring-builder object.builder add z1-127.0.0.1:6010/device 1
    sudo swift-ring-builder object.builder add z2-127.0.0.1:6020/device 1
    sudo swift-ring-builder object.builder add z3-127.0.0.1:6030/device 1
    sudo swift-ring-builder object.builder add z4-127.0.0.1:6040/device 1
    sudo swift-ring-builder object.builder rebalance
    sudo swift-ring-builder container.builder add z1-127.0.0.1:6011/device 1
    sudo swift-ring-builder container.builder add z2-127.0.0.1:6021/device 1
    sudo swift-ring-builder container.builder add z3-127.0.0.1:6031/device 1
    sudo swift-ring-builder container.builder add z4-127.0.0.1:6041/device 1
    sudo swift-ring-builder container.builder rebalance
    sudo swift-ring-builder account.builder add z1-127.0.0.1:6012/device 1
    sudo swift-ring-builder account.builder add z2-127.0.0.1:6022/device 1
    sudo swift-ring-builder account.builder add z3-127.0.0.1:6032/device 1
    sudo swift-ring-builder account.builder add z4-127.0.0.1:6042/device 1
    sudo swift-ring-builder account.builder rebalance

    # Starting Swift services
    sudo swift-init main start
    sudo swift-init rest start

    # Testing Swift
    sudo chown -R swift.swift /etc/swift
    swift -v -V 2.0 -A http://127.0.0.1:5000/v2.0/ -U service:swift -K swift stat
}

# -----------------------------------------------------------------
# Main Function
# -----------------------------------------------------------------
shell_env
network_setup
database_setup
keystone_setup
glance_setup
nova_setup
horizon_setup
swift_setup

