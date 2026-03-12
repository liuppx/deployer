# portproxy：让 WSL 用上 Windows 的 v2rayN 代理

## 背景

v2rayN 通常监听 `127.0.0.1:10808`（Windows 回环地址）。
WSL 程序不能稳定直接访问该回环地址，因此需要桥接。

## 配置命令（管理员 PowerShell）

```powershell
# 查看规则
netsh interface portproxy show v4tov4

# 删除旧规则（不存在可忽略）
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=10810

# 新增桥接：WSL -> Windows v2rayN
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=10810 connectaddress=127.0.0.1 connectport=10808

# 校验
netsh interface portproxy show v4tov4
```

预期出现：

```text
0.0.0.0         10810       127.0.0.1       10808
```

## 验证

Windows：
```powershell
netstat -ano | findstr :10808
curl.exe -x socks5h://127.0.0.1:10808 https://api.ipify.org
```

WSL：
```bash
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
curl --socks5-hostname "$HOST_IP:10810" https://api.ipify.org
```
