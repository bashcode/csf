#!/bin/bash
#
# by Felipe Montes, @Gudw4L <gudwal@live.com>
#


RED='\033[01;31m'
GREEN='\033[01;32m'
RESET='\033[0m'
ver=v2.07;

TEMPDIR="/root/tmp/csf"

uninstall() {
	if [ -e /etc/csf/bashcode ]
		then
			installver=$(cat /etc/csf/bashcode)
			echo "The bashcode $installver was used, proceeding with uninstallation."
		elif [ "$(echo $switch)" = "-u" ]
			then
			{
				echo "Use -uf if you want to force the installer to attempt an uninstallation."
				exit 1;
			}
		elif [ "$(echo $switch)" = "-uf" ]
			then
			{
				echo "WARNING :: FORCE UNINSTALL DETECTED. PROCEEDING WITH UNINSTALLATION."
				sleep 1
				echo "Press Enter to continue or ctrl^C to quit."
				read
			}
	fi

	echo "WARNING :: THERE MIGHT BE NO FIREWALL ON THIS SERVER AFTER UNINSTALLATION. PLEASE INSTALL A NEW FIREWALL IF NEEDED!"

	echo "STOPPING CSF"
	/etc/init.d/csf stop
	echo "STOPPING LFD"
	/etc/init.d/lfd stop
	echo "REMOVING CSF and LFD init SCRIPTS"
	rm -fv /etc/init.d/csf
	rm -fv /etc/init.d/lfd
	echo "FLUSHING IPTABLES RULES"
	/sbin/iptables --flush
	/etc/init.d/iptables save
	/etc/init.d/iptables restart
	echo "REMOVING CSF AND LFD FROM CHKCONFIG"
	chkconfig --del csf
	chkconfig --del lfd
	echo "REMOVING THE CSF AND LFD SYSLINKS"
	rm -fv /usr/sbin/csf
	rm -fv /usr/sbin/lfd
	echo "BACKING UP THE CSF CONFIGURATION"
	mv /etc/csf /etc/csf.bak
	echo "REMOVING THE CSF WHM PLUGIN"
	rm -fv /usr/local/cpanel/whostmgr/docroot/cgi/addon_csf.cgi
	rm -rfv /usr/local/cpanel/whostmgr/docroot/cgi/csf/
	rm -fv /usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf.cgi
	rm -rfv /usr/local/cpanel/whostmgr/docroot/cgi/configserver/
	echo "REMOVING LFD FROM CHKSERVD"
	sed -ie 's/lfd:1//g' /etc/chkserv.d/chkservd.conf
	echo "RESTARTING cPanel"
	/etc/init.d/cpanel restart
	echo " "
	echo " "
	echo "WARNING :: THERE MIGHT NOT BE A FIREWALL ON THIS SERVER. PLEASE INSTALL A NEW FIREWALL IF NEEDED!"
}

