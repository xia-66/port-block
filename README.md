# port-block

用于在 Debian/Ubuntu 服务器上通过 nftables 屏蔽指定国家/地区 IP 访问本机指定端口。默认屏蔽 `cn` 到本机 `55555` 端口，协议默认 `tcp + udp`。

## 一键安装

本地运行：

```bash
sudo bash install.sh
```

上传到 GitHub 后运行：

```bash
curl -fsSL https://raw.githubusercontent.com/xia-66/port-block/main/install.sh | sudo GITHUB_REPO=xia-66/port-block bash
```

如果主分支不是 `main`：

```bash
curl -fsSL https://raw.githubusercontent.com/xia-66/port-block/main/install.sh | sudo GITHUB_REPO=xia-66/port-block GITHUB_BRANCH=master bash
```

## 常用命令

打开交互菜单：

```bash
sudo bash port-block.sh menu
```

直接安装：

```bash
sudo PORT=55555 COUNTRY=cn PROTO=both bash port-block.sh install
```

修改端口：

```bash
sudo bash port-block.sh change-port
```

查看状态：

```bash
sudo PORT=55555 bash port-block.sh status
```

卸载：

```bash
sudo PORT=55555 bash port-block.sh uninstall
```

手动更新 IP 段：

```bash
sudo PORT=55555 bash port-block.sh update
```

## 参数

- `PORT`：本机端口，默认 `55555`
- `COUNTRY`：国家/地区代码，默认 `cn`
- `PROTO`：协议，可选 `both`、`tcp`、`udp`，默认 `both`

安装后会创建 systemd timer，每周自动更新一次 IP 段。
