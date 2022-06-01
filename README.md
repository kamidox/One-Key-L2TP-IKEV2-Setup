# One-Key-L2TP-IKEV2-Setup

Since the original script `l2tp_setup.sh` not longer work any more. I create a new script, named `IKEv2_setup.sh`, which do the similar thing: setup an IKEv2 VPN server with one key.

Please refer to [How to Set Up an IKEv2 VPN Server with StrongSwan on Ubuntu 22.04](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-ikev2-vpn-server-with-strongswan-on-ubuntu-22-04) for technical details.

General speaking, you can run below script on your ubuntu 22.04 server to setup IKEv2 VPN server:

```
$ cd ~
$ wget https://raw.githubusercontent.com/kamidox/One-Key-L2TP-IKEV2-Setup/master/IKEv2_setup.sh
$ sudo chmod a+x IKEv2_setup.sh
$ ./IKEv2_setup.sh
```

```
echo "#################################"
echo "What do you want to do:"
echo "1) Setup IKEv2 server"
echo "2) Add an account"
echo "#################################"
```

Choose 1 to setup server. Choose 2 to add a vpn account.

After that, jump to [Step 7 — Testing the VPN Connection on Windows, macOS, Ubuntu, iOS, and Android](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-ikev2-vpn-server-with-strongswan-on-ubuntu-22-04), verify your VPN server on your client devices.