prepare() {

echo -ne "$RED

     _____  _____ ______ 
   / ____|/ ____|  ____|
   | |    | (___ | |__   
   | |     \___ \|  __|  
   | |____ ____) | |     
    \_____|_____/|_|     $RESET $GREEN Automated Installation ver $ver $RESET"  
       

	if [ ! -d "$TEMPDIR" ]; then mkdir -p "$TEMPDIR" &>/dev/null; fi
	cd "$TEMPDIR"

	# CSF won't work if cPanel has the SMTP tweak enabled
        echo " ";
        echo " ";
        echo -n "Checking for SMTP tweak: "
	if [ -f "/var/cpanel/smtpgidonlytweak" ]; then
		echo "Found (disabling)"
		rm -f /var/cpanel/smtpgidonlytweak &>/dev/null
		echo -n "Restarting cPanel: "
		/etc/init.d/cpanel restart &>/dev/null
		echo "OK"
	else
		echo "OK (not found)"
	fi

        # check for conflicting products.
        if [ -e "/etc/cron.d/bfd" ]; then 
                echo "ERROR: BFD is installed. Exiting."
                exit 2
        else
            	echo "OK: BFD not found (conflicting product)"
        fi
	if [ -e "/etc/cron.daily/fw" ]; then 
                echo "ERROR: APF appears to be installed and will conflict. Exiting."
                exit 2
        else
            	echo "OK: APF not found (conflicting product)"
        fi

        echo
        cd "$TEMPDIR"

	echo

	#check for CentOS 6
	release=$(cat /etc/redhat-release | awk '{print $3}' | cut -d . -f1);
	if [ $release -ge 6  ]; then
		releasev=$(cat /etc/redhat-release | awk '{print $3}')
		echo "CentOS $releasev detected : Skipping klogd and syslog checks."
	else
        	# Turn on klogd if skipped in syslog
        	sed -ie 's/passed klogd skipped #//g' /etc/init.d/syslog
        	/etc/init.d/syslog restart

        	# check for requirements.
        	klogd_enabled=$(grep -vE "^\#" /etc/init.d/syslog|grep klogd|wc -l)
	        if [ "0" = "$klogd_enabled" ]; then echo "ERROR: klogd is required but does not appear to be configured. Exiting." ; exit 2 ; fi
        	klogd_running=$(ps ax|grep klog|grep -v grep|wc -l)
	        if [ "0" = "$klogd_running" ]; then echo "ERROR: klogd is required but does not appear to be running. Exiting." ; exit 2 ; fi
        fi   


}

install_csf() {
        echo -n "Downloading CSF: "
        wget http://www.configserver.com/free/csf.tgz -O "$TEMPDIR/csf.tgz" &>/dev/null
        echo "OK"
        tar -zxvf csf.tgz &>/dev/null
        cd ./csf
        echo -n "Installing CSF: "
        sh install.sh &>/dev/null
        if [ "0" = "$?" ]; then
	{
                echo "OK"
		echo "install-csf $ver" > /etc/csf/bashcode;
		echo "ConfigServer Firewall installed" $(date +%D)". Configuration at /etc/csf/" >> /root/.motd
        }
	else
                echo "Failed"
                exit 2
        fi
}

uncomment_tweak() {
        if [ -z "$3" ]; then echo "uncomment_tweak requires <item> <replacement> <filename>" ; return ; fi
        if [ ! -f "$3" ]; then echo "uncomment_tweak: file does not exist ($2)" ; return ;  fi
        sed -i -e 's/^\#${1}.*/${2}/g' -e 's/${1}.*/${2}/g' "${3}"
}

configure_csf_allow(){
            
        if [ -f "/etc/resolv.conf" ]; then
          for ip in `grep nameserver /etc/resolv.conf | sed -e "s/^nameserver //g"`; do
            echo "- Adding $ip to /etc/csf/csf.allow and csf.ignore (from resolv.conf)"
            echo "$ip:tcp:in:s=53 # DNS Server (do not remove)" >> /etc/csf/csf.allow
            echo "$ip:udp:in:s=53 # DNS Server (do not remove)" >> /etc/csf/csf.allow
            echo "$ip:tcp:out:d=53 # DNS Server (do not remove)" >> /etc/csf/csf.allow
            echo "$ip:udp:out:d=53 # DNS Server (do not remove)" >> /etc/csf/csf.allow
            echo "$ip # DNS Server (do not remove)" >> /etc/csf/csf.ignore
          done

	echo "Editing: /etc/csf/csf.ignore"
	  # whitelist local IPs:
	  grep -E "^IPADDR" /etc/sysconfig/network-scripts/ifcfg*|awk -F"=" '{print $2}'|while read ip; do
		grep "$ip" /etc/csf/csf.ignore &>/dev/null || echo "- Adding $ip to /etc/csf/csf.ignore (Local IP)" && \
		echo "$ip # Local IP: Do not remove" >> /etc/csf/csf.ignore
	  done

	# whitelist gateway:

	for ip in `grep -E "^GATEWAY=" /etc/sysconfig/network-scripts/ifcfg*|awk -F"=" '{print $2}'`; do
		grep "$ip" /etc/csf/csf.ignore &>/dev/null || echo "- Adding $ip to /etc/csf/csf.ignore (Gateway)" && \
		echo "$ip # Local Gateway: Do not remove" >> /etc/csf/csf.ignore
	done

  # whitelist other IPs that are commonly used:
  
    grep "$ip" /etc/csf/csf.ignore &>/dev/null || echo "- Adding $ip to /etc/csf/csf.ignore (common DNS)" && \

	  for ip in \
		74.125.0.0/24 66.249.64.0/19 ; do
		grep "$ip" /etc/csf/csf.ignore &>/dev/null || echo "- Adding $ip to /etc/csf/csf.ignore (Google)" && \
		echo "$ip # GoogleBot: Do not remove" >> /etc/csf/csf.ignore
	  done

	  for ip in \
		209.191.64.0/18; do
		grep "$ip" /etc/csf/csf.ignore &>/dev/null || echo "- Adding $ip to /etc/csf/csf.ignore (Yahoo)" && \
		echo "$ip # Yahoo Crawler: Do not remove" >> /etc/csf/csf.ignore
	  done
      
      fi

}

