#!/bin/bash

mkdir pihole_docker
cp pi-hole.conf pihole_docker
cd pihole_docker

# https://github.com/pi-hole/docker-pi-hole/blob/master/README.md

PIHOLE_BASE="${PIHOLE_BASE:-$(pwd)}"
[[ -d "$PIHOLE_BASE" ]] || mkdir -p "$PIHOLE_BASE" || { echo "Couldn't create storage directory: $PIHOLE_BASE"; exit 1; }

# Note: FTLCONF_LOCAL_IPV4 should be replaced with your external ip.
docker run -d \
    --name pihole \
    -p 127.0.0.1:53:53/tcp -p 127.0.0.1:53:53/udp \
    -p 80:80 \
    -e TZ="Europe/Berlin" \
    -v "${PIHOLE_BASE}/etc-pihole:/etc/pihole" \
    -v "${PIHOLE_BASE}/etc-dnsmasq.d:/etc/dnsmasq.d" \
    --dns=9.9.9.9 --dns 1.1.1.1 \
    --restart=unless-stopped \
    --hostname pi.hole \
    -e VIRTUAL_HOST="pi.hole" \
    -e PROXY_LOCATION="pi.hole" \
    -e FTLCONF_LOCAL_IPV4="127.0.0.1" \
    pihole/pihole:latest

printf 'Starting up pihole container '
for i in $(seq 1 20); do
    if [ "$(docker inspect -f "{{.State.Health.Status}}" pihole)" == "healthy" ] ; then
        printf ' OK'
        echo -e "\n$(docker logs pihole 2> /dev/null | grep 'password:') for your pi-hole: http://${IP}/admin/"
        docker exec -it pihole apt-get update
        docker exec -it pihole apt-get upgrade -y
        docker exec -it pihole apt-get full-upgrade -y
        docker exec -it pihole apt autoremove -y
        docker exec -it pihole apt-get install unbound -y
        docker exec -it pihole apt-get install wget -y
        docker cp ./pi-hole.conf pihole://etc/unbound/unbound.conf.d
        docker exec -it pihole wget https://www.internic.net/domain/named.root -O /var/lib/unbound/root.hints
        docker exec -it pihole unbound-anchor
        docker exec -it pihole mkdir /var/log/unbound
        docker exec -it pihole sh -c 'sed -i '/PIHOLE_DNS_1/d' /etc/pihole/setupVars.conf'
        docker exec -it pihole sh -c 'sed -i '/PIHOLE_DNS_2/d' /etc/pihole/setupVars.conf'
        docker exec -it pihole sh -c 'echo DNSSEC=true >> /etc/pihole/setupVars.conf'
        docker exec -it pihole sh -c 'echo PIHOLE_DNS_1=127.0.0.1#5335 >> /etc/pihole/setupVars.conf'
        docker exec -it pihole sh -c 'sed  -i "1i /etc/init.d/unbound restart" /opt/pihole/updatecheck.sh'
        docker restart pihole
#        docker exec -it pihole /etc/init.d/unbound restart

        exit 0
    else
        sleep 3
        printf '.'
    fi

    if [ $i -eq 20 ] ; then
        echo -e "\nTimed out waiting for Pi-hole start, consult your container logs for more info (\`docker logs pihole\`)"
        exit 1
    fi
done;
