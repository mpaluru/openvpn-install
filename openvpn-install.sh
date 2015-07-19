#!/bin/bash
# OpenVPN road warrior installer for Debian, Ubuntu and CentOS

# This script will work on Debian, Ubuntu, CentOS and probably other distros
# of the same families, although no support is offered for them. It isn't
# bulletproof but it will probably work if you simply want to setup a VPN on
# your Debian/Ubuntu/CentOS box. It has been designed to be as unobtrusive and
# universal as possible.

# TODO: Check for return codes for all variables
# TODO: Use colored messages?
# TODO: Check if we can use the topology subnet?
# TODO: See if we can print currently connected client information
# TODO: Configure the company/department parameters while configuring cert


if [[ "$USER" != 'root' ]]; then
    echo "Sorry, you need to run this as root"
    exit
fi


if [[ ! -e /dev/net/tun ]]; then
    echo "TUN/TAP is not available"
    exit
fi


if grep -qs "CentOS release 5" "/etc/redhat-release"; then
    echo "CentOS 5 is too old and not supported"
    exit
fi

if [[ -e /etc/debian_version ]]; then
    OS=debian
    RCLOCAL='/etc/rc.local'
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
    OS=centos
    RCLOCAL='/etc/rc.d/rc.local'
    # Needed for CentOS 7
    chmod +x /etc/rc.d/rc.local
else
    echo "Looks like you aren't running this installer on a Debian, Ubuntu or CentOS system"
    exit
fi

DEFAUT_CLIENT_CONFIG_TEMPLATE_FILE=
OPEN_WARRIOR_CLIENT_CONFIG_TEMPLATE_FILE=


# Generates the client.ovpn
add_client() {

    DEFAUT_CLIENT_CONFIG_TEMPLATE_FILE=`ls /usr/share/doc/openvpn*/*ample*/sample-config-files/client.conf`
    OPEN_WARRIOR_CLIENT_CONFIG_TEMPLATE_FILE="${DEFAUT_CLIENT_CONFIG_TEMPLATE_FILE}".ow
    
    echo "DEFAUT_CLIENT_CONFIG_TEMPLATE_FILE=${DEFAUT_CLIENT_CONFIG_TEMPLATE_FILE}"
    echo "OPEN_WARRIOR_CLIENT_CONFIG_TEMPLATE_FILE=${OPEN_WARRIOR_CLIENT_CONFIG_TEMPLATE_FILE}"

    echo ""
    echo "Tell me a name for the client cert"
    echo "Please, use one word only, no special characters"
    read -p "Client name: " -e -i client CLIENT
    cd /etc/openvpn/easy-rsa/2.0/
    source ./vars
    # build-key for the client
    export KEY_CN="$CLIENT"
    export EASY_RSA="${EASY_RSA:-.}"
    "$EASY_RSA/pkitool" $CLIENT

    if [ -f  "${OPEN_WARRIOR_CLIENT_CONFIG_TEMPLATE_FILE}" ]; then
        cp "${OPEN_WARRIOR_CLIENT_CONFIG_TEMPLATE_FILE}" ~/${CLIENT}.ovpn
    else
        echo "Did you set up the server using this script earlier?"
        echo "There is a slight problem, can't continue for now"
        exit 1
        # TODO: Fix this later
    fi

    sed -i "/ca ca.crt/d" ~/${CLIENT}.ovpn
    sed -i "/cert client.crt/d" ~/${CLIENT}.ovpn
    sed -i "/key client.key/d" ~/${CLIENT}.ovpn
    echo "<ca>" >> ~/${CLIENT}.ovpn
    cat /etc/openvpn/easy-rsa/2.0/keys/ca.crt >> ~/${CLIENT}.ovpn
    echo "</ca>" >> ~/${CLIENT}.ovpn
    echo "<cert>" >> ~/${CLIENT}.ovpn
    cat /etc/openvpn/easy-rsa/2.0/keys/${CLIENT}.crt >> ~/${CLIENT}.ovpn
    echo "</cert>" >> ~/${CLIENT}.ovpn
    echo "<key>" >> ~/${CLIENT}.ovpn
    cat /etc/openvpn/easy-rsa/2.0/keys/${CLIENT}.key >> ~/${CLIENT}.ovpn
    echo "</key>" >> ~/${CLIENT}.ovpn


    echo ""
    echo "Client $CLIENT added, certs available at ~/$CLIENT.ovpn"
    echo "If you want to add more clients, you simply need to run this script another time!"

    # TODO: Handle if there is client specific configuration to be done on server
    # Say static ip, enable default gateway or not etc.

    # Figure out the client-config-dir
    CCD_DIR_NAME=`grep "^\s\?\+client-config-dir" /etc/openvpn/server.conf | awk '{print $2}'`
    if [ ! -d "/etc/openvpn/${CCD_DIR_NAME}" ]; then
        echo "Error: client-config-dir ${CCD_DIR_NAME} doesn't exist"
        # TODO: Should I create?
        mkdir -p "/etc/openvpn/${CCD_DIR_NAME}"
    fi

    if [ -f "/etc/openvpn/${CCD_DIR_NAME}/${CLIENT}" ]; then
        echo "Client specific file: /etc/openvpn/${CCD_DIR_NAME}/${CLIENT} already exists"
        # TODO: Decide what we need to do.
    else
        touch "/etc/openvpn/${CCD_DIR_NAME}/${CLIENT}"
    fi

    echo ""
    read -p "Do you want to assign a static IP address for the client? [y/n]: " -e -i y CLIENT_ASSIGN_STATIC_IP

    if [ "${CLIENT_ASSIGN_STATIC_IP}" == "y" -o "${CLIENT_ASSIGN_STATIC_IP}" == "Y" ]; then
        # TODO: Figure out what IP addresses are already in use.
        echo ""
        read -p "Enter the static IP address: " CLIENT_IP
        echo "ifconfig-push ${CLIENT_IP} 255.255.255.0" >> "/etc/openvpn/${CCD_DIR_NAME}/${CLIENT}"
        # TODO: The mask is hard coded, need to fix that later
    fi

    echo ""
    read -p "Do you want this client's traffic to go through VPN? [y/n]: " -e -i y CLIENT_DEFAULT_GW

    if [ "${CLIENT_DEFAULT_GW}" == "y" -o "${CLIENT_DEFAULT_GW}" == "Y" ]; then
        echo ""
        echo 'push "redirect-gateway def1"' >> "/etc/openvpn/${CCD_DIR_NAME}/${CLIENT}"
    fi

}

