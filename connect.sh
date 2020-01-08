#! /bin/bash

mkdir -p ~/.wgcf
chmod 700 ~/.wgcf
prv=~/.wgcf/private.key
usr=~/.wgcf/identity.cfg

tun="wg09"
sudo ip link delete ${tun}
sudo ip link add dev "${tun}" type wireguard
echo "Will use interface: ${tun}"

if [ -e "${usr}" ]; then
    echo "Identity already exists!"

    token=($(cat "${usr}"))
    test "${#token[@]}" -eq 2

    reg=$(curl -s -H 'user-agent:' -H 'content-type: application/json' -H 'authorization: Bearer '"${token[1]}"'' -X "GET" https://api.cloudflareclient.com/v0i1909051800/reg/${token[0]})
    cfg=($(echo $reg | jq -r '.result.config|(.peers[0]|.public_key+" "+.endpoint.v4)+" "+.interface.addresses.v4'))
    echo $reg
else
    pub=$({ cat "${prv}" 2>/dev/null || wg genkey | tee "${prv}"; } | wg pubkey)
    test -n "${pub}"
    echo "Generated public key: ${pub}"
    echo "Private key generated and saved to ${prv}. Reused if already existed."

    reg=$(curl -s -H 'user-agent:' -H 'content-type: application/json' -X "POST" -d '{"install_id":"","tos":"'"$(date -u +%FT%T.000Z)"'","key":"'"${pub}"'","fcm_token":"","type":"ios","locale":"en_US"}' https://api.cloudflareclient.com/v0i1909051800/reg)
    token=($(echo $reg | jq -r '.result|.id+" "+.token'))
    echo "Cloudflare responded with identity: ${token}"
    test "${#token[@]}" -eq 2
    echo "${token[@]}" > "${usr}"
    echo "Saved token to ${usr}"

    cfg=($(echo $reg | jq -r '.result.config|(.peers[0]|.public_key+" "+.endpoint.v4)+" "+.interface.addresses.v4'))
    test "${#cfg[@]}" -eq 3
    echo "Peer: ${cfg[0]}"
    echo "Endpoint: ${cfg[1]}"
    echo "Interface address: ${cfg[2]}"

    curl -s -H 'user-agent:' -H 'content-type: application/json' -H 'authorization: Bearer '"${reg[1]}"'' -X "PATCH" -d '"warp_enabled":true' 'https://api.cloudflareclient.com/v0i1909051800/reg/${token[0]}'
    echo "Requested Cloudflare enable WARP for new identity."
fi

end=${cfg[1]%:*}
echo "${end}"
sudo route -n delete "${end}" 2>/dev/null || true
sudo route -n add "${end}" gw 192.168.0.1 # Need to determine gateway in script.

sudo ifconfig "${tun}" inet "${cfg[2]}" "${cfg[2]}" netmask 255.255.255.255
sudo wg set "${tun}" private-key "${prv}" peer "${cfg[0]}" endpoint "${cfg[1]}" allowed-ips 0.0.0.0/0

sudo route add -net 0.0.0.0 netmask 128.0.0.0 dev ${tun}
sudo route add -net 128.0.0.0 netmask 128.0.0.0 dev ${tun}