configure_csf_conf(){
        echo "Editing: /etc/csf/csf.conf"
        echo "- Setting TESTING=0"
        sed -ie "s/^TESTING = .*/TESTING = \"0\"/g" /etc/csf/csf.conf

        echo "- Setting AUTO_UPDATES=1"
        sed -ie "s/^AUTO_UPDATES = .*/AUTO_UPDATES = \"1\"/g" /etc/csf/csf.conf

        echo "- Setting LF_TRIGGER_PERM to 15 minutes (default)"
        sed -ie "s/^LF_TRIGGER_PERM = .*/LF_TRIGGER_PERM = \"900\"/g" /etc/csf/csf.conf

        echo "- Setting SSH failure to 20 / 30 min ban"
        sed -ie "s/^LF_SSHD = .*/LF_SSHD = \"20\"/g" /etc/csf/csf.conf
        sed -ie "s/^LF_SSHD_PERM = .*/LF_SSHD_PERM = \"3600\"/g" /etc/csf/csf.conf

        echo "- Setting SMTP failure rate to 20 / 5 min ban"

        sed -ie "s/^LF_SMTPAUTH = .*/LF_SMTPAUTH = \"20\"/g" /etc/csf/csf.conf
        sed -ie "s/^LF_SMTPAUTH = .*/LF_SMTPAUTH = \"300\"/g" /etc/csf/csf.conf

        echo "- Setting POP3 failure rate to 20 / 5min ban"
        sed -ie "s/^LF_POP3D = .*/LF_POP3D = \"20\"/g" /etc/csf/csf.conf
        sed -ie "s/^LF_POP3D_PERM = .*/LF_POP3D_PERM = \"300\"/g" /etc/csf/csf.conf

        echo "- Setting HTTP auth failure detection to 0 (disabled)"
        sed -ie "s/^LF_HTACCESS = .*/LF_HTACCESS = \"0\"/g" /etc/csf/csf.conf
        sed -ie "s/^LF_HTACCESS_PERM = .*/LF_HTACCESS_PERM = \"300\"/g" /etc/csf/csf.conf

        echo "- Setting MODSEC failure detection to 0 (disabled)"
        sed -ie "s/^LF_MODSEC = .*/LF_MODSEC = \"0\"/g" /etc/csf/csf.conf
        sed -ie "s/^LF_MODSEC_PERM = .*/LF_MODSEC_PERM = \"300\"/g" /etc/csf/csf.conf

        echo "- Setting cPanel login failures to 15 / 15min ban"
        sed -ie "s/^LF_CPANEL = .*/LF_CPANEL = \"15\"/g" /etc/csf/csf.conf
        sed -ie "s/^LF_CPANEL_PERM = .*/LF_CPANEL_PERM = \"3600\"/g" /etc/csf/csf.conf

        echo "- Setting suhosin detection to 0 (disabled)"
        sed -ie "s/^LF_SUHOSIN = .*/LF_SUHOSIN = \"0\"/g" /etc/csf/csf.conf
        sed -ie "s/^LF_SUHOSIN_PERM = .*/LF_SUHOSIN_PERM = \"180\"/g" /etc/csf/csf.conf

        echo "- Setting LF_SPAMHAUS=604800" # 1 day ban if on SpamHaus list
        sed -ie "s/^LF_SPAMHAUS = \"0\"/LF_SPAMHAUS = \"86400\"/g" /etc/csf/csf.conf

        echo "- Setting CT_LIMIT=300"
        sed -ie "s/^CT_LIMIT = .*/CT_LIMIT = \"300\"/g" /etc/csf/csf.conf

        echo "- Setting CT_BLOCK_TIME=900"
        sed -ie "s/^CT_BLOCK_TIME = .*/CT_BLOCK_TIME = \"900\"/g" /etc/csf/csf.conf

	      echo "- Setting LF_SCRIPT_LIMIT=1000"
	      sed -ie "s/^LF_SCRIPT_LIMIT = .*/LF_SCRIPT_LIMIT = \"1000\"/g" /etc/csf/csf.conf

        echo "- Setting LF_SCRIPT_ALERT=1"
        sed -ie "s/^LF_SCRIPT_ALERT = .*/LF_SCRIPT_ALERT = \"1\"/g" /etc/csf/csf.conf

        echo "- Setting LF_DSHIELD=86400"
        sed -ie "s/LF_DSHIELD = \"0\"/LF_DSHIELD = \"86400\"/g" /etc/csf/csf.conf

        echo "- Disabling email warning for SSH login"
        sed -ie "s/^LF_SSH_EMAIL_ALERT = \"1\"/LF_SSH_EMAIL_ALERT = \"0\"/g" /etc/csf/csf.conf

        echo "- Connection Tracking Options"
        echo "  Setting CT_INTERVAL=120"
        sed -ie "s/^CT_INTERVAL = .*/CT_INTERVAL = \"120\"/g" /etc/csf/csf.conf

        echo "  Setting connection blocks to temporary"
        sed -ie "s/^CT_PERMANENT = .*/CT_PERMANENT = \"0\"/g" /etc/csf/csf.conf

        echo "  Setting blocktime to 30 minutes"
        sed -ie "s/^CT_BLOCK_TIME = .*/CT_BLOCK_TIME = \"1800\"/g" /etc/csf/csf.conf

        echo "  Setting skip time_wait to on"
        sed -ie "s/^CT_SKIP_TIME_WAIT = .*/CT_SKIP_TIME_WAIT = \"1\"/g" /etc/csf/csf.conf

        echo "- Process Tracking Options"

        echo "  Setting Process Tracking Minimum Life to 180 seconds"
        sed -ie "s/^PT_LIMIT = .*/PT_LIMIT = \"180\"/g" /etc/csf/csf.conf

        echo "  Setting Process Tracking Check to 120 seconds"
        sed -ie "s/^PT_INTERVAL = .*/PT_INTERVAL = \"120\"/g" /etc/csf/csf.conf

        echo "  Verifying process killing is disabled"
        sed -ie "s/^PT_USERKILL = .*/PT_USERKILL = \"0\"/g" /etc/csf/csf.conf

        echo "- PortScan Options"

        echo "  Disabling PortScan Block"
        sed -ie "s/^PS_INTERVAL = .*/PS_INTERVAL = \"0\"/g" /etc/csf/csf.conf

        echo "  Disabling PortScan permanent blocks"
        sed -ie "s/^PS_PERMANENT = .*/PS_PERMANENT = \"0\"/g" /etc/csf/csf.conf

        echo "- Setting Integrity check to every 8 hours (from every hour)"
        sed -ie "s/^LF_INTEGRITY = .*/LF_INTEGRITY = \"28800\"/g" /etc/csf/csf.conf

        echo "- Increasing POP3/hour from 60 to 120"
        sed -ie "s/^LT_POP3D = .*/LT_POP3D = \"120\"/g" /etc/csf/csf.conf

	if [ -e /usr/local ]; then
		echo "- Adding Rules for Plesk ports"
		sed -ie 's/20,21,22,25,53,80,110,143,443,465,587,993,995,2222/20,21,22,25,53,80,110,113,143,443,465,587,993,995,2222,8443,8447,8880/g' /etc/csf/csf.conf
		sed -ie 's/20,21,22,25,53,80,110,113,443/20,21,22,25,53,80,110,113,443,5224/g' /etc/csf/csf.conf
	fi
	
}

