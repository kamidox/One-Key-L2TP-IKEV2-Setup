#! /bin/sh
#===============================================================================================
#   Install IKEv2 VPN on Ubuntu
#   Verified under Ubuntu 22.04
#   REF: https://www.digitalocean.com/community/tutorials/how-to-set-up-an-ikev2-vpn-server-with-strongswan-on-ubuntu-22-04
#===============================================================================================
echo "#######################################################"
echo "Setup IKEv2 service on Ubuntu server"
echo
echo "Easy to install & add new account."
echo "Only tested on Ubuntu 22.04"
echo "PS. Please make sure you are using root account to run this script."
echo "#######################################################"
echo
echo "#################################"
echo "What do you want to do:"
echo "1) Setup IKEv2 server"
echo "2) Add an account"
echo "#################################"
read x

#===============================================================================================
#   1) Setup IKEv2 server
#===============================================================================================
if test $x -eq 1; then
    echo "Install strongswan ..."
    sudo apt update
    sudo apt install strongswan strongswan-pki libcharon-extra-plugins libcharon-extauth-plugins libstrongswan-extra-plugins

    echo "Setup pki ..."
    mkdir -p ~/pki/cacerts
    mkdir -p ~/pki/certs
    mkdir -p ~/pki/private
    chmod 700 ~/pki

    pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/ca-key.pem
    pki --self --ca --lifetime 3650 --in ~/pki/private/ca-key.pem \
        --type rsa --dn "CN=VPN root CA" --outform pem > ~/pki/cacerts/ca-cert.pem

    echo "#################################"
    echo "Please input your server's public ip address:"
    echo "#################################"
    read ip

    pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/server-key.pem
    pki --pub --in ~/pki/private/server-key.pem --type rsa \
        | pki --issue --lifetime 1825 \
            --cacert ~/pki/cacerts/ca-cert.pem \
            --cakey ~/pki/private/ca-key.pem \
            --dn "CN=$ip" --san @$ip --san $ip \
            --flag serverAuth --flag ikeIntermediate --outform pem \
        >  ~/pki/certs/server-cert.pem

    sudo cp -r ~/pki/* /etc/ipsec.d/

    echo "Configuring StrongSwan ..."
    sudo mv /etc/ipsec.conf /etc/ipsec.conf.bak

    cat > /etc/ipsec.conf <<END
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn ikev2-vpn
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes
    forceencaps=yes
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftid=$ip
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=10.10.10.0/24
    rightdns=8.8.8.8,8.8.4.4
    rightsendcert=never
    eap_identity=%identity
    ike=chacha20poly1305-sha512-curve25519-prfsha512,aes256gcm16-sha384-prfsha384-ecp384,aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024,aes256-sha1-modp2048,aes256-sha256-modp2048!
    esp=chacha20poly1305-sha512,aes256gcm16-ecp384,aes256-sha256,aes256-sha1,3des-sha1!
END

    echo "Configuring VPN Authentication ..."
    sudo mv /etc/ipsec.secrets /etc/ipsec.secrets.bak

    cat > /etc/ipsec.secrets <<END
: RSA "server-key.pem"
END

    sudo ufw allow OpenSSH
    sudo ufw enable
    sudo ufw allow 500,4500/udp

    echo "Configuring /etc/ufw/before.rules ..."
    sudo mv /etc/ufw/before.rules /etc/ufw/before.rules.bak

    cat > /etc/ufw/before.rules <<END
#
# rules.before
#
# Rules that should be run before the ufw command line added rules. Custom
# rules should be added to one of these chains:
#   ufw-before-input
#   ufw-before-output
#   ufw-before-forward
#

##################################
# Config for IKEv2 VPN - start
##################################
*nat
-A POSTROUTING -s 10.10.10.0/24 -o eth0 -m policy --pol ipsec --dir out -j ACCEPT
-A POSTROUTING -s 10.10.10.0/24 -o eth0 -j MASQUERADE
COMMIT

*mangle
-A FORWARD --match policy --pol ipsec --dir in -s 10.10.10.0/24 -o eth0 -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360
COMMIT
##################################
# Config for IKEv2 VPN - end
##################################

# Don't delete these required lines, otherwise there will be errors
*filter
:ufw-before-input - [0:0]
:ufw-before-output - [0:0]
:ufw-before-forward - [0:0]
:ufw-not-local - [0:0]
# End required lines

##################################
# Config for IKEv2 VPN - start
# These lines tell the firewall to forward ESP (Encapsulating Security Payload) traffic so the VPN clients will be able to connect.
##################################
-A ufw-before-forward --match policy --pol ipsec --dir in --proto esp -s 10.10.10.0/24 -j ACCEPT
-A ufw-before-forward --match policy --pol ipsec --dir out --proto esp -d 10.10.10.0/24 -j ACCEPT
##################################
# Config for IKEv2 VPN - end
##################################

# allow all on loopback
-A ufw-before-input -i lo -j ACCEPT
-A ufw-before-output -o lo -j ACCEPT

# quickly process packets for which we already have a connection
-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# drop INVALID packets (logs these in loglevel medium and higher)
-A ufw-before-input -m conntrack --ctstate INVALID -j ufw-logging-deny
-A ufw-before-input -m conntrack --ctstate INVALID -j DROP

# ok icmp codes for INPUT
-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT
-A ufw-before-input -p icmp --icmp-type time-exceeded -j ACCEPT
-A ufw-before-input -p icmp --icmp-type parameter-problem -j ACCEPT
-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT

# ok icmp code for FORWARD
-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j ACCEPT
-A ufw-before-forward -p icmp --icmp-type time-exceeded -j ACCEPT
-A ufw-before-forward -p icmp --icmp-type parameter-problem -j ACCEPT
-A ufw-before-forward -p icmp --icmp-type echo-request -j ACCEPT

# allow dhcp client to work
-A ufw-before-input -p udp --sport 67 --dport 68 -j ACCEPT

#
# ufw-not-local
#
-A ufw-before-input -j ufw-not-local

# if LOCAL, RETURN
-A ufw-not-local -m addrtype --dst-type LOCAL -j RETURN

# if MULTICAST, RETURN
-A ufw-not-local -m addrtype --dst-type MULTICAST -j RETURN

# if BROADCAST, RETURN
-A ufw-not-local -m addrtype --dst-type BROADCAST -j RETURN

# all other non-local packets are dropped
-A ufw-not-local -m limit --limit 3/min --limit-burst 10 -j ufw-logging-deny
-A ufw-not-local -j DROP

# allow MULTICAST mDNS for service discovery (be sure the MULTICAST line above
# is uncommented)
-A ufw-before-input -p udp -d 224.0.0.251 --dport 5353 -j ACCEPT

# allow MULTICAST UPnP for service discovery (be sure the MULTICAST line above
# is uncommented)
-A ufw-before-input -p udp -d 239.255.255.250 --dport 1900 -j ACCEPT

# don't delete the 'COMMIT' line or these rules won't be processed
COMMIT
END

    echo "Configuring /etc/ufw/sysctl.conf ..."
    sudo mv /etc/ufw/sysctl.conf /etc/ufw/sysctl.conf.bak

    cat > /etc/ufw/sysctl.conf <<END
#
# Configuration file for setting network variables. Please note these settings
# override /etc/sysctl.conf and /etc/sysctl.d. If you prefer to use
# /etc/sysctl.conf, please adjust IPT_SYSCTL in /etc/default/ufw. See
# Documentation/networking/ip-sysctl.txt in the kernel source code for more
# information.
#

# Uncomment this to allow this host to route packets between interfaces
net/ipv4/ip_forward=1
#net/ipv6/conf/default/forwarding=1
#net/ipv6/conf/all/forwarding=1

# Disable ICMP redirects. ICMP redirects are rarely used but can be used in
# MITM (man-in-the-middle) attacks. Disabling ICMP may disrupt legitimate
# traffic to those sites.
net/ipv4/conf/all/accept_redirects=0
net/ipv4/conf/all/send_redirects=0
net/ipv4/conf/default/accept_redirects=0
net/ipv6/conf/all/accept_redirects=0
net/ipv6/conf/default/accept_redirects=0

# Ignore bogus ICMP errors
net/ipv4/icmp_echo_ignore_broadcasts=1
net/ipv4/icmp_ignore_bogus_error_responses=1
net/ipv4/icmp_echo_ignore_all=0

# Don't log Martian Packets (impossible addresses)
# packets
net/ipv4/conf/all/log_martians=0
net/ipv4/conf/default/log_martians=0

#net/ipv4/tcp_fin_timeout=30
#net/ipv4/tcp_keepalive_intvl=1800

# Uncomment this to turn off ipv6 autoconfiguration
#net/ipv6/conf/default/autoconf=1
#net/ipv6/conf/all/autoconf=1

# Uncomment this to enable ipv6 privacy addressing
#net/ipv6/conf/default/use_tempaddr=2
#net/ipv6/conf/all/use_tempaddr=2

# Turn off Path MTU discovery
net/ipv4/ip_no_pmtu_disc=1
END

    sudo ufw disable
    sudo ufw enable

#===============================================================================================
#   2) Add an account
#===============================================================================================
elif test $x -eq 2; then

    echo "Please input an new username:"
    read u
    echo "Please input the password:"
    read p

    # Add an new account
    echo "$u : EAP \"$p\"" >> /etc/ipsec.secrets

    sudo ipsec stop
    sudo systemctl restart strongswan-starter
    echo "##############"
    echo "Success!"
    echo "Please read https://www.digitalocean.com/community/tutorials/how-to-set-up-an-ikev2-vpn-server-with-strongswan-on-ubuntu-22-04 to setup client"
    echo "##############"

else
#===============================================================================================
#   error
#===============================================================================================
    echo "Error with wrong choice."
    exit
fi
