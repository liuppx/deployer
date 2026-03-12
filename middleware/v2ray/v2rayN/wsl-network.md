# WSL 网络稳定化配置

## 1. 固定 DNS（推荐）

```bash
sudo tee /etc/wsl.conf >/dev/null <<'CFG'
[network]
generateResolvConf = false
CFG

sudo rm -f /etc/resolv.conf
sudo tee /etc/resolv.conf >/dev/null <<'DNS'
nameserver 1.1.1.1
nameserver 8.8.8.8
DNS

cat /etc/wsl.conf
cat /etc/resolv.conf
```

## 2. 代理环境变量（可选）

```bash
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
export ALL_PROXY="socks5h://$HOST_IP:10810"
export http_proxy="$ALL_PROXY"
export https_proxy="$ALL_PROXY"
```

## 3. 验证

```bash
curl --socks5-hostname "$HOST_IP:10810" https://api.ipify.org
curl -I https://www.google.com
```
