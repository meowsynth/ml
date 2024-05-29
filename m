1. связать внутренние связи в настройках сети в виртуалке (названия)
2. nano /etc/sysctl.conf включить форвардинги (анкоммент) (сделать на всех виртуалках)
3. nmtui настроить подключение, проверить через ip a (желательно удалить проводное)
4. редакт nftables по гайду на isp обязателен, без него интернет не раздается	
	apt install ipcalc
	apt install subnetcalc

nmtui // для задания айпи адресов 
hostnamectl set-hostname <name>
sudo useradd <name> // создание пользователя	
sudo passwd <name> // пароль пользователя
полный перезапуск с другого пользователя 
настройки -> пользователи -> поменять имя пользователя
sudo usermod -l <new name> <old name> // смена имени пользователя
sudo usermod -d /home/isp -m isp // смена папки пользователя

# nano /etc/sysctl.conf //(isp br-r hq-r)
В данном файле прописываем следующие строки:
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
sudo sysctl -p

(isp br-r hq-r):
nano /etc/nftables.conf
добавить
table inet my_nat { 
chain my_masquerade {
type nat hook postrouting priority srcnat;
oifname "enp0s3" masquerade
}
} systemctl enable --now nftables

создание gre тунелля (br-r hq-r)
nmtui

Задаём понятные имена «Имя профиля» и «Устройство»
«Режим работы» выбираем «GRE»
«Родительский» указываем интерфейс в сторону ISP (enp0s3)
Задаём «Локальный IP» (ip выбранной машины в сторону ISP) (2 на конце)
Задаём «Удалённый IP» (IP удаленной машины в сторону ISP) (2 на конце)
Переходим к «КОНФИГУРАЦИЯ IPv4»
Задаём адрес IPv4 для туннеля 
Переходим к «КОНФИГУРАЦИЯ IPv6»
Задаём адрес IPv6 для туннеля
Активируем интерфейс tun1 
nmcli connection modify tun1 ip-tunnel.ttl 64

я выбрал ospfd так как он безопасный, стандартизированный и масшатбируемый.
apt install frr (HQ-R BR-R)
nano /etc/frr/daemons
ospfd = yes
ospf6d = yes 
systemctl enable --now frr
vtysh

conf t
router ospf
passive-interface default
network 192.168.100.0/27 area 0 (айпи машины на srv с нулем на конце)
network 15.15.15.0/30 area 0 (gre с нулем на конце)
exit 
interface tun1 
no ip ospf network broadcast
no ip ospf passive
exit
do write
router ospf6
ospf6 router-id 1.1.1.1 //(для hq) 3.3.3.1 // (для br или ситуативно)
exit
interface tun1
ipv6 ospf6 area 0
exit
interface enp0s3 (смотрящий на isp)
ipv6 ospf6 area 0 
exit 
do write
systemctl restart frr
vtysh 
show running-config
show ip ospf neighbor
show ipv6 ospf6 neighbor

на hq-r
sudo apt install isc-dhcp-server
nano /etc/dhcp/dhcpd.conf

в нем

subnet "ip роутер-сеть.0" netmask "маска hqr-isp.255.255" {
range "ip от 2" "до нужного ip";
option routers "gateway роутер-сеть";
default-lease-time 600;
max-lease-time 7200;
}

host "название сервера  в ветке" {
hardware ethernet "mac address из ip a сервера";
fixed-address "желаемый заданный ip";
}

nano /etc/default/isc-dhcp-server
INTERFACESv4="интерфейс к серверу"

nano /etc/dhcp/dhcpd6.conf

закомментировать все, кроме

default-lease-time
preferred-lifetime
option dhcp-renewal-time
option dhcp-rebinging-time
allow reasequery
option dhcp6.preference 255
option dhcp6.info-refresh-time
subnet6 "маска айпиv6 к серверу" {
range6 "маска айпиv6 к серверу::2" "маска айпиv6 к серверу::"максимальный айпи по заданию"
}
в теории работать должно но у меня чет не пошло так что анлаки плаки плаки :D

на hq-r и isp
apt install iperf3
на isp iperf3 -s (error: address already in use? команда sudo lsof -i :5201, затем kill номер под PID, пробовать еще епта)
на hq-r iperf3-c "айпи isp"

на hq-r

mkdir /var/backup-script/
nano /var/backup/backup.sh

в нем

data=$(date +%d.%m.%Y-%H:%M:%S)
mkdir /var/backup/$data
cp -r /"адрес октуда копировать" /var/backup/$data
и так сколько угодно адресов
cd /var/backup
tar czfv "./$data.tar.gz" ./$data
rm -r /var/backup/$data

в терминал

chmod +x /var/backup/backup.sh
/var/backup/backup.sh

на br-q

scp Admin(предварительно создать профиль)@"айпи gre на той стороне":"адрес бекап скрипта.sh" "адрес куда копировать"
chmod +x /var/backup/backup.sh
/var/backup-script/backup.sh

на hq-srv

nano /etc/ssh/sshd_config
Port 2222
systemctl restart sshd
ss -tlpn | grep ssh
ssh "пользователь на HQ-SRV"@"айпи сервера" -p 2222
если управляется компом дистанционно - работает

на hq-r

nano /etc/nftables.conf
привести к виду
table inet my_nat { 
chain prerouting {
type nat hook prerouting priority filter; police accept;
ip daddr 4.4.4.1 tcp dport 22 dnat ip to "айпи сервера":2222
ip daddr "айпи hq-r к isp" tcp dport 22 dnat ip to "айпи сервера":2222
}

chain my_masquerade {
type nat hook postrouting priority srcnat;
oifname "enp0s3" masquerade
}
}
system restart nftables

на br-r 

ssh "пользователь на HQ-SRV"@"айпи сервера" -p 2222
если управляется компом дистанционно - работает

на hq-srv 

nano /etc/nftabes.conf

добавить строчки

table inet filter {
	chain imput {
		type filter hook input priority filter; policy accept;
		ip sadddr 3.3.3.2 tcp dport 2222 counter reject
		ip saddr 4.4.4.0/30 tcp dport 2222 counter reject
	}		
systemctl enable --now nftables

со всех виртуалок

ssh "пользователь на HQ-R"@"айпи сервера" -p 2222
если управляется компом дистанционно - работает

с cli

ssh "пользователь на HQ-R"@"айпи соединения cli и hq-r" -p 2222
connection refused - все прально значит епта!