configure_sshd_config(){
        # SSHD Hardening
        if [ -f "/etc/ssh/sshd_config" ]; then
                echo "Editing: /etc/ssh/sshd_config"
                echo "- Disabling ssh v1"
                uncomment_tweak "Protocol " "Protocol 2" /etc/ssh/sshd_config
                echo "- Setting KeySize to 2048"
                uncomment_tweak "ServerKeyBits " "ServerKeyBits 2048" /etc/ssh/sshd_config
                echo "- Setting LoginGraceTime to 2m"
                uncomment_tweak "LoginGraceTime " "LoginGraceTime 2m" /etc/ssh/sshd_config
                echo "- Setting MaxAuthTries 3"
                uncomment_tweak "MaxAuthTries " "MaxAuthTries 3" /etc/ssh/sshd_config
                echo "- Setting UsePrivSep to yes"
                uncomment_tweak "UsePrivilegeSeparation " "UsePrivilegeSeparation yes" /etc/ssh/sshd_config
                echo "- Setting MaxStartups to 5"
                uncomment_tweak "MaxStartups " "MaxStartups 5" /etc/ssh/sshd_config
        fi
                echo "Restarting: sshd"
        if [ -e "/etc/init.d/sshd" ]; then /etc/init.d/sshd restart &>/dev/null ; fi
}