# TODO: Check if we can put the version in a variable or somehow use the latest?
geteasyrsa () {
    wget --no-check-certificate -O ~/easy-rsa.tar.gz https://github.com/OpenVPN/easy-rsa/archive/2.2.2.tar.gz
    tar xzf ~/easy-rsa.tar.gz -C ~/
    mkdir -p /etc/openvpn/easy-rsa/2.0/
    cp ~/easy-rsa-2.2.2/easy-rsa/2.0/* /etc/openvpn/easy-rsa/2.0/
    rm -rf ~/easy-rsa-2.2.2
    rm -rf ~/easy-rsa.tar.gz
}

install_software() {
    if [[ "$OS" = 'debian' ]]; then
        apt-get update
        apt-get install openvpn iptables openssl -y
        cp -R /usr/share/doc/openvpn/examples/easy-rsa/ /etc/openvpn
        # easy-rsa isn't available by default for Debian Jessie and newer
        if [[ ! -d /etc/openvpn/easy-rsa/2.0/ ]]; then
            geteasyrsa
        fi
    else
        # Else, the distro is CentOS
        yum install epel-release -y
        yum install openvpn iptables openssl wget -y
        geteasyrsa
    fi

}

configure_firewall() {

    # TODO: Check if iptables command is present
    # TODO: Install iptables using yum if not present
    # TODO: Ask the user to install either iptables/firewalld if on CentOS

    #TODO: Should we put the tun0 interface in a zone?

    USE_IPTABLES=0

    if [ "${USE_IPTABLES}" == "1" ]; then
        if [[ "$INTERNALNETWORK" = 'y' ]]; then
            iptables -t nat -A POSTROUTING -s ${OPENVPN_SUBNET}/24 ! -d ${OPENVPN_SUBNET}/24 -j SNAT --to $IP
            sed -i "1 a\iptables -t nat -A POSTROUTING -s ${OPENVPN_SUBNET}/24 ! -d ${OPENVPN_SUBNET}/24 -j SNAT --to $IP" $RCLOCAL
        else
            iptables -t nat -A POSTROUTING -s ${OPENVPN_SUBNET}/24 -j SNAT --to $IP
            sed -i "1 a\iptables -t nat -A POSTROUTING -s ${OPENVPN_SUBNET}/24 -j SNAT --to $IP" $RCLOCAL
        fi
    else
        firewall-cmd --permanent --zone=public --add-service openvpn
        firewall-cmd --permanent --zone=public --add-masquerade
        firewall-cmd --reload

        #if [[ "$INTERNALNETWORK" = 'y' ]]; then
        #else
        #fi
    fi
}

#TODO: Have a separate function for enabling/disabling the service
restart_openvpn() {
    if [[ "$OS" = 'debian' ]]; then
        # Little hack to check for systemd
        if pgrep systemd-journal; then
            systemctl restart openvpn@server.service
        else
            /etc/init.d/openvpn restart
        fi
    else
        if pgrep systemd-journal; then
            systemctl restart openvpn@server.service
            systemctl enable openvpn@server.service
        else
            service openvpn restart
            chkconfig openvpn on
        fi
    fi
}

revoke_client() {

    # TODO: Instead of asking the user for the client name,
    # can't we figure out ourselves and provide a choice?

    echo ""
    echo "Tell me the existing client name"
    read -p "Client name: " -e -i client CLIENT
    cd /etc/openvpn/easy-rsa/2.0/
    . /etc/openvpn/easy-rsa/2.0/vars
    . /etc/openvpn/easy-rsa/2.0/revoke-full $CLIENT

    #TODO: Remove any CCD file present for the CLIENT

    # If it's the first time revoking a cert, we need to add the crl-verify line
    if ! grep -q "crl-verify" "/etc/openvpn/server.conf"; then
        echo "crl-verify /etc/openvpn/easy-rsa/2.0/keys/crl.pem" >> "/etc/openvpn/server.conf"
        # And restart
        if pgrep systemd-journal; then
            systemctl restart openvpn@server.service
        else
            if [[ "$OS" = 'debian' ]]; then
                /etc/init.d/openvpn restart
            else
                service openvpn restart
            fi
        fi
    fi
    echo ""
    echo "Certificate for client $CLIENT revoked"
}

uninstall_openvpn() {
    echo ""
    read -p "Do you really want to remove OpenVPN? [y/n]: " -e -i n REMOVE
    if [[ "$REMOVE" = 'y' ]]; then
        if [[ "$OS" = 'debian' ]]; then
            apt-get remove --purge -y openvpn openvpn-blacklist
        else
            yum remove openvpn -y
        fi
        rm -rf /etc/openvpn
        rm -rf /usr/share/doc/openvpn*
        # TODO: May not work if firewalld is used
        sed -i '/--dport 53 -j REDIRECT --to-port/d' $RCLOCAL
        sed -i '/iptables -t nat -A POSTROUTING -s ${OPENVPN_SUBNET}/d' $RCLOCAL
        echo ""
        echo "OpenVPN removed!"
    else
        echo ""
        echo "Removal aborted!"
    fi
}

# Try to get our IP from the system and fallback to the Internet.
# I do this to make the script compatible with NATed servers (lowendspirit.com)
# and to avoid getting an IPv6.
IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
if [[ "$IP" = "" ]]; then
        IP=$(wget -qO- ipv4.icanhazip.com)
fi


if [[ -e /etc/openvpn/server.conf ]]; then
    while :
    do
    clear
        echo "Looks like OpenVPN is already installed"
        echo "What do you want to do?"
        echo ""
        echo "1) Add a cert for a new user"
        echo "2) Revoke existing user cert"
        echo "3) Remove OpenVPN"
        echo "4) Exit"
        echo ""
        read -p "Select an option [1-4]: " option
        case $option in
            1) 
                add_client
                exit
                ;;

            2)
                revoke_client
                exit
                ;;

            3) 
                uninstall_openvpn
                exit
                ;;
            4) 
                exit
                ;;
        esac
    done
else
    clear
    echo 'Welcome to this quick OpenVPN "road warrior" installer'
    echo ""
    # OpenVPN setup and first user creation
    echo "I need to ask you a few questions before starting the setup"
    echo "You can leave the default options and just press enter if you are ok with them"

    echo ""
    echo "First I need to know the IPv4 address of the network interface you want OpenVPN"
    echo "listening to."
    read -p "IP address: " -e -i $IP IP

    echo ""
    echo "What port do you want for OpenVPN?"
    read -p "Port: " -e -i 1194 PORT

    echo ""
    echo "Do you want OpenVPN to be available at port 53 too?"
    echo "This can be useful to connect under restrictive networks"
    read -p "Listen at port 53 [y/n]: " -e -i n ALTPORT
    echo ""
    echo "Do you want to enable internal networking for the VPN?"
    echo "This can allow VPN clients to communicate between them"
    read -p "Allow internal networking [y/n]: " -e -i y INTERNALNETWORK

    echo ""
    echo "What subnet do you want to use with the VPN?"
    read -p "Enter the subnet IP address: " -e -i "10.8.0.0" OPENVPN_SUBNET

    guess_p_dns_server=`echo ${OPENVPN_SUBNET} | sed 's|\(.*\)\.\(.*\)\.\(.*\)\.\(.*\)|\1.\2.\3.1|'`

    echo ""
    echo ""
    read -p "Do you want to enable topology subnet? [y/n]: " -e -i n TOPOLOGY_SUBNET

    echo ""
    echo "What DNS do you want to use with the VPN?"
    echo "   1) Current system resolvers"
    echo "   2) OpenDNS"
    echo "   3) Level 3"
    echo "   4) NTT"
    echo "   5) Hurricane Electric"
    echo "   6) Yandex"
    echo "   7) Enter custom DNS"
    read -p "DNS [1-7]: " -e -i 7 DNS

    if [ "${DNS}" == "7" ]; then
        read -p "Please enter the IP address of primary DNS server: " -e -i "${guess_p_dns_server}" p_dns_server
        read -p "Please enter the IP address of secondary DNS server [optional]: " s_dns_server
    fi
        
    echo ""
    read -p "Do you want to enable client-config-dir? [y/n]: " -e -i y CCD_ENABLE

    if [ "${CCD_ENABLE}" == "y" -o "${CCD_ENABLE}" == "Y" ]; then
        echo ""
        echo "What name would you like to use for client-config-dir?"
        read -p "Enter a valid directory name: " -e -i ccd CCD_DIR_NAME
    fi

    echo ""
    echo "Okay, that was all I needed. We are ready to setup your OpenVPN server now"
    read -n1 -r -p "Press any key to continue..."


    install_software

    cd /etc/openvpn/easy-rsa/2.0/
    # Let's fix one thing first...
    cp -u -p openssl-1.0.0.cnf openssl.cnf
    # Fuck you NSA - 1024 bits was the default for Debian Wheezy and older
    sed -i 's|export KEY_SIZE=1024|export KEY_SIZE=2048|' /etc/openvpn/easy-rsa/2.0/vars
    # Create the PKI
    . /etc/openvpn/easy-rsa/2.0/vars
    . /etc/openvpn/easy-rsa/2.0/clean-all
    # The following lines are from build-ca. I don't use that script directly
    # because it's interactive and we don't want that. Yes, this could break
    # the installation script if build-ca changes in the future.
    export EASY_RSA="${EASY_RSA:-.}"
    "$EASY_RSA/pkitool" --initca $*
    # Same as the last time, we are going to run build-key-server
    export EASY_RSA="${EASY_RSA:-.}"
    "$EASY_RSA/pkitool" --server server
    # Now the client keys. We need to set KEY_CN or the stupid pkitool will cry
    export KEY_CN="$CLIENT"
    export EASY_RSA="${EASY_RSA:-.}"
    "$EASY_RSA/pkitool" $CLIENT
    # DH params
    . /etc/openvpn/easy-rsa/2.0/build-dh
    # Let's configure the server
    cd /usr/share/doc/openvpn*/*ample*/sample-config-files
    if [[ "$OS" = 'debian' ]]; then
        gunzip -d server.conf.gz
    fi
    cp server.conf /etc/openvpn/
    cd /etc/openvpn/easy-rsa/2.0/keys
    cp ca.crt ca.key dh2048.pem server.crt server.key /etc/openvpn
    cd /etc/openvpn/
    # Set the server configuration
    sed -i 's|dh dh1024.pem|dh dh2048.pem|' server.conf

    # TODO: Not all users want to use the VPN as default gateway. Don't use this
    # sed -i 's|;push "redirect-gateway def1 bypass-dhcp"|push "redirect-gateway def1 bypass-dhcp"|' server.conf

    sed -i "s|port 1194|port $PORT|" server.conf
    # DNS
    case $DNS in
        1) 
        # Obtain the resolvers from resolv.conf and use them for OpenVPN
        grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
            sed -i "/;push \"dhcp-option DNS 208.67.220.220\"/a\push \"dhcp-option DNS $line\"" server.conf
        done
        ;;
        2)
        sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 208.67.222.222"|' server.conf
        sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 208.67.220.220"|' server.conf
        ;;
        3) 
        sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 4.2.2.2"|' server.conf
        sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 4.2.2.4"|' server.conf
        ;;
        4) 
        sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 129.250.35.250"|' server.conf
        sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 129.250.35.251"|' server.conf
        ;;
        5) 
        sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 74.82.42.42"|' server.conf
        ;;
        6) 
        sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS 77.88.8.8"|' server.conf
        sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS 77.88.8.1"|' server.conf
        ;;
        7) 
        sed -i 's|;push "dhcp-option DNS 208.67.222.222"|push "dhcp-option DNS '"${p_dns_server}"'"|' server.conf
        if [ "${s_dns_server}" != "" ]; then
            sed -i 's|;push "dhcp-option DNS 208.67.220.220"|push "dhcp-option DNS '"${s_dns_server}"'"|' server.conf
        fi

        ;;
    esac

    # Create the CCD directory
    if [ "${CCD_ENABLE}" == "y" -o "${CCD_ENABLE}" == "Y" ]; then
        mkdir -p "/etc/openvpn/${CCD_DIR_NAME}"
        echo "client-config-dir ${CCD_DIR_NAME}" >> /etc/openvpn/server.conf
    fi


    # Change the subnet
    sed -i "s|server 10.8.0.0 255.255.255.0| server ${OPENVPN_SUBNET} 255.255.255.0|" server.conf

    if [ "${TOPOLOGY_SUBNET}" == "y" -o "${TOPOLOGY_SUBNET}" == "Y" ]; then
        sed -i 's|;topology subnet|topology subnet|' server.conf
    fi

    # Listen at port 53 too if user wants that
    if [[ "$ALTPORT" = 'y' ]]; then
        iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port $PORT
        sed -i "1 a\iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-port $PORT" $RCLOCAL
    fi
    # Enable net.ipv4.ip_forward for the system
    if [[ "$OS" = 'debian' ]]; then
        sed -i 's|#net.ipv4.ip_forward=1|net.ipv4.ip_forward=1|' /etc/sysctl.conf
    else
        # CentOS 5 and 6
        sed -i 's|net.ipv4.ip_forward = 0|net.ipv4.ip_forward = 1|' /etc/sysctl.conf
        # CentOS 7
        if ! grep -q "net.ipv4.ip_forward=1" "/etc/sysctl.conf"; then
            echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
        fi
    fi
    # Avoid an unneeded reboot
    echo 1 > /proc/sys/net/ipv4/ip_forward


    # Set iptables
    # And finally, restart OpenVPN
    restart_openvpn

    # TODO: Use a variable for the server
    # TODO: What if that server is down? 
    # Try to detect a NATed connection and ask about it to potential LowEndSpirit
    # users
    EXTERNALIP=$(wget -qO- ipv4.icanhazip.com)
    if [[ "$IP" != "$EXTERNALIP" ]]; then
        echo ""
        echo "Looks like your server is behind a NAT!"
        echo ""
        echo "If your server is NATed (LowEndSpirit), I need to know the external IP"
        echo "If that's not the case, just ignore this and leave the next field blank"
        read -p "External IP: " -e USEREXTERNALIP
        if [[ "$USEREXTERNALIP" != "" ]]; then
            IP=$USEREXTERNALIP
        fi
    fi

    # IP/port set on the default client.conf so we can add further users
    # without asking for them
    cp "${DEFAUT_CLIENT_CONFIG_TEMPLATE_FILE}" "${OPEN_WARRIOR_CLIENT_CONFIG_TEMPLATE_FILE}"
    sed -i "s|remote my-server-1 1194|remote $IP $PORT|" "${OPEN_WARRIOR_CLIENT_CONFIG_TEMPLATE_FILE}"

    echo ""
    echo "You can add more clients later by simply running this script again!"
    read -p "Do you want to add a new client NOW? [y/n]: " -e -i n ADD_CLIENT_NOW

    if [ "${ADD_CLIENT_NOW}" == "y" -o "${ADD_CLIENT_NOW}" == "Y" ]; then
        add_client
    fi

    echo ""
    echo "Finished!"
    echo ""
fi
