#!/bin/bash
#set -x

	sed -i 's/#EXTRA_GROUPS=.*/EXTRA_GROUPS="video"/g' /etc/adduser.conf
	sed -i 's/#ADD_EXTRA_GROUPS=.*/ADD_EXTRA_GROUPS=1/g' /etc/adduser.conf
	echo -n "rootwait rw console=ttyS2,1500000 console=tty1 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory" > /etc/kernel/cmdline
	echo -n " text plymouth.ignore-serial-consoles apparmor=1 security=apparmor apparmor=1 security=apparmor" >> /etc/kernel/cmdline
	rm -f /var/lib/dbus/machine-id
	true > /etc/machine-id
	touch /var/log/syslog
	chown syslog:adm /var/log/syslog
	ssh-keygen -A

	apt-get -y purge cloud-init flash-kernel fwupd ufw
	apt-get -y autoremove
	apt-get  clean
	