configure_csf_pignore(){
        if [ -f "/etc/csf/csf.pignore" ]; then
          echo "Editing: /etc/csf/csf.pignore"

	if [ -e "/usr/local/psa/bin/product_info" ]; then
		echo "- Adding Plesk Processes to csf.pignore"
		echo "exe:/usr/bin/sw-engine-cgi" >> /etc/csf/csf.pignore
		echo "cmd:/usr/bin/sw-engine-cgi -c /usr/local/psa/admin/conf/php.ini -d auto_prepend_file=auth.php3 -u psaadm" >> /etc/csf/csf.pignore
		echo "user:psaadm" >> /etc/csf/csf.pignore
		echo "exe:/usr/libexec/mysqld" >> /etc/csf/csf.pignore
		echo "cmd:/usr/libexec/mysqld –basedir=/usr –datadir=/var/lib/mysql –user=mysql –pid-file=/var/run/mysqld/mysqld.pid –skip-external-locking –socket=/var/lib/mysql/mysql.sock" >> /etc/csf/csf.pignore
		echo "user:mysql" >> /etc/csf/csf.pignore
		echo "user:admin" >> /etc/csf/csf.pignore
	fi

          grep -i "/usr/local/cpanel/3rdparty/mailman/bin/qrunner" /etc/csf/csf.pignore &>/dev/null || \
                echo "- Adding /usr/local/cpanel/3rdparty/mailman/bin/qrunner" && \
                echo "exe:/usr/local/cpanel/3rdparty/mailman/bin/qrunner" >> /etc/csf/csf.pignore

          grep -i "/usr/sbin/mysqld" /etc/csf/csf.pignore &>/dev/null || \
                echo "- Adding /usr/sbin/mysqld" && \
                echo "exe:/usr/sbin/mysqld" /etc/csf/csf.pignore >> /etc/csf/csf.pignore

          grep -i "/usr/local/cpanel/3rdparty/mailman/bin/mailmanctl" /etc/csf/csf.pignore &>/dev/null || \
                echo "- Adding /usr/local/cpanel/3rdparty/mailman/bin/mailmanctl" && \
                echo "exe:/usr/local/cpanel/3rdparty/mailman/bin/mailmanctl" >> /etc/csf/csf.pignore

        fi
}

