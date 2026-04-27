
## 查看`git`配置

```bash
# 查看当前项目配置
git config -l

# 查看全局配置
git config --global -l
```

## 配置`Git`代理
在开发环境中配置代理：
- 本地开启了`sock5`代理且端口是`1080`
- 安装依赖`apt install connect-proxy`
- 在配置文件$HOME/.ssh/config添加代理
### 方案1
```text
Host github.com
    HostName github.com
    User git
    ProxyCommand connect -S 127.0.0.1:1080 %h %p
```
### 方案2
```bash
git config --global https.proxy socks5h://127.0.0.1:1080
git config --global http.proxy socks5h://127.0.0.1:1080
```

## 添加`Github`公钥
- 在当前开发环境中生成公私钥对`ssh-keygen`，公钥文件默认是`$HOME/.ssh/id_ed25519.pub`
- 登陆Github -> 点击右上角头像 -> Settings (设置) -> 在左侧菜单找到 SSH and GPG keys -> 点击绿色的 New SSH key 按钮 -> 粘贴公钥文件中的内容到*key* -> 点击 Add SSH key
- 在开发环境上执行`ssh -T git@github.com`，查看当时登陆的Github账号

## 配置`Git`账户
在开发环境中配置用户名和邮箱：
```bash
git config --global user.name "你的GitHub用户名"
git config --global user.email "你的GitHub邮箱"
```

## Git中文显示
使用`git status` 能够正确显示中文，而不是显示转义的乱码
```bash
git config core.quotepath false
```

## 常用命令
```bash
# 删除上游
git remote remove upstream

# 删除本地TAG
git tag -d <tag name>

# 删除远端TAG
git push origin :<tag name>

# 修改远程仓库地址
git remote set-url origin <请使用git协议地址>

```