configure_csf_dirwatch(){
        grep "^/etc/ssh/sshd_config" /etc/csf/csf.dirwatch &>/dev/null || echo "/etc/ssh/sshd_config" >> /etc/csf/csf.dirwatch \
                && echo "- Adding /etc/ssh/sshd_config file to watchlist"
}

configure_csf() {
	configure_csf_allow
	configure_csf_conf
	configure_sshd_config
	configure_csf_pignore
	configure_csf_dirwatch
}

stop_services() {
	echo "Stopping/Disabling Services"
	for service in anacron avahi-daemon avahi-dnsconfd bluetooth canna cups gpm hidd iiim nfslock nifd pcscd \
		rpcidmapd saslauthd sbadm webmin xfs ; do
	  echo "- Stopping: $service"
	  service $service stop &>/dev/null
  	  chkconfig $service off &>/dev/null
	done
}

set_permissions() {
	for folder in /tmp /var/tmp ; do
		echo "Setting $folder to 1777"
		chmod 1777 $folder &>/dev/null
	done
}

update_csf() {
        echo
        echo "Checking for CSF updates ..."
        echo
        /usr/sbin/csf --update
}

restart_csf() {
        if [ -e "/etc/rc.d/init.d/lfd" ]; then
                echo -n "Restarting LFD: "
                /etc/rc.d/init.d/lfd restart &>/dev/null
                echo "OK"
        fi
        if [ -e "/etc/rc.d/init.d/csf" ]; then
                echo -n "Restarting CSF: "
                /etc/rc.d/init.d/csf restart &>/dev/null
                echo "OK"

        fi
}

cleanup() {
	rm -rf "$TEMPDIR" &>/dev/null
    rm -f $0 &>/dev/null
}

plesku() {
	if [ -e "/usr/local/psa/bin/product_info" ]; then
		clear
		echo "PLESK SERVER."
		echo " "
		echo "Turning the Plesk Firewall back on after uninstallation."
		touch /usr/local/psa/var/modules/firewall/active.flag
		chkconfig --add psa-firewall
		service psa-firewall start
	fi
}

plesk() {
	if [ -e "/usr/local/psa/bin/product_info" ]; then
		echo "Plesk Server Installation."
		echo " "
		echo "Turning off Plesk Firewall."
		service psa-firewall stop
		echo "Removing the PSA Firewall active.flag"
		rm -fv /usr/local/psa/var/modules/firewall/active.flag
		echo "Removing psa-firewall from chkconfig"
		chkconfig --del psa-firewall
	fi
}

clear
switch="$(echo $1)";

# Uninstall if -u or -uf passed from command line.
if [ "$(echo $1)" = "-u" -o "$(echo $1)" = "-uf" ]
	then
		uninstall
		plesku
fi

# Install if -i passed from command line
if [ "$(echo $1)" = "-i" ]
	then
	{
		plesk
		prepare
		install_csf
		configure_csf
		stop_services
		set_permissions
		update_csf
		restart_csf
		cleanup
	}
fi
# Print usage and exit.
if [ "$(echo $1)" = "-v" ]
	then
		echo "install-csf $ver";
fi
if [ -z "$(echo $1)" ]
	then
	{
		echo "This is bashcode CSF installation script. Please run as follows :";
		echo " ";
		echo "bash <(GET https://raw.github.com/bashcode/csf/master/install.sh) -i :: to install"
		echo "bash <(GET https://raw.github.com/bashcode/csf/master/install.sh) -u :: to uninstall"
		echo "bash <(GET https://raw.github.com/bashcode/csf/master/install.sh) -v :: to print the current version";
	}
fi
